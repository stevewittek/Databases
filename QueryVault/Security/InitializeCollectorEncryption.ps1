<#
.SYNOPSIS
Creates a per-installation Windows certificate and an Always Encrypted credential table.
.DESCRIPTION
Run as the intended collector Windows identity, with temporary schema/key administration
permissions on the archive. Does not install dependencies, enable sources, or store passwords.
Use a new backup directory outside the checkout. The encrypted PFX must be copied to
independent protected storage before treating this installation as recoverable.
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$Database,
    [string]$CollectorSid,
    [string]$BackupDirectory,
    [securestring]$BackupPassword,
    [pscredential]$ArchiveCredential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-QVCollectorIdentity {
    param([string]$ExpectedSid)
    if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)) {
        throw 'This bootstrap requires Windows and its certificate store. No database changes were attempted.'
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedSid)) { throw 'CollectorSid is required.' }
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -cne $ExpectedSid) { throw 'Run this script as the declared collector identity; SID does not match.' }
}

function Resolve-QVNewBackupDirectory {
    param([string]$Path, [string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) {
        throw 'BackupDirectory must be an absolute path to a new directory.'
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $repo = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($full.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Key backup must be outside the repository.'
    }
    if (Test-Path -LiteralPath $full) { throw 'BackupDirectory already exists; refusing to overwrite or reuse it.' }
    $parent = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($full))
    if (-not $parent.Exists) { throw 'The parent of BackupDirectory must already exist.' }
    for ($p = $parent; $null -ne $p; $p = $p.Parent) {
        if (($p.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Key backup path cannot traverse a reparse point.'
        }
    }
    return $full
}

function Import-QVSqlClient {
    Import-Module SqlServer -MinimumVersion 22.0 -ErrorAction Stop
    if ($null -eq ('Microsoft.Data.SqlClient.SqlConnection' -as [type])) {
        throw 'The installed SqlServer module did not load Microsoft.Data.SqlClient.'
    }
}

function Resolve-QVInstallationRoot {
    param([string]$ScriptDirectory)
    $scripts = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($ScriptDirectory))
    if ($scripts.Name -eq 'Security' -and $null -ne $scripts.Parent -and
        $scripts.Parent.Name -eq 'QueryVault' -and $null -ne $scripts.Parent.Parent -and
        (Test-Path -LiteralPath (Join-Path $scripts.Parent.FullName 'QueryVault.sqlproj') -PathType Leaf)) {
        return $scripts.Parent.Parent.FullName
    }
    if ($scripts.Name -eq 'setup' -and $null -ne $scripts.Parent -and
        (Test-Path -LiteralPath (Join-Path $scripts.Parent.FullName 'QueryVault.dacpac') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $scripts.Parent.FullName 'manifest.json') -PathType Leaf)) {
        return $scripts.Parent.FullName
    }
    throw 'Cannot identify the QueryVault source/package root. Keep setup scripts in the distributed layout.'
}

function New-QVArchiveConnection {
    param([string]$Server, [string]$Database, [pscredential]$ArchiveCredential)
    if ([string]::IsNullOrWhiteSpace($Server) -or [string]::IsNullOrWhiteSpace($Database)) {
        throw 'Server and Database are required.'
    }
    if ($Database -in @('master', 'model', 'msdb', 'tempdb')) { throw 'System databases are not permitted.' }
    $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder.DataSource = $Server
    $builder.InitialCatalog = $Database
    $builder['Encrypt'] = 'True'
    $builder.TrustServerCertificate = $false
    $builder['Column Encryption Setting'] = 'Enabled'
    $builder.PersistSecurityInfo = $false
    $builder.ConnectTimeout = 30
    # Provisioning must bind key trust to one opened endpoint, without idle reconnect.
    $builder.ConnectRetryCount = 0
    $builder.ApplicationName = 'QueryVault credential provisioning'
    $builder.IntegratedSecurity = ($null -eq $ArchiveCredential)
    $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    if ($ArchiveCredential) {
        $password = $ArchiveCredential.Password.Copy()
        $password.MakeReadOnly()
        $connection.Credential = [Microsoft.Data.SqlClient.SqlCredential]::new($ArchiveCredential.UserName, $password)
    }
    return $connection
}

function Set-QVTrustedMasterKeyPath {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][string]$KeyPath,
        [Parameter(Mandatory)]
        [System.Collections.Generic.IDictionary[string,System.Collections.Generic.IList[string]]]$TrustedPaths
    )
    if ($Connection.State -ne [Data.ConnectionState]::Open) {
        throw 'Open the archive connection before binding its trusted key path.'
    }
    $effectiveServer = [string]$Connection.DataSource
    if ([string]::IsNullOrWhiteSpace($effectiveServer) -or [string]::IsNullOrWhiteSpace($KeyPath)) {
        throw 'An explicit opened endpoint and trusted key path are required.'
    }
    $paths = [System.Collections.Generic.List[string]]::new()
    $paths.Add($KeyPath)
    $TrustedPaths[$effectiveServer] = $paths
    if (-not $TrustedPaths.ContainsKey($effectiveServer) -or
        $TrustedPaths[$effectiveServer].Count -ne 1 -or
        $TrustedPaths[$effectiveServer][0] -cne $KeyPath) {
        throw 'Cannot establish the approved key path for this archive endpoint.'
    }
}

function Initialize-QueryVaultCollectorEncryption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$CollectorSid,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [securestring]$BackupPassword,
        [pscredential]$ArchiveCredential
    )
    Assert-QVCollectorIdentity $CollectorSid
    $repo = Resolve-QVInstallationRoot $PSScriptRoot
    $backup = Resolve-QVNewBackupDirectory $BackupDirectory $repo
    Import-QVSqlClient
    if (-not $BackupPassword) { $BackupPassword = Read-Host 'Password for encrypted recovery PFX' -AsSecureString }
    if ($BackupPassword.Length -lt 16) { throw 'Use a recovery password of at least 16 characters.' }
    $connection = New-QVArchiveConnection $Server $Database $ArchiveCredential
    $transaction = $null
    $key = $null
    try {
        $connection.Open()
        $check = $connection.CreateCommand()
        $check.CommandText = @'
IF OBJECT_ID(N'dbo.CollectionCredential', N'U') IS NULL
    THROW 51300, 'Deploy the QueryVault registry first.', 1;
IF OBJECT_ID(N'dbo.CollectionCredentialSecret') IS NOT NULL
 OR EXISTS (SELECT 1 FROM sys.column_master_keys WHERE name=N'QV_CredentialCMK')
 OR EXISTS (SELECT 1 FROM sys.column_encryption_keys WHERE name=N'QV_CredentialCEK')
    THROW 51301, 'Encryption objects already exist. Review recovery or rotation; do not overwrite keys.', 1;
'@
        [void]$check.ExecuteNonQuery()
        # Apply a protected ACL to a new backup directory before writing any private material.
        $directory = [IO.Directory]::CreateDirectory($backup)
        $acl = [System.Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sidValue in @($CollectorSid, 'S-1-5-18')) {
            $sid = [System.Security.Principal.SecurityIdentifier]::new($sidValue)
            $rule = [System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl',
                'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $directory.FullName -AclObject $acl
        $cert = New-SelfSignedCertificate -Subject ('CN=QueryVault-' + [guid]::NewGuid()) `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 3072 `
            -KeySpec KeyExchange -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' `
            -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(5)
        $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
        try {
            if ($privateKey -isnot [System.Security.Cryptography.RSACryptoServiceProvider] -or
                $privateKey.CspKeyContainerInfo.MachineKeyStore) {
                throw 'Expected a CurrentUser CSP private key.'
            }
            $keyFile = Join-Path ([Environment]::GetFolderPath('ApplicationData')) `
                ('Microsoft\Crypto\RSA\' + $CollectorSid + '\' + $privateKey.CspKeyContainerInfo.UniqueKeyContainerName)
            if (-not (Test-Path -LiteralPath $keyFile -PathType Leaf)) { throw 'Cannot identify the generated private-key file.' }
            $keyAcl = [System.Security.AccessControl.FileSecurity]::new()
            $keyAcl.SetAccessRuleProtection($true, $false)
            foreach ($sidValue in @($CollectorSid, 'S-1-5-18')) {
                $sid = [System.Security.Principal.SecurityIdentifier]::new($sidValue)
                $keyAcl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow'))
            }
            Set-Acl -LiteralPath $keyFile -AclObject $keyAcl
        } finally { if ($privateKey) { $privateKey.Dispose() } }
        $pfx = Join-Path $backup 'QueryVault-collector-key.pfx'
        Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $BackupPassword `
            -CryptoAlgorithmOption AES256_SHA256 -ChainOption EndEntityCertOnly | Out-Null
        # Verify the exported backup contains the same private key before database provisioning.
        $restored = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $pfx, $BackupPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        try {
            if (-not $restored.HasPrivateKey -or $restored.Thumbprint -ne $cert.Thumbprint) {
                throw 'Recovery PFX verification failed.'
            }
        } finally { $restored.Dispose() }
        $keyPath = 'CurrentUser/My/' + $cert.Thumbprint
        $key = [byte[]]::new(32)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($key) } finally { $rng.Dispose() }
        $provider = [Microsoft.Data.SqlClient.SqlColumnEncryptionCertificateStoreProvider]::new()
        $wrapped = $provider.EncryptColumnEncryptionKey($keyPath, 'RSA_OAEP', $key)
        $hex = '0x' + [BitConverter]::ToString($wrapped).Replace('-', '')
        $transaction = $connection.BeginTransaction()
        $command = $connection.CreateCommand()
        $command.Transaction = $transaction
        $command.CommandText = @"
CREATE COLUMN MASTER KEY [QV_CredentialCMK]
 WITH (KEY_STORE_PROVIDER_NAME=N'MSSQL_CERTIFICATE_STORE', KEY_PATH=N'$keyPath');
CREATE COLUMN ENCRYPTION KEY [QV_CredentialCEK]
 WITH VALUES (COLUMN_MASTER_KEY=[QV_CredentialCMK], ALGORITHM='RSA_OAEP', ENCRYPTED_VALUE=$hex);
CREATE TABLE dbo.CollectionCredentialSecret
(
 CredentialID UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_CollectionCredentialSecret PRIMARY KEY,
 UserName NVARCHAR(128) COLLATE Latin1_General_BIN2 ENCRYPTED WITH
   (COLUMN_ENCRYPTION_KEY=[QV_CredentialCEK], ENCRYPTION_TYPE=RANDOMIZED, ALGORITHM='AEAD_AES_256_CBC_HMAC_SHA_256') NOT NULL,
 SecretValue NVARCHAR(512) COLLATE Latin1_General_BIN2 ENCRYPTED WITH
   (COLUMN_ENCRYPTION_KEY=[QV_CredentialCEK], ENCRYPTION_TYPE=RANDOMIZED, ALGORITHM='AEAD_AES_256_CBC_HMAC_SHA_256') NOT NULL,
 CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_CollectionCredentialSecret_Created DEFAULT SYSUTCDATETIME(),
 CONSTRAINT FK_CollectionCredentialSecret_Metadata FOREIGN KEY(CredentialID)
   REFERENCES dbo.CollectionCredential(CredentialID)
);
"@
        [void]$command.ExecuteNonQuery()
        $transaction.Commit()
        $transaction.Dispose()
        $transaction = $null
        @{ Server=$Server; Database=$Database; CollectorSid=$CollectorSid; KeyPath=$keyPath;
           CertificateThumbprint=$cert.Thumbprint; CreatedUtc=[DateTime]::UtcNow.ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'installation.json') -Encoding utf8
        Write-Output 'Encryption schema provisioned. Keep the encrypted recovery PFX and its password separately; sources remain disabled.'
    } catch {
        if ($transaction) { try { $transaction.Rollback() } catch {} }
        # Never emit nested SQL/driver errors that might contain parameter values.
        throw 'Encryption provisioning failed. No keys are overwritten automatically. Inspect target state and the protected backup directory before retrying.'
    } finally {
        if ($key) { [Array]::Clear($key, 0, $key.Length) }
        if ($transaction) { $transaction.Dispose() }
        $connection.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Initialize-QueryVaultCollectorEncryption @PSBoundParameters
}

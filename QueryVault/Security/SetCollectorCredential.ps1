<# Inserts a new credential using Always Encrypted. No secret replacement, source enablement,
   key rotation or plaintext fallback. SourceCredential must come from Get-Credential. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][string]$Database,
    [Parameter(Mandatory)][string]$CollectorSid,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{40}$')][string]$CertificateThumbprint,
    [Parameter(Mandatory)][guid]$CredentialID,
    [Parameter(Mandatory)][pscredential]$SourceCredential,
    [pscredential]$ArchiveCredential
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$bootstrapArguments = @{ Server=$Server; Database=$Database; CollectorSid=$CollectorSid; ArchiveCredential=$ArchiveCredential }
. (Join-Path $PSScriptRoot 'InitializeCollectorEncryption.ps1') @bootstrapArguments
Assert-QVCollectorIdentity $CollectorSid
Import-QVSqlClient
if ([string]::IsNullOrWhiteSpace($SourceCredential.UserName) -or $SourceCredential.UserName.Length -gt 128 -or
    $SourceCredential.Password.Length -lt 1 -or $SourceCredential.Password.Length -gt 512) {
    throw 'Credential username/password length is outside the supported range.'
}
$keyPath = 'CurrentUser/My/' + $CertificateThumbprint.ToUpperInvariant()
$cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint)
if (-not $cert.HasPrivateKey) { throw 'The collector identity cannot access the expected private key.' }
$connection = New-QVArchiveConnection $Server $Database $ArchiveCredential
$transaction = $null
$pointer = [IntPtr]::Zero
$plainPassword = $null
try {
    $connection.Open()
    # SqlClient looks up trust using the opened connection's DataSource, which can
    # differ from the supplied alias. Bind before issuing any encrypted SQL.
    Set-QVTrustedMasterKeyPath -Connection $connection -KeyPath $keyPath `
        -TrustedPaths ([Microsoft.Data.SqlClient.SqlConnection]::ColumnEncryptionTrustedMasterKeyPaths)
    $transaction = $connection.BeginTransaction()
    $check = $connection.CreateCommand()
    $check.Transaction = $transaction
    $check.CommandText = @'
IF NOT EXISTS (SELECT 1 FROM dbo.CollectionCredential WITH (UPDLOCK,HOLDLOCK)
               WHERE CredentialID=@id AND EnrollmentState='PENDING')
    THROW 51302, 'A pending credential registration is required.', 1;
IF EXISTS (SELECT 1 FROM dbo.CollectionCredentialSecret WHERE CredentialID=@id)
    THROW 51303, 'Credential already enrolled. Rotation requires a separate reviewed operation.', 1;
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.CollectionCredentialSecret')
    AND name IN (N'UserName',N'SecretValue') AND encryption_type=2) <> 2
    THROW 51304, 'Expected randomized encrypted columns are missing.', 1;
'@
    [void]$check.Parameters.Add('@id', [Data.SqlDbType]::UniqueIdentifier)
    $check.Parameters['@id'].Value = $CredentialID
    [void]$check.ExecuteNonQuery()
    $command = $connection.CreateCommand()
    $command.Transaction = $transaction
    $command.CommandText = 'INSERT dbo.CollectionCredentialSecret(CredentialID,UserName,SecretValue) VALUES (@id,@user,@secret);'
    [void]$command.Parameters.Add('@id', [Data.SqlDbType]::UniqueIdentifier)
    $command.Parameters['@id'].Value = $CredentialID
    [void]$command.Parameters.Add('@user', [Data.SqlDbType]::NVarChar, 128)
    $command.Parameters['@user'].ForceColumnEncryption = $true
    $command.Parameters['@user'].Value = $SourceCredential.UserName
    [void]$command.Parameters.Add('@secret', [Data.SqlDbType]::NVarChar, 512)
    $command.Parameters['@secret'].ForceColumnEncryption = $true
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SourceCredential.Password)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    $command.Parameters['@secret'].Value = $plainPassword
    [void]$command.ExecuteNonQuery()
    $transaction.Commit()
    $transaction.Dispose()
    $transaction = $null
    Write-Output 'Credential encrypted and enrolled. Collector readiness and source enablement remain separate acceptance gates.'
} catch {
    if ($transaction) { try { $transaction.Rollback() } catch {} }
    throw 'Credential enrollment failed; no plaintext fallback was attempted. Check the protected key, schema and permissions without logging secret values.'
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    if (Get-Variable command -ErrorAction SilentlyContinue) { $command.Parameters.Clear(); $command.Dispose() }
    $plainPassword = $null
    if ($transaction) { $transaction.Dispose() }
    $connection.Dispose()
}

<# Offline preflight checks only. Does not claim Windows cryptographic/SQL acceptance. #>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bootstrap = Join-Path $root 'QueryVault/Security/InitializeCollectorEncryption.ps1'
$enrollment = Join-Path $root 'QueryVault/Security/SetCollectorCredential.ps1'

function Assert-Throws {
    param([scriptblock]$Action, [string]$Expected)
    $caught = $false
    try { & $Action | Out-Null } catch {
        $caught = $true
        if ($_.Exception.Message -notlike "*$Expected*") { throw "Unexpected failure: $($_.Exception.Message)" }
    }
    if (-not $caught) { throw "Expected rejection: $Expected" }
}
foreach ($path in @($bootstrap, $enrollment)) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ($errors.Message -join '; ') }
}
. $bootstrap
$trustedPaths = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.IList[string]]]::new()
$expectedKey = 'CurrentUser/My/0123456789012345678901234567890123456789'
$opened = [pscustomobject]@{State=[Data.ConnectionState]::Open;DataSource='resolved-alias.example,14330'}
Set-QVTrustedMasterKeyPath -Connection $opened -KeyPath $expectedKey -TrustedPaths $trustedPaths
if ($trustedPaths.Count -ne 1 -or $trustedPaths[$opened.DataSource][0] -cne $expectedKey) {
    throw 'Trusted key was not bound to the effective opened endpoint.'
}
$closed = [pscustomobject]@{State=[Data.ConnectionState]::Closed;DataSource='input-alias.example'}
Assert-Throws { Set-QVTrustedMasterKeyPath -Connection $closed -KeyPath $expectedKey -TrustedPaths $trustedPaths } 'Open the archive'
$noEndpoint = [pscustomobject]@{State=[Data.ConnectionState]::Open;DataSource=' '}
Assert-Throws { Set-QVTrustedMasterKeyPath -Connection $noEndpoint -KeyPath $expectedKey -TrustedPaths $trustedPaths } 'explicit opened endpoint'
if ($trustedPaths.Count -ne 1) { throw 'Failed endpoint validation changed the trust allowlist.' }
$temp = Join-Path $root ('artifacts/qv-encryption-preflight-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($temp)
try {
    $repository = Join-Path $temp 'repo'
    [void][IO.Directory]::CreateDirectory($repository)
    $sourceScripts = Join-Path $repository 'QueryVault/Security'
    [void][IO.Directory]::CreateDirectory($sourceScripts)
    [IO.File]::WriteAllText((Join-Path $repository 'QueryVault/QueryVault.sqlproj'), '<Project/>')
    if ((Resolve-QVInstallationRoot $sourceScripts) -ne $repository) { throw 'Source root detection failed.' }
    $package = Join-Path $temp 'package'
    $packageScripts = Join-Path $package 'setup'
    [void][IO.Directory]::CreateDirectory($packageScripts)
    [IO.File]::WriteAllText((Join-Path $package 'QueryVault.dacpac'), '')
    [IO.File]::WriteAllText((Join-Path $package 'manifest.json'), '{}')
    if ((Resolve-QVInstallationRoot $packageScripts) -ne $package) { throw 'Package root detection failed.' }
    Assert-Throws { Resolve-QVInstallationRoot $temp } 'Cannot identify'
    Assert-Throws { Resolve-QVNewBackupDirectory (Join-Path $package 'key') $package } 'outside the repository'
    $packageBackup = Join-Path $temp 'package-key-backup'
    if ((Resolve-QVNewBackupDirectory $packageBackup (Resolve-QVInstallationRoot $packageScripts)) -ne $packageBackup) {
        throw 'A sibling package backup was incorrectly rejected.'
    }
    Assert-Throws { Resolve-QVNewBackupDirectory 'relative/path' $repository } 'absolute path'
    Assert-Throws { Resolve-QVNewBackupDirectory (Join-Path $repository 'key') $repository } 'outside the repository'
    Assert-Throws { Resolve-QVNewBackupDirectory $temp $repository } 'already exists'
    Assert-Throws { Resolve-QVNewBackupDirectory (Join-Path $temp 'missing/key') $repository } 'parent'
    $valid = Join-Path $temp 'independent-key-backup'
    if ((Resolve-QVNewBackupDirectory $valid $repository) -ne $valid) { throw 'Unexpected normalized path.' }
    if (Test-Path -LiteralPath $valid) { throw 'Backup preflight created a directory.' }
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
        Assert-Throws { Initialize-QueryVaultCollectorEncryption -Server 'invalid.example' -Database 'NeverConnect' `
            -CollectorSid 'S-1-5-21-1-2-3-1001' -BackupDirectory $valid } 'requires Windows'
        if (Test-Path -LiteralPath $valid) { throw 'Unsupported platform mutated the filesystem.' }
    } else {
        Assert-Throws { Assert-QVCollectorIdentity 'S-1-0-0' } 'SID does not match'
    }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Output 'PASS: script parsing, opened-endpoint key binding, source/package layout detection, backup path guards, side-effect-free preflight and platform/identity rejection. Windows AE integration remains pending.'

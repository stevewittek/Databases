<#
.SYNOPSIS
	Runs the complete local QueryVault production deployment safety sequence.
#>

[CmdletBinding()]
param(
	[Parameter()]
	[string]$ServerInstance = "localhost",

	[Parameter()]
	[string]$DatabaseName = "QueryVaultDB",

	[Parameter()]
	[string]$BaselineRoot = "/home/nasa/queryvault-production/baselines",

	[Parameter()]
	[string]$BackupRoot = "/var/opt/mssql/userlog/backups/voyager2/QueryVaultDB/FULL",

	[Parameter()]
	[string]$GitSha = $env:GITHUB_SHA,

	[Parameter()]
	[PSCredential]$Credential,

	[Parameter()]
	[switch]$TrustServerCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$shaLabel = if ([string]::IsNullOrWhiteSpace($GitSha)) { "manual" } else { ($GitSha -replace '[^A-Za-z0-9]', '').Substring(0,[Math]::Min(12,($GitSha -replace '[^A-Za-z0-9]', '').Length)) }
$baselinePath = Join-Path $BaselineRoot "QueryVaultDB_${timestamp}_${shaLabel}.json"

$common = @{
	ServerInstance = $ServerInstance
	DatabaseName = $DatabaseName
}
if ($Credential) { $common.Credential = $Credential }
if ($TrustServerCertificate) { $common.TrustServerCertificate = $true }

$startedUtc = [DateTime]::UtcNow
Write-Host "QueryVault production sequence started: $($startedUtc.ToString('o'))" -ForegroundColor Cyan
Write-Host "Git SHA: $(if ($GitSha) { $GitSha } else { 'not-supplied' })"

try {
	& (Join-Path $PSScriptRoot "TestQueryVaultDeployment.ps1") @common -Mode Pre -BaselinePath $baselinePath
	$backupPath = & (Join-Path $PSScriptRoot "BackupQueryVault.ps1") @common -BackupRoot $BackupRoot
	& (Join-Path $PSScriptRoot "DeployQueryVault.ps1") @common -GitSha $GitSha
	& (Join-Path $PSScriptRoot "TestQueryVaultDeployment.ps1") @common -Mode Post -BaselinePath $baselinePath

	Write-Host "QueryVault production sequence passed." -ForegroundColor Green
	Write-Host "Baseline: $baselinePath"
	Write-Host "Verified backup: $backupPath"
	Write-Host "Completed UTC: $([DateTime]::UtcNow.ToString('o'))"
}
catch {
	Write-Error "QueryVault production sequence stopped safely: $($_.Exception.Message)"
	throw
}

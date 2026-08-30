<#
.SYNOPSIS
	Creates and verifies a copy-only QueryVault production backup.
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$ServerInstance,

	[Parameter()]
	[string]$DatabaseName = "QueryVaultDB",

	[Parameter()]
	[string]$BackupRoot = "/var/opt/mssql/userlog/backups/voyager2/QueryVaultDB/FULL",

	[Parameter()]
	[PSCredential]$Credential,

	[Parameter()]
	[switch]$TrustServerCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($DatabaseName -notmatch '^[A-Za-z_][A-Za-z0-9_@$#-]{0,127}$') {
	throw "DatabaseName contains unsupported characters: $DatabaseName"
}

if (-not $Credential -and $env:QUERYVAULT_SQL_USER -and $env:QUERYVAULT_SQL_PASSWORD) {
	$securePassword = ConvertTo-SecureString $env:QUERYVAULT_SQL_PASSWORD -AsPlainText -Force
	$Credential = [PSCredential]::new($env:QUERYVAULT_SQL_USER, $securePassword)
}

$module = Get-Module -ListAvailable -Name SqlServer | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) { throw "Required PowerShell module 'SqlServer' is missing." }
Import-Module SqlServer -ErrorAction Stop

function New-ConnectionParameters {
	param([string]$Database, [int]$QueryTimeout = 1800)
	$params = @{
		ServerInstance = $ServerInstance
		Database = $Database
		QueryTimeout = $QueryTimeout
		AbortOnError = $true
		ErrorAction = "Stop"
	}
	if ($Credential) { $params.Credential = $Credential }
	if ($TrustServerCertificate) { $params.TrustServerCertificate = $true }
	return $params
}

$stateParams = New-ConnectionParameters -Database "master" -QueryTimeout 30
$dbState = Invoke-Sqlcmd @stateParams -Query "SET NOCOUNT ON; SELECT state_desc AS StateDescription FROM sys.databases WHERE name=N'$DatabaseName';" -Verbose:$false
if (-not $dbState) { throw "Target database '$DatabaseName' does not exist." }
if ($dbState.StateDescription -ne "ONLINE") { throw "Target database '$DatabaseName' is not ONLINE." }

$timestamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$backupFile = Join-Path $BackupRoot "voyager2_${DatabaseName}_FULL_${timestamp}_predeploy_copyonly.bak"
$escapedBackupFile = $backupFile.Replace("'", "''")

$backupQuery = @"
SET NOCOUNT ON;
BACKUP DATABASE [$DatabaseName]
TO DISK=N'$escapedBackupFile'
WITH COPY_ONLY,COMPRESSION,CHECKSUM,INIT,STATS=10;

RESTORE VERIFYONLY
FROM DISK=N'$escapedBackupFile'
WITH CHECKSUM;

SELECT N'$DatabaseName' AS DatabaseName,
       CONVERT(bit,1) AS IsCopyOnly,
       CONVERT(bit,1) AS HasChecksums,
       SYSUTCDATETIME() AS BackupFinishDate,
       N'$escapedBackupFile' AS BackupPath;
"@

$backupParams = New-ConnectionParameters -Database "master" -QueryTimeout 1800
$result = Invoke-Sqlcmd @backupParams -Query $backupQuery -Verbose:$false | Select-Object -Last 1
if (-not $result) { throw "Backup completed without a verifiable msdb history record." }
if (-not [bool]$result.IsCopyOnly) { throw "Backup history does not mark the backup as COPY_ONLY." }
if (-not [bool]$result.HasChecksums) { throw "Backup history does not contain checksums." }

Write-Host "Verified copy-only backup: $backupFile" -ForegroundColor Green
Write-Output $backupFile

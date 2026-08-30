<#
.SYNOPSIS
	Captures and validates QueryVault state before or after production deployment.
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidateSet("Pre", "Post")]
	[string]$Mode,

	[Parameter(Mandatory = $true)]
	[string]$ServerInstance,

	[Parameter()]
	[string]$DatabaseName = "QueryVaultDB",

	[Parameter(Mandatory = $true)]
	[string]$BaselinePath,

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
if (-not $module) {
	throw "Required PowerShell module 'SqlServer' is missing."
}
Import-Module SqlServer -ErrorAction Stop

function New-ConnectionParameters {
	param([string]$Database, [int]$QueryTimeout = 300)
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

function Invoke-QueryVaultSql {
	param([string]$Database, [string]$Query, [int]$QueryTimeout = 300)
	$params = New-ConnectionParameters -Database $Database -QueryTimeout $QueryTimeout
	return Invoke-Sqlcmd @params -Query $Query -Verbose:$false
}

function Get-Hash {
	param([object]$Value)
	$json = $Value | ConvertTo-Json -Compress -Depth 8
	$bytes = [Text.Encoding]::UTF8.GetBytes($json)
	return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Assert-Condition {
	param([bool]$Condition, [string]$Message)
	if (-not $Condition) { throw $Message }
}

function Get-QueryVaultSnapshot {
	$dbState = Invoke-QueryVaultSql -Database "master" -Query "SET NOCOUNT ON; SELECT state_desc AS StateDescription FROM sys.databases WHERE name=N'$DatabaseName';" -QueryTimeout 30
	Assert-Condition ($null -ne $dbState) "Database '$DatabaseName' does not exist."

	$objectQuery = @"
SET NOCOUNT ON;
DECLARE @Expected TABLE (ObjectType char(2) NOT NULL, SchemaName sysname NOT NULL, ObjectName sysname NOT NULL);
INSERT @Expected (ObjectType, SchemaName, ObjectName)
VALUES
('U','dbo','DatabaseConfig'),('U','dbo','RunMetadata'),
('U','dbo','query_store_query'),('U','dbo','query_store_query_text'),('U','dbo','query_store_plan'),
('U','dbo','query_store_runtime_stats'),('U','dbo','query_store_runtime_stats_interval'),('U','dbo','query_store_wait_stats'),
('U','dbo','query_store_query_PartitionMaintenance'),('U','dbo','query_store_query_text_PartitionMaintenance'),
('U','dbo','query_store_plan_PartitionMaintenance'),('U','dbo','query_store_runtime_stats_PartitionMaintenance'),
('U','dbo','query_store_runtime_stats_interval_PartitionMaintenance'),('U','dbo','query_store_wait_stats_PartitionMaintenance'),
('P','dbo','usp_ManagePartitions'),('P','dbo','usp_InitializeDatabase'),('P','dbo','usp_GetArchiveSummary'),
('P','dbo','usp_ArchiveQueryStore'),('P','dbo','usp_PurgeExpiredArchives');

SELECT
  (SELECT COUNT(*) FROM @Expected AS e WHERE OBJECT_ID(QUOTENAME(e.SchemaName)+'.'+QUOTENAME(e.ObjectName),e.ObjectType) IS NULL) AS MissingObjectCount,
  (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) AS UserTableCount,
  (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped=0) AS ProcedureCount,
  (SELECT COUNT(*) FROM sys.partition_functions WHERE name=N'PF_RunID') AS PartitionFunctionCount,
  (SELECT COUNT(*) FROM sys.partition_schemes WHERE name=N'PS_RunID') AS PartitionSchemeCount,
  (SELECT COUNT_BIG(*) FROM dbo.DatabaseConfig) AS ConfigCount,
  (SELECT COUNT_BIG(*) FROM dbo.RunMetadata) AS RunMetadataCount,
  (SELECT COUNT_BIG(*) FROM dbo.DatabaseConfig WHERE DefaultDaysToArchive<=0 OR DefaultRetentionDays<=0) AS InvalidConfigCount;
"@
	$objects = Invoke-QueryVaultSql -Database $DatabaseName -Query $objectQuery -QueryTimeout 60

	$rowQuery = @"
SET NOCOUNT ON;
SELECT t.name AS TableName,
       CONVERT(bigint,SUM(CASE WHEN i.index_id IN (0,1) THEN ps.row_count ELSE 0 END)) AS [RowCount]
FROM sys.tables AS t
JOIN sys.indexes AS i ON i.object_id=t.object_id
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id=i.object_id AND ps.index_id=i.index_id
WHERE t.name IN
(
 N'DatabaseConfig',N'RunMetadata',N'query_store_query',N'query_store_query_text',N'query_store_plan',
 N'query_store_runtime_stats',N'query_store_runtime_stats_interval',N'query_store_wait_stats'
)
GROUP BY t.name
ORDER BY t.name;
"@
	$archiveRows = @(Invoke-QueryVaultSql -Database $DatabaseName -Query $rowQuery -QueryTimeout 60 | ForEach-Object {
		[ordered]@{ TableName = [string]$_.TableName; RowCount = [long]$_.RowCount }
	})

	$configQuery = @"
SET NOCOUNT ON;
SELECT DatabaseName,ServerName,IsEnabled,DefaultDaysToArchive,ScheduleType,
       CONVERT(varchar(16),ScheduleTime,114) AS ScheduleTime,DefaultRetentionDays,
       AutoDeleteEnabled,MaxRowsPerBatch,EnableParallelCopy
FROM dbo.DatabaseConfig
ORDER BY DatabaseName,ServerName;
"@
	$configRows = @(Invoke-QueryVaultSql -Database $DatabaseName -Query $configQuery -QueryTimeout 60 | ForEach-Object {
		[ordered]@{
			DatabaseName = [string]$_.DatabaseName
			ServerName = [string]$_.ServerName
			IsEnabled = [bool]$_.IsEnabled
			DefaultDaysToArchive = [int]$_.DefaultDaysToArchive
			ScheduleType = [string]$_.ScheduleType
			ScheduleTime = [string]$_.ScheduleTime
			DefaultRetentionDays = [int]$_.DefaultRetentionDays
			AutoDeleteEnabled = [bool]$_.AutoDeleteEnabled
			MaxRowsPerBatch = [int]$_.MaxRowsPerBatch
			EnableParallelCopy = [bool]$_.EnableParallelCopy
		}
	})

	$agentQuery = @"
SET NOCOUNT ON;
SELECT j.name AS JobName,j.enabled AS JobEnabled,SUSER_SNAME(j.owner_sid) AS OwnerName,
       s.name AS ScheduleName,COALESCE(s.enabled,0) AS ScheduleEnabled
FROM dbo.sysjobs AS j
LEFT JOIN dbo.sysjobschedules AS js ON js.job_id=j.job_id
LEFT JOIN dbo.sysschedules AS s ON s.schedule_id=js.schedule_id
WHERE j.name LIKE N'QueryVault%'
ORDER BY j.name,s.name;
"@
	$agentRows = @(Invoke-QueryVaultSql -Database "msdb" -Query $agentQuery -QueryTimeout 60 | ForEach-Object {
		[ordered]@{
			JobName = [string]$_.JobName
			JobEnabled = [bool]$_.JobEnabled
			OwnerName = [string]$_.OwnerName
			ScheduleName = [string]$_.ScheduleName
			ScheduleEnabled = [bool]$_.ScheduleEnabled
		}
	})

	return [ordered]@{
		CapturedUtc = [DateTime]::UtcNow.ToString("o")
		ServerInstance = $ServerInstance
		DatabaseName = $DatabaseName
		DatabaseState = [string]$dbState.StateDescription
		MissingObjectCount = [int]$objects.MissingObjectCount
		UserTableCount = [int]$objects.UserTableCount
		ProcedureCount = [int]$objects.ProcedureCount
		PartitionFunctionCount = [int]$objects.PartitionFunctionCount
		PartitionSchemeCount = [int]$objects.PartitionSchemeCount
		ConfigCount = [long]$objects.ConfigCount
		RunMetadataCount = [long]$objects.RunMetadataCount
		InvalidConfigCount = [long]$objects.InvalidConfigCount
		ConfigHash = Get-Hash $configRows
		AgentHash = Get-Hash $agentRows
		ArchiveRows = $archiveRows
		AgentJobs = $agentRows
	}
}

function Test-ProcedureCompilationAndSmoke {
	$compileQuery = @"
SET NOCOUNT ON;
BEGIN TRANSACTION;
BEGIN TRY
  EXEC sys.sp_refreshsqlmodule N'dbo.usp_ManagePartitions';
  EXEC sys.sp_refreshsqlmodule N'dbo.usp_InitializeDatabase';
  EXEC sys.sp_refreshsqlmodule N'dbo.usp_GetArchiveSummary';
  EXEC sys.sp_refreshsqlmodule N'dbo.usp_ArchiveQueryStore';
  EXEC sys.sp_refreshsqlmodule N'dbo.usp_PurgeExpiredArchives';
  ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
  THROW;
END CATCH;
"@
	Invoke-QueryVaultSql -Database $DatabaseName -Query $compileQuery -QueryTimeout 120 | Out-Null

	$smokeQuery = @"
SET NOCOUNT ON;
BEGIN TRANSACTION;
BEGIN TRY
  SELECT COUNT_BIG(*) AS ConfigRows FROM dbo.DatabaseConfig;
  SELECT COUNT_BIG(*) AS RunRows FROM dbo.RunMetadata;
  SELECT TOP (1) RunID,`$PARTITION.PF_RunID(RunID) AS PartitionNumber
  FROM dbo.RunMetadata
  ORDER BY RunID DESC;
  ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
  THROW;
END CATCH;
"@
	Invoke-QueryVaultSql -Database $DatabaseName -Query $smokeQuery -QueryTimeout 120 | Out-Null
}

$snapshot = Get-QueryVaultSnapshot
Assert-Condition ($snapshot.DatabaseState -eq "ONLINE") "Database '$DatabaseName' is not ONLINE."
Assert-Condition ($snapshot.MissingObjectCount -eq 0) "One or more required QueryVault objects are missing."
Assert-Condition ($snapshot.PartitionFunctionCount -eq 1) "PF_RunID is missing or duplicated."
Assert-Condition ($snapshot.PartitionSchemeCount -eq 1) "PS_RunID is missing or duplicated."
Assert-Condition ($snapshot.InvalidConfigCount -eq 0) "DatabaseConfig contains invalid retention settings."

if ($Mode -eq "Pre") {
	$parent = Split-Path -Parent $BaselinePath
	if ($parent -and -not (Test-Path -LiteralPath $parent)) {
		New-Item -ItemType Directory -Path $parent -Force | Out-Null
	}
	$snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BaselinePath -Encoding utf8NoBOM
	if (-not $IsWindows) {
		[IO.File]::SetUnixFileMode($BaselinePath, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite)
	}
	Write-Host "Pre-deployment verification passed. Baseline: $BaselinePath" -ForegroundColor Green
	return
}

Assert-Condition (Test-Path -LiteralPath $BaselinePath -PathType Leaf) "Baseline file not found: $BaselinePath"
$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
Assert-Condition ($baseline.DatabaseName -eq $snapshot.DatabaseName) "Baseline database does not match the target database."
Assert-Condition ($baseline.ConfigHash -eq $snapshot.ConfigHash) "DatabaseConfig settings changed during deployment."
Assert-Condition ($baseline.AgentHash -eq $snapshot.AgentHash) "QueryVault SQL Agent job or schedule state changed during deployment."

$currentRows = @{}
foreach ($row in $snapshot.ArchiveRows) { $currentRows[$row.TableName] = [long]$row.RowCount }
foreach ($row in $baseline.ArchiveRows) {
	Assert-Condition $currentRows.ContainsKey([string]$row.TableName) "Expected archive table is missing: $($row.TableName)"
	Assert-Condition ($currentRows[[string]$row.TableName] -ge [long]$row.RowCount) "Row count dropped for $($row.TableName): $($row.RowCount) -> $($currentRows[[string]$row.TableName])"
}

Test-ProcedureCompilationAndSmoke
Write-Host "Post-deployment verification passed. Data, configuration, objects, procedures, partitions, and Agent state are intact." -ForegroundColor Green

<#
.SYNOPSIS
	Safely deploys QueryVault database objects from the canonical source folders.

.DESCRIPTION
	Designed for repeatable production automation. The script never installs
	dependencies, never deploys SQL Agent job scripts, and requires the target
	database to exist unless -AllowDatabaseCreate is explicitly supplied.

	Existing tables are preserved and skipped. Partition scripts are idempotent,
	and stored procedures use CREATE OR ALTER. Table shape changes require an
	explicit reviewed migration; they are never inferred or applied destructively.
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$ServerInstance,

	[Parameter()]
	[string]$DatabaseName = "QueryVaultDB",

	[Parameter()]
	[string]$ScriptPath = (Split-Path -Parent $PSScriptRoot),

	[Parameter()]
	[PSCredential]$Credential,

	[Parameter()]
	[string]$GitSha = $env:GITHUB_SHA,

	[Parameter()]
	[switch]$AllowDatabaseCreate,

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

$deploymentSteps = @(
	@{ Name = "Partition Function"; Path = "Partitions/PartitionFunction.sql"; Kind = "Always" },
	@{ Name = "Partition Scheme"; Path = "Partitions/PartitionScheme.sql"; Kind = "Always" },
	@{ Name = "RunMetadata Table"; Path = "Tables/Core/RunMetadata.sql"; Kind = "Table"; Object = "RunMetadata" },
	@{ Name = "DatabaseConfig Table"; Path = "Tables/Core/DatabaseConfig.sql"; Kind = "Table"; Object = "DatabaseConfig" },
	@{ Name = "query_store_query Table"; Path = "Tables/QueryStore/query_store_query.sql"; Kind = "Table"; Object = "query_store_query" },
	@{ Name = "query_store_query_text Table"; Path = "Tables/QueryStore/query_store_query_text.sql"; Kind = "Table"; Object = "query_store_query_text" },
	@{ Name = "query_store_plan Table"; Path = "Tables/QueryStore/query_store_plan.sql"; Kind = "Table"; Object = "query_store_plan" },
	@{ Name = "query_store_runtime_stats Table"; Path = "Tables/QueryStore/query_store_runtime_stats.sql"; Kind = "Table"; Object = "query_store_runtime_stats" },
	@{ Name = "query_store_runtime_stats_interval Table"; Path = "Tables/QueryStore/query_store_runtime_stats_interval.sql"; Kind = "Table"; Object = "query_store_runtime_stats_interval" },
	@{ Name = "query_store_wait_stats Table"; Path = "Tables/QueryStore/query_store_wait_stats.sql"; Kind = "Table"; Object = "query_store_wait_stats" },
	@{ Name = "query_store_runtime_stats_contributor Table"; Path = "Tables/QueryStore/query_store_runtime_stats_contributor.sql"; Kind = "Table"; Object = "query_store_runtime_stats_contributor" },
	@{ Name = "query_store_runtime_stats_canonical Table"; Path = "Tables/QueryStore/query_store_runtime_stats_canonical.sql"; Kind = "Table"; Object = "query_store_runtime_stats_canonical" },
	@{ Name = "query_store_wait_stats_contributor Table"; Path = "Tables/QueryStore/query_store_wait_stats_contributor.sql"; Kind = "Table"; Object = "query_store_wait_stats_contributor" },
	@{ Name = "query_store_wait_stats_canonical Table"; Path = "Tables/QueryStore/query_store_wait_stats_canonical.sql"; Kind = "Table"; Object = "query_store_wait_stats_canonical" },
	@{ Name = "query_store_query_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_query_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_query_PartitionMaintenance" },
	@{ Name = "query_store_query_text_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_query_text_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_query_text_PartitionMaintenance" },
	@{ Name = "query_store_plan_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_plan_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_plan_PartitionMaintenance" },
	@{ Name = "query_store_runtime_stats_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_runtime_stats_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_runtime_stats_PartitionMaintenance" },
	@{ Name = "query_store_runtime_stats_interval_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_runtime_stats_interval_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_runtime_stats_interval_PartitionMaintenance" },
	@{ Name = "query_store_wait_stats_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_wait_stats_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_wait_stats_PartitionMaintenance" },
	@{ Name = "query_store_runtime_stats_contributor_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_runtime_stats_contributor_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_runtime_stats_contributor_PartitionMaintenance" },
	@{ Name = "query_store_runtime_stats_canonical_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_runtime_stats_canonical_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_runtime_stats_canonical_PartitionMaintenance" },
	@{ Name = "query_store_wait_stats_contributor_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_wait_stats_contributor_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_wait_stats_contributor_PartitionMaintenance" },
	@{ Name = "query_store_wait_stats_canonical_PartitionMaintenance"; Path = "Tables/PartitionMaintenance/query_store_wait_stats_canonical_PartitionMaintenance.sql"; Kind = "Table"; Object = "query_store_wait_stats_canonical_PartitionMaintenance" },
	@{ Name = "usp_ManagePartitions Procedure"; Path = "StoredProcedures/usp_ManagePartitions.sql"; Kind = "Procedure" },
	@{ Name = "usp_InitializeDatabase Procedure"; Path = "StoredProcedures/usp_InitializeDatabase.sql"; Kind = "Procedure" },
	@{ Name = "usp_GetArchiveSummary Procedure"; Path = "StoredProcedures/usp_GetArchiveSummary.sql"; Kind = "Procedure" },
	@{ Name = "usp_MaterializeCanonicalQueryStoreStats Procedure"; Path = "StoredProcedures/usp_MaterializeCanonicalQueryStoreStats.sql"; Kind = "Procedure" },
	@{ Name = "usp_ArchiveQueryStore Procedure"; Path = "StoredProcedures/usp_ArchiveQueryStore.sql"; Kind = "Procedure" },
	@{ Name = "usp_PurgeExpiredArchives Procedure"; Path = "StoredProcedures/usp_PurgeExpiredArchives.sql"; Kind = "Procedure" },
	@{ Name = "qv_report.periods View"; Path = "Views/qv_report.periods.sql"; Kind = "View" },
	@{ Name = "qv_report.query_period_metrics View"; Path = "Views/qv_report.query_period_metrics.sql"; Kind = "View" },
	@{ Name = "qv_report.period_metrics View"; Path = "Views/qv_report.period_metrics.sql"; Kind = "View" },
	@{ Name = "qv_report.wait_period_metrics View"; Path = "Views/qv_report.wait_period_metrics.sql"; Kind = "View" },
	@{ Name = "qv_report.query_wait_period_metrics View"; Path = "Views/qv_report.query_wait_period_metrics.sql"; Kind = "View" },
	@{ Name = "qv_report.query_plans View"; Path = "Views/qv_report.query_plans.sql"; Kind = "View" },
	@{ Name = "qv_report.usp_GetShowplanXml Procedure"; Path = "StoredProcedures/qv_report.usp_GetShowplanXml.sql"; Kind = "Procedure" }
)

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

function Write-Header {
	param([string]$Message)
	Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

$startedUtc = [DateTime]::UtcNow
$resolvedScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
$effectiveGitSha = if ([string]::IsNullOrWhiteSpace($GitSha)) { "not-supplied" } else { $GitSha }

try {
	Write-Header "QueryVault production-safe deployment"
	Write-Host "Start UTC: $($startedUtc.ToString('o'))"
	Write-Host "Git SHA: $effectiveGitSha"
	Write-Host "Target server: $ServerInstance"
	Write-Host "Target database: $DatabaseName"
	Write-Host "Canonical source: $resolvedScriptPath"

	$module = Get-Module -ListAvailable -Name SqlServer | Sort-Object Version -Descending | Select-Object -First 1
	if (-not $module) {
		throw "Required PowerShell module 'SqlServer' is missing. Install it during runner provisioning; deployment will not install dependencies."
	}
	Import-Module SqlServer -ErrorAction Stop
	Write-Host "SqlServer module: $($module.Version)"

	$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction Stop
	if ($TrustServerCertificate -and -not $invokeSqlcmd.Parameters.ContainsKey("TrustServerCertificate")) {
		throw "Installed Invoke-Sqlcmd does not support -TrustServerCertificate."
	}

	foreach ($step in $deploymentSteps) {
		$scriptFile = Join-Path $resolvedScriptPath $step.Path
		if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf)) {
			throw "Required deployment source is missing: $scriptFile"
		}
	}

	$dbState = Invoke-QueryVaultSql -Database "master" -Query "SET NOCOUNT ON; SELECT state_desc AS StateDescription FROM sys.databases WHERE name = N'$DatabaseName';" -QueryTimeout 30
	if (-not $dbState) {
		if (-not $AllowDatabaseCreate) {
			throw "Target database '$DatabaseName' does not exist. Production deployment requires an existing database."
		}
		Invoke-QueryVaultSql -Database "master" -Query "CREATE DATABASE [$DatabaseName];" -QueryTimeout 120 | Out-Null
		Write-Host "Created database '$DatabaseName' because -AllowDatabaseCreate was explicitly supplied."
	}
	elseif ($dbState.StateDescription -ne "ONLINE") {
		throw "Target database '$DatabaseName' is not ONLINE; current state: $($dbState.StateDescription)"
	}

	# This preflight deliberately runs before any deployment DDL. The restricted
	# production deployer must not gain dbo impersonation merely to create the
	# reporting boundary.
	$reportSchema = Invoke-QueryVaultSql -Database $DatabaseName -Query @"
SET NOCOUNT ON;
SELECT
  CASE WHEN SCHEMA_ID(N'qv_report') IS NULL THEN 0 ELSE 1 END AS SchemaExists,
  CASE WHEN EXISTS
  (
    SELECT 1 FROM sys.schemas AS s
    WHERE s.name=N'qv_report' AND USER_NAME(s.principal_id)=N'dbo'
  ) THEN 1 ELSE 0 END AS IsDboOwned;
"@ -QueryTimeout 30
	if ([int]$reportSchema.SchemaExists -ne 1 -or [int]$reportSchema.IsDboOwned -ne 1) {
		throw "Required dbo-owned schema 'qv_report' is missing or has the wrong owner. A DBA must first run Security/ProvisionReportingSchema.sql. No QueryVault object DDL was applied."
	}

	$deployed = [System.Collections.Generic.List[string]]::new()
	$skipped = [System.Collections.Generic.List[string]]::new()

	foreach ($step in $deploymentSteps) {
		$scriptFile = Join-Path $resolvedScriptPath $step.Path

		if ($step.Kind -eq "Table") {
			$objectExists = Invoke-QueryVaultSql -Database $DatabaseName -Query "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID(N'dbo.$($step.Object)', N'U') IS NULL THEN 0 ELSE 1 END AS ObjectExists;" -QueryTimeout 30
			if ([int]$objectExists.ObjectExists -eq 1) {
				$skipped.Add($step.Name)
				Write-Host "[PRESERVED] $($step.Name) already exists; no table DDL was applied." -ForegroundColor Yellow
				continue
			}
		}

		$scriptContent = Get-Content -LiteralPath $scriptFile -Raw
		Invoke-QueryVaultSql -Database $DatabaseName -Query $scriptContent | Out-Null
		$deployed.Add($step.Name)
		Write-Host "[DEPLOYED] $($step.Name)" -ForegroundColor Green
	}

	Write-Header "Deployment result"
	Write-Host "Deployed/refreshed: $($deployed.Count)"
	Write-Host "Existing tables preserved: $($skipped.Count)"
	Write-Host "SQL Agent jobs changed: 0"
	Write-Host "End UTC: $([DateTime]::UtcNow.ToString('o'))"
}
catch {
	Write-Error "QueryVault deployment failed: $($_.Exception.Message)"
	throw
}

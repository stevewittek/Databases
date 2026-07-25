<#
.SYNOPSIS
	Deploys the QueryVault database solution for SQL Server Query Store archiving.

.DESCRIPTION
	This script automates the deployment of the QueryVault database, including:
	- Database creation
	- Partition functions and schemes
	- Core metadata tables
	- QueryStore archive tables with columnstore indexes
	- Partition maintenance tables
	- Stored procedures

.PARAMETER ServerInstance
	The SQL Server instance to deploy to (e.g., "localhost" or "SERVER\INSTANCE")

.PARAMETER DatabaseName
	The name of the database to create (default: "QueryVaultDB")

.PARAMETER ScriptPath
	Path to the QueryVault scripts folder (default: current directory)

.PARAMETER Credential
	SQL Server credentials (optional, uses Windows Authentication if not provided)

.EXAMPLE
	.\DeployQueryVault.ps1 -ServerInstance "localhost"

.EXAMPLE
	.\DeployQueryVault.ps1 -ServerInstance "PRODSERVER\INSTANCE" -Credential (Get-Credential) -Verbose

.NOTES
	Author: QueryVault Team
	Requires: SQL Server 2016 or higher
	Requires: PowerShell 5.1 or higher
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory=$true)]
	[string]$ServerInstance,

	[Parameter(Mandatory=$false)]
	[string]$DatabaseName = "QueryVaultDB",

	[Parameter(Mandatory=$false)]
	[string]$ScriptPath = $PSScriptRoot,

	[Parameter(Mandatory=$false)]
	[PSCredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script execution order
$deploymentSteps = @(
	@{ Name = "Partition Function"; Path = "Partitions\PartitionFunction.sql" },
	@{ Name = "Partition Scheme"; Path = "Partitions\PartitionScheme.sql" },
	@{ Name = "RunMetadata Table"; Path = "Tables\Core\RunMetadata.sql" },
	@{ Name = "DatabaseConfig Table"; Path = "Tables\Core\DatabaseConfig.sql" },
	@{ Name = "query_store_query Table"; Path = "Tables\QueryStore\query_store_query.sql" },
	@{ Name = "query_store_query_text Table"; Path = "Tables\QueryStore\query_store_query_text.sql" },
	@{ Name = "query_store_plan Table"; Path = "Tables\QueryStore\query_store_plan.sql" },
	@{ Name = "query_store_runtime_stats Table"; Path = "Tables\QueryStore\query_store_runtime_stats.sql" },
	@{ Name = "query_store_runtime_stats_interval Table"; Path = "Tables\QueryStore\query_store_runtime_stats_interval.sql" },
	@{ Name = "query_store_wait_stats Table"; Path = "Tables\QueryStore\query_store_wait_stats.sql" },
	@{ Name = "query_store_query_PartitionMaintenance"; Path = "Tables\PartitionMaintenance\query_store_query_PartitionMaintenance.sql" },
	@{ Name = "query_store_query_text_PartitionMaintenance"; Path = "Tables\PartitionMaintenance\query_store_query_text_PartitionMaintenance.sql" },
	@{ Name = "query_store_plan_PartitionMaintenance"; Path = "Tables\PartitionMaintenance\query_store_plan_PartitionMaintenance.sql" },
	@{ Name = "query_store_runtime_stats_PartitionMaintenance"; Path = "Tables\PartitionMaintenance\query_store_runtime_stats_PartitionMaintenance.sql" },
	@{ Name = "query_store_runtime_stats_interval_PartitionMaintenance"; Path = "Tables\PartitionMaintenance\query_store_runtime_stats_interval_PartitionMaintenance.sql" },
	@{ Name = "query_store_wait_stats_PartitionMaintenance"; Path = "Tables\PartitionMaintenance\query_store_wait_stats_PartitionMaintenance.sql" },
	@{ Name = "usp_ManagePartitions Procedure"; Path = "StoredProcedures\usp_ManagePartitions.sql" },
	@{ Name = "usp_InitializeDatabase Procedure"; Path = "StoredProcedures\usp_InitializeDatabase.sql" },
	@{ Name = "usp_GetArchiveSummary Procedure"; Path = "StoredProcedures\usp_GetArchiveSummary.sql" },
	@{ Name = "usp_ArchiveQueryStore Procedure"; Path = "StoredProcedures\usp_ArchiveQueryStore.sql" }
)

function Write-Header {
	param([string]$Message)
	Write-Host "`n========================================" -ForegroundColor Cyan
	Write-Host $Message -ForegroundColor Cyan
	Write-Host "========================================`n" -ForegroundColor Cyan
}

function Invoke-SqlScript {
	param(
		[string]$ServerInstance,
		[string]$Database,
		[string]$ScriptFile,
		[PSCredential]$Credential
	)

	if (-not (Test-Path $ScriptFile)) {
		throw "Script file not found: $ScriptFile"
	}

	$scriptContent = Get-Content -Path $ScriptFile -Raw

	# Build connection parameters
	$connectionParams = @{
		ServerInstance = $ServerInstance
		Database = $Database
		QueryTimeout = 300
		ErrorAction = "Stop"
	}

	if ($Credential) {
		$connectionParams.Credential = $Credential
	}

	# Execute script
	Invoke-Sqlcmd @connectionParams -Query $scriptContent -Verbose:$false
}

# Main deployment logic
try {
	Write-Header "QueryVault Database Deployment"

	Write-Host "Server Instance: $ServerInstance" -ForegroundColor Yellow
	Write-Host "Database Name: $DatabaseName" -ForegroundColor Yellow
	Write-Host "Script Path: $ScriptPath`n" -ForegroundColor Yellow

	# Check for SqlServer module
	if (-not (Get-Module -ListAvailable -Name SqlServer)) {
		Write-Warning "SqlServer PowerShell module not found. Installing..."
		Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber
	}

	Import-Module SqlServer -ErrorAction Stop
	Write-Verbose "SqlServer module loaded successfully"

	# Step 1: Create database
	Write-Header "Step 1: Creating Database"

	$createDbScript = @"
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = '$DatabaseName')
BEGIN
	CREATE DATABASE [$DatabaseName];
	PRINT 'Database $DatabaseName created successfully';
END
ELSE
BEGIN
	PRINT 'Database $DatabaseName already exists';
END
"@

	$connectionParams = @{
		ServerInstance = $ServerInstance
		Database = "master"
		QueryTimeout = 60
		ErrorAction = "Stop"
	}

	if ($Credential) {
		$connectionParams.Credential = $Credential
	}

	Invoke-Sqlcmd @connectionParams -Query $createDbScript
	Write-Host "Database ready: $DatabaseName" -ForegroundColor Green

	# Step 2: Execute deployment scripts
	Write-Header "Step 2: Deploying Database Objects"

	$stepNumber = 1
	$totalSteps = $deploymentSteps.Count

	foreach ($step in $deploymentSteps) {
		$scriptFile = Join-Path $ScriptPath $step.Path

		Write-Progress -Activity "Deploying QueryVault" -Status "Step $stepNumber of $totalSteps" -PercentComplete (($stepNumber / $totalSteps) * 100) -CurrentOperation $step.Name
		Write-Verbose "Executing: $($step.Name)"

		try {
			Invoke-SqlScript -ServerInstance $ServerInstance -Database $DatabaseName -ScriptFile $scriptFile -Credential $Credential
			Write-Host "[OK] $($step.Name)" -ForegroundColor Green
		}
		catch {
			Write-Host "[FAILED] $($step.Name)" -ForegroundColor Red
			throw "Failed to deploy $($step.Name): $_"
		}

		$stepNumber++
	}

	Write-Progress -Activity "Deploying QueryVault" -Completed

	# Step 3: Verification
	Write-Header "Step 3: Deployment Verification"

	$verificationScript = @"
SELECT 
	'Tables' AS ObjectType,
	COUNT(*) AS ObjectCount
FROM sys.tables 
WHERE SCHEMA_NAME(schema_id) = 'dbo'

UNION ALL

SELECT 
	'Stored Procedures' AS ObjectType,
	COUNT(*) AS ObjectCount
FROM sys.procedures 
WHERE SCHEMA_NAME(schema_id) = 'dbo'

UNION ALL

SELECT 
	'Partition Functions' AS ObjectType,
	COUNT(*) AS ObjectCount
FROM sys.partition_functions 
WHERE name = 'PF_RunID'

UNION ALL

SELECT 
	'Partition Schemes' AS ObjectType,
	COUNT(*) AS ObjectCount
FROM sys.partition_schemes 
WHERE name = 'PS_RunID';
"@

	$connectionParams.Database = $DatabaseName
	$results = Invoke-Sqlcmd @connectionParams -Query $verificationScript

	$results | Format-Table -AutoSize

	# Summary
	Write-Header "Deployment Summary"

	Write-Host "Database '$DatabaseName' deployed successfully!" -ForegroundColor Green
	Write-Host "`nNext Steps:" -ForegroundColor Yellow
	Write-Host "1. Register databases for archiving:" -ForegroundColor White
	Write-Host "   EXEC $DatabaseName.dbo.usp_InitializeDatabase @DatabaseName = 'YourDatabaseName';" -ForegroundColor Gray
	Write-Host "`n2. Create SQL Agent jobs:" -ForegroundColor White
	Write-Host "   - Use Jobs\CreateArchiveJob_Template.sql for single database" -ForegroundColor Gray
	Write-Host "   - Use Jobs\CreateArchiveJob_AllDatabases.sql for all databases" -ForegroundColor Gray
	Write-Host "`n3. Test archiving:" -ForegroundColor White
	Write-Host "   EXEC $DatabaseName.dbo.usp_ArchiveQueryStore" -ForegroundColor Gray
	Write-Host "        @SourceDatabaseName = 'YourDatabaseName'," -ForegroundColor Gray
	Write-Host "        @RunName = 'Test Archive'," -ForegroundColor Gray
	Write-Host "        @DoNotDelete = 1;" -ForegroundColor Gray
	Write-Host ""

	Write-Host "Deployment completed successfully!" -ForegroundColor Green
}
catch {
	Write-Error "Deployment failed: $_"
	Write-Host "`nDeployment failed. Please check the error message above." -ForegroundColor Red
	exit 1
}

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

[xml]$project = Get-Content -LiteralPath (Join-Path $projectRoot "QueryVault.sqlproj") -Raw
$namespace = [System.Xml.XmlNamespaceManager]::new($project.NameTable)
$namespace.AddNamespace("msb", $project.Project.NamespaceURI)
$buildItems = @($project.SelectNodes("//msb:Build", $namespace))

Assert-Condition ($buildItems.Count -eq 29) "Expected 29 canonical SQL build items; found $($buildItems.Count)."

foreach ($item in $buildItems) {
    $relativePath = [string]$item.Include
    Assert-Condition ($relativePath -match '^(Partitions|Tables|StoredProcedures|Schemas|Views)\\') "Noncanonical build item: $relativePath"
    Assert-Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) "Missing build source: $relativePath"
}

$partitionFunctionBuildItem = @($buildItems | Where-Object { $_.Include -eq "Partitions\DatabaseProject\PartitionFunction.sql" })
$partitionSchemeBuildItem = @($buildItems | Where-Object { $_.Include -eq "Partitions\DatabaseProject\PartitionScheme.sql" })
Assert-Condition ($partitionFunctionBuildItem.Count -eq 1) "The SSDT-safe partition function definition is not the project build source."
Assert-Condition ($partitionSchemeBuildItem.Count -eq 1) "The SSDT-safe partition scheme definition is not the project build source."

$operationalPartitionFunction = Get-Content -LiteralPath (Join-Path $projectRoot "Partitions\PartitionFunction.sql") -Raw
$operationalPartitionScheme = Get-Content -LiteralPath (Join-Path $projectRoot "Partitions\PartitionScheme.sql") -Raw
Assert-Condition ($operationalPartitionFunction.Contains("IF NOT EXISTS")) "The idempotent partition function deployment wrapper was not preserved."
Assert-Condition ($operationalPartitionScheme.Contains("IF NOT EXISTS")) "The idempotent partition scheme deployment wrapper was not preserved."

$procedureNames = @(
    "usp_ArchiveQueryStore.sql",
    "usp_GetArchiveSummary.sql",
    "usp_InitializeDatabase.sql",
    "usp_ManagePartitions.sql",
    "usp_PurgeExpiredArchives.sql",
    "qv_report.usp_GetShowplanXml.sql"
)

foreach ($procedureName in $procedureNames) {
    $deploymentProcedure = Get-Content -LiteralPath (Join-Path $projectRoot "StoredProcedures\$procedureName") -Raw
    $declarationStart = $deploymentProcedure.IndexOf("CREATE OR ALTER PROCEDURE")
    Assert-Condition ($declarationStart -ge 0) "Deployment procedure is missing its idempotent declaration: $procedureName"

    $expectedModelProcedure = $deploymentProcedure.Substring($declarationStart)
    $expectedModelProcedure = [regex]::Replace($expectedModelProcedure, '^CREATE OR ALTER PROCEDURE', 'CREATE PROCEDURE', 1)
    $actualModelProcedure = Get-Content -LiteralPath (Join-Path $projectRoot "StoredProcedures\DatabaseProject\$procedureName") -Raw

    $expectedNormalized = $expectedModelProcedure -replace "`r`n", "`n"
    $actualNormalized = $actualModelProcedure -replace "`r`n", "`n"
    $expectedNormalized = [regex]::Replace($expectedNormalized, '(?m)^[\t ]*\n', '')
    $actualNormalized = [regex]::Replace($actualNormalized, '(?m)^[\t ]*\n', '')
    $expectedNormalized = [regex]::Replace($expectedNormalized, '(?m)[\t ]+$', '').TrimEnd()
    $actualNormalized = [regex]::Replace($actualNormalized, '(?m)[\t ]+$', '').TrimEnd()
    Assert-Condition ($actualNormalized -ceq $expectedNormalized) "SSDT procedure definition has drifted from its deployment source: $procedureName"
}

$reportingViewNames = @(
    "qv_report.periods.sql",
    "qv_report.query_period_metrics.sql",
    "qv_report.period_metrics.sql",
    "qv_report.wait_period_metrics.sql",
    "qv_report.query_wait_period_metrics.sql",
    "qv_report.query_plans.sql"
)

foreach ($viewName in $reportingViewNames) {
    $deploymentView = Get-Content -LiteralPath (Join-Path $projectRoot "Views\$viewName") -Raw
    $declarationStart = $deploymentView.IndexOf("CREATE OR ALTER VIEW")
    Assert-Condition ($declarationStart -ge 0) "Deployment view is missing its idempotent declaration: $viewName"

    $expectedModelView = $deploymentView.Substring($declarationStart)
    $expectedModelView = [regex]::Replace($expectedModelView, '^CREATE OR ALTER VIEW', 'CREATE VIEW', 1)
    $actualModelView = Get-Content -LiteralPath (Join-Path $projectRoot "Views\DatabaseProject\$viewName") -Raw

    $expectedNormalized = $expectedModelView -replace "`r`n", "`n"
    $actualNormalized = $actualModelView -replace "`r`n", "`n"
    $expectedNormalized = [regex]::Replace($expectedNormalized, '(?m)^[\t ]*\n', '')
    $actualNormalized = [regex]::Replace($actualNormalized, '(?m)^[\t ]*\n', '')
    $expectedNormalized = [regex]::Replace($expectedNormalized, '(?m)[\t ]+$', '').TrimEnd()
    $actualNormalized = [regex]::Replace($actualNormalized, '(?m)[\t ]+$', '').TrimEnd()
    Assert-Condition ($actualNormalized -ceq $expectedNormalized) "SSDT view definition has drifted from its deployment source: $viewName"
}

$reportSchemaBuildItem = @($buildItems | Where-Object { $_.Include -eq "Schemas\qv_report.sql" })
Assert-Condition ($reportSchemaBuildItem.Count -eq 1) "The qv_report schema is missing from the SSDT model."

[xml]$fixedProject = Get-Content -LiteralPath (Join-Path $projectRoot "QueryVault_Fixed.sqlproj") -Raw
$fixedNamespace = [System.Xml.XmlNamespaceManager]::new($fixedProject.NameTable)
$fixedNamespace.AddNamespace("msb", $fixedProject.Project.NamespaceURI)
$fixedBuildPaths = @($fixedProject.SelectNodes("//msb:Build", $fixedNamespace) | ForEach-Object { [string]$_.Include } | Sort-Object)
$primaryBuildPaths = @($buildItems | ForEach-Object { [string]$_.Include } | Sort-Object)
Assert-Condition (($fixedBuildPaths -join "`n") -ceq ($primaryBuildPaths -join "`n")) "The two SQL project manifests do not build the same model sources."

$masterReference = @($project.SelectNodes("//msb:ArtifactReference", $namespace) | Where-Object { $_.Include -match 'SqlServer\\150\\SqlSchemas\\master\.dacpac$' })
Assert-Condition ($masterReference.Count -eq 1) "The SQL Server 2019 master DACPAC reference is missing."

$archiveProcedure = Get-Content -LiteralPath (Join-Path $projectRoot "StoredProcedures\usp_ArchiveQueryStore.sql") -Raw
Assert-Condition ($archiveProcedure.Contains("SET @PartitionsToAdd = @RunID - @MaxRunIDInFunction;")) "Archive partition growth does not cover identity jumps."
Assert-Condition ($archiveProcedure.Contains("@NewPartitionCount = @PartitionsToAdd;")) "Archive procedure does not pass the calculated partition count."
Assert-Condition ($archiveProcedure.Contains("GROUP BY plan_id, execution_type, runtime_stats_interval_id")) "Runtime-stat grain rejection guard is missing."
Assert-Condition ($archiveProcedure.Contains("GROUP BY plan_id, runtime_stats_interval_id, execution_type, wait_category")) "Wait-stat grain rejection guard is missing."

$partitionProcedure = Get-Content -LiteralPath (Join-Path $projectRoot "StoredProcedures\usp_ManagePartitions.sql") -Raw
Assert-Condition ($partitionProcedure.Contains("Refusing to switch a physical partition that contains multiple RunID values.")) "SwitchOut shared-partition guard is missing."
Assert-Condition ($partitionProcedure.Contains("Refusing to truncate a physical partition that contains multiple RunID values.")) "Truncate shared-partition guard is missing."
Assert-Condition ($partitionProcedure.Contains("IF @StartedTransaction = 1 AND XACT_STATE() <> 0")) "Owned-transaction rollback guard is missing."

Assert-Condition (Test-Path -LiteralPath (Join-Path $repositoryRoot "docs\CURRENT_STATE.md") -PathType Leaf) "CURRENT_STATE.md is missing."
Assert-Condition (Test-Path -LiteralPath (Join-Path $repositoryRoot "docs\TARGET_GAP_ANALYSIS.md") -PathType Leaf) "TARGET_GAP_ANALYSIS.md is missing."

[pscustomobject]@{
    TestResult = "PASS"
    CanonicalBuildItems = $buildItems.Count
    ReportingContractItems = 8
    PartitionSafetyGuards = 4
}

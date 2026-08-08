# FixBuildErrors.ps1
# This script fixes the QueryVault.sqlproj file by changing deployment and job scripts from Build to None

Write-Host "Fixing QueryVault.sqlproj build errors..." -ForegroundColor Cyan

$projectFile = "QueryVault.sqlproj"

if (Test-Path $projectFile) {
	Write-Host "Reading project file..." -ForegroundColor Yellow
	$content = Get-Content $projectFile -Raw

	# Replace Build includes with None includes for deployment scripts
	$content = $content -replace '<Build Include="CreateArchiveJob_Template\.sql" />', '<None Include="CreateArchiveJob_Template.sql" />'
	$content = $content -replace '<Build Include="CreateArchiveJob_AllDatabases\.sql" />', '<None Include="CreateArchiveJob_AllDatabases.sql" />'
	$content = $content -replace '<Build Include="Deploy\.sql" />', '<None Include="Deploy.sql" />'
	$content = $content -replace '<Build Include="Deploy_Standalone\.sql" />', '<None Include="Deploy_Standalone.sql" />'

	# Replace Build includes with None includes for job scripts in Jobs folder
	$content = $content -replace '<Build Include="Jobs\\CreateArchiveJob_AllDatabases\.sql" />', '<None Include="Jobs\CreateArchiveJob_AllDatabases.sql" />'
	$content = $content -replace '<Build Include="Jobs\\CreateArchiveJob_Template\.sql" />', '<None Include="Jobs\CreateArchiveJob_Template.sql" />'

	# Replace Build includes with None includes for deploy scripts in Scripts folder
	$content = $content -replace '<Build Include="Scripts\\Deploy\.sql" />', '<None Include="Scripts\Deploy.sql" />'
	$content = $content -replace '<Build Include="Scripts\\Deploy_Standalone\.sql" />', '<None Include="Scripts\Deploy_Standalone.sql" />'

	# Replace Build includes with None includes for maintenance/utility scripts
	$content = $content -replace '<Build Include="EnableQueryStore\.sql" />', '<None Include="EnableQueryStore.sql" />'
	$content = $content -replace '<Build Include="FixSQL2019Compatibility\.sql" />', '<None Include="FixSQL2019Compatibility.sql" />'
	$content = $content -replace '<Build Include="CompleteSQL2019Fix\.sql" />', '<None Include="CompleteSQL2019Fix.sql" />'
	$content = $content -replace '<Build Include="ups_ArchiveQueryStore\.sql" />', '<None Include="ups_ArchiveQueryStore.sql" />'

	# Remove duplicate entries (old root-level references)
	$content = $content -replace '<Build Include="PartitionFunction\.sql" />', ''
	$content = $content -replace '<Build Include="PartitionScheme\.sql" />', ''
	$content = $content -replace '<Build Include="RunMetadata\.sql" />', ''
	$content = $content -replace '<Build Include="DatabaseConfig\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_query\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_query_text\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_plan\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_runtime_stats\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_runtime_stats_interval\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_wait_stats\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_query_PartitionMaintenance\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_query_text_PartitionMaintenance\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_plan_PartitionMaintenance\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_runtime_stats_PartitionMaintenance\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_runtime_stats_interval_PartitionMaintenance\.sql" />', ''
	$content = $content -replace '<Build Include="query_store_wait_stats_PartitionMaintenance\.sql" />', ''
	$content = $content -replace '<Build Include="usp_ManagePartitions\.sql" />', ''
	$content = $content -replace '<Build Include="usp_ArchiveQueryStore\.sql" />', ''
	$content = $content -replace '<Build Include="usp_InitializeDatabase\.sql" />', ''
	$content = $content -replace '<Build Include="usp_GetArchiveSummary\.sql" />', ''

	# Clean up any double empty lines
	$content = $content -replace '(\r\n){3,}', "`r`n`r`n"

	Write-Host "Writing fixed project file..." -ForegroundColor Yellow
	$content | Set-Content $projectFile -NoNewline

	Write-Host "Project file fixed successfully!" -ForegroundColor Green
	Write-Host ""
	Write-Host "Changes made:" -ForegroundColor Cyan
	Write-Host "  - Moved job creation scripts from Build to None" -ForegroundColor White
	Write-Host "  - Moved deployment scripts from Build to None" -ForegroundColor White
	Write-Host "  - Moved utility scripts from Build to None" -ForegroundColor White
	Write-Host "  - Removed duplicate root-level Build entries" -ForegroundColor White
	Write-Host ""
	Write-Host "Please reload the solution in Visual Studio to see the changes." -ForegroundColor Yellow

} else {
	Write-Host "Error: QueryVault.sqlproj not found!" -ForegroundColor Red
	Write-Host "Please run this script from the QueryVault project directory." -ForegroundColor Red
}

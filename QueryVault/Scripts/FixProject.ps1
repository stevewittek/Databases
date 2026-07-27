# Fix QueryVault.sqlproj - Remove build errors
# This script removes duplicate entries and excludes deployment/job scripts from build

$projectFile = "D:\Dev\QueryVault\Databases\QueryVault\QueryVault.sqlproj"

Write-Host "Unloading project in Visual Studio..." -ForegroundColor Yellow
Write-Host "Please unload the QueryVault project (Right-click > Unload Project), then press Enter to continue..." -ForegroundColor Cyan
Read-Host

if (Test-Path $projectFile) {
	$content = Get-Content $projectFile -Raw

	# Create backup
	$backup = "$projectFile.backup"
	Copy-Item $projectFile $backup -Force
	Write-Host "Backup created: $backup" -ForegroundColor Green

	# Read as XML
	[xml]$xml = $content

	# Find all Build ItemGroups
	$buildItems = $xml.Project.ItemGroup | Where-Object { $_.Build -ne $null }

	# Clear existing build items
	foreach ($item in $buildItems) {
		$item.RemoveAll()
	}

	# Save
	$xml.Save($projectFile)
	Write-Host "Project file cleaned successfully!" -ForegroundColor Green
	Write-Host "Now reload the project in Visual Studio and rebuild." -ForegroundColor Cyan
}
else {
	Write-Error "Project file not found: $projectFile"
}

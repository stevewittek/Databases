# Quick Fix for QueryVault Build Errors
# This script replaces the project file with the corrected version

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "QueryVault Project File Fix Utility" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$projectDir = "D:\Dev\QueryVault\Databases\QueryVault"
$originalFile = Join-Path $projectDir "QueryVault.sqlproj"
$fixedFile = Join-Path $projectDir "QueryVault_Fixed.sqlproj"
$backupFile = Join-Path $projectDir "QueryVault.sqlproj.backup"

# Check if Visual Studio is running
$vsProcesses = Get-Process devenv -ErrorAction SilentlyContinue
if ($vsProcesses) {
	Write-Host "⚠️  Visual Studio is currently running!" -ForegroundColor Yellow
	Write-Host "Please close Visual Studio before running this script." -ForegroundColor Yellow
	Write-Host "`nPress any key to exit..."
	$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
	exit 1
}

# Verify files exist
if (-not (Test-Path $originalFile)) {
	Write-Error "Original project file not found: $originalFile"
	exit 1
}

if (-not (Test-Path $fixedFile)) {
	Write-Error "Fixed project file not found: $fixedFile"
	exit 1
}

Write-Host "Found project files:" -ForegroundColor Green
Write-Host "  Original: $originalFile" -ForegroundColor Gray
Write-Host "  Fixed:    $fixedFile`n" -ForegroundColor Gray

# Create backup
Write-Host "Creating backup..." -ForegroundColor Yellow
try {
	Copy-Item $originalFile $backupFile -Force
	Write-Host "✓ Backup created: $backupFile`n" -ForegroundColor Green
}
catch {
	Write-Error "Failed to create backup: $_"
	exit 1
}

# Replace with fixed version
Write-Host "Applying fix..." -ForegroundColor Yellow
try {
	Copy-Item $fixedFile $originalFile -Force
	Write-Host "✓ Project file updated successfully!`n" -ForegroundColor Green
}
catch {
	Write-Error "Failed to apply fix: $_"
	Write-Host "Restoring backup..." -ForegroundColor Yellow
	Copy-Item $backupFile $originalFile -Force
	exit 1
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ FIX APPLIED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Changes made:" -ForegroundColor Cyan
Write-Host "  • Removed duplicate Build entries" -ForegroundColor White
Write-Host "  • Excluded deployment scripts from build" -ForegroundColor White
Write-Host "  • Excluded SQL Agent job scripts from build" -ForegroundColor White
Write-Host "  • Kept all database objects for validation`n" -ForegroundColor White

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Open Visual Studio" -ForegroundColor White
Write-Host "  2. Reload the solution if prompted" -ForegroundColor White
Write-Host "  3. Build → Rebuild Solution" -ForegroundColor White
Write-Host "  4. Verify 0 errors`n" -ForegroundColor White

Read-Host "Press Enter to exit"

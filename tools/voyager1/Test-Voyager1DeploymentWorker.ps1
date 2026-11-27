$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Invoke-Voyager1DeploymentWorker.ps1') -FunctionsOnly

function Assert-Equal($Actual, $Expected, [string]$Label) {
    if ($Actual -cne $Expected) { throw "Failed: $Label" }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    try { & $Action } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw
    }
    throw "Expected failure: $Pattern"
}

$run = @{
    repository = @{ full_name = 'stevewittek/Databases' }; head_repository = @{ full_name = 'stevewittek/Databases' }
    head_branch = 'master'; path = '.github/workflows/queryvault-voyager1.yml'; event = 'workflow_dispatch'
    status = 'in_progress'; run_attempt = 1; id = 767; head_sha = 'a'*40
    actor = @{ login = 'stevewittek' }; triggering_actor = @{ login = 'stevewittek' }
    display_title = 'QueryVault Voyager 1 | inspect'
}
Assert-Equal (Get-RequestMode $run) 'inspect' 'inspection mode'
$run.display_title = 'QueryVault Voyager 1 | deploy'
Assert-Equal (Get-RequestMode $run) 'deploy' 'deploy mode'
$run.path += '@refs/heads/master'
Assert-Equal (Get-RequestMode $run) 'deploy' 'qualified workflow path'
foreach ($case in @(
    @{ key='path'; bad='.github/workflows/queryvault-prod.yml' },
    @{ key='head_branch'; bad='feature' },
    @{ key='head_repository'; bad=@{ full_name='example/Databases' } },
    @{ key='actor'; bad=@{ login='example' } },
    @{ key='triggering_actor'; bad=@{ login='example' } },
    @{ key='event'; bad='pull_request_target' },
    @{ key='status'; bad='completed' },
    @{ key='run_attempt'; bad=2 },
    @{ key='head_sha'; bad='master' },
    @{ key='display_title'; bad='QueryVault Voyager 1 | deploy now' }
)) {
    $changed = $run.Clone()
    $changed[$case.key] = $case.bad
    Assert-Equal (Get-RequestMode $changed) $null $case.key
}

$now = [datetimeoffset]::UtcNow
$status = @{ state='pending'; creator=@{ login='github-actions[bot]' }; created_at=$now.AddMinutes(-1); description='Voyager 1 deploy requested' }
Assert-Equal (Test-RequestReady $status 'deploy' $now) $true 'fresh request'
Assert-Equal (Test-RequestReady $status 'inspect' $now) $false 'status disagrees with mode'
Assert-Equal (Test-RequestReady $null 'deploy' $now) $false 'status not posted yet'
$status.created_at = $now.AddMinutes(-11)
Assert-Equal (Test-RequestReady $status 'deploy' $now) $false 'stale request'
$status.created_at = $now
$status.creator.login = 'stevewittek'
Assert-Equal (Test-RequestReady $status 'deploy' $now) $false 'status not from Actions'
Assert-Equal (Test-UsesStatusToken "statuses/$($run.head_sha)") $true 'authenticated receipt'
Assert-Equal (Test-UsesStatusToken "commits/$($run.head_sha)/statuses?per_page=100") $true 'authenticated status read'
Assert-Equal (Test-UsesStatusToken 'actions/runs/767') $false 'public Actions API with status-only token'
Assert-Equal (Test-UsesStatusToken 'git/ref/heads/master') $false 'public branch read with status-only token'

$snapshot = @{
    MachineName='DESKTOP-CLVE7DV'; DatabaseName='QueryVaultDB'; MajorVersion=15; HasArchive=1
    Updateability='READ_WRITE'; HasReportingSchema=1; HasRunPartitioning=1; ObservedRunPartitions=10
    PopulatedColumnstoreOverflowPartitions=0
}
Assert-ArchiveTarget $snapshot
$wrong = $snapshot.Clone(); $wrong.DatabaseName = 'QueryVaultRowstoreLab'
Assert-Throws { Assert-ArchiveTarget $wrong } 'existing Voyager 1 root'
$wrong = $snapshot.Clone(); $wrong.MachineName = 'voyager2'
Assert-Throws { Assert-ArchiveTarget $wrong } 'existing Voyager 1 root'
$wrong = $snapshot.Clone(); $wrong.HasArchive = 0
Assert-Throws { Assert-ArchiveTarget $wrong } 'existing Voyager 1 root'

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$null = New-Item -Path $fixtureRoot -ItemType Directory
try {
    $config = @{ deployment_enabled=$false; backup_root='D:\QV\Backups'; baseline_root=$fixtureRoot }
    Assert-Throws { Assert-DeploymentReady $snapshot $config } 'disabled locally'
    $config.deployment_enabled = $true
    $blocked = $snapshot.Clone(); $blocked.PopulatedColumnstoreOverflowPartitions = 1
    Assert-Throws { Assert-DeploymentReady $blocked $config } 'legacy RunID overflow'
    $blocked = $snapshot.Clone(); $blocked.ObservedRunPartitions = 0
    Assert-Throws { Assert-DeploymentReady $blocked $config } 'not deployment-ready'
    Assert-DeploymentReady $snapshot $config
    $config.backup_root = '\\backup\archive\Voyager1'
    Assert-DeploymentReady $snapshot $config
    $config.backup_root = 'relative'
    Assert-Throws { Assert-DeploymentReady $snapshot $config } 'backup directory'
    $path = Join-Path $fixtureRoot 'receipt.json'
    Set-Receipt $path $run.head_sha running 'claimed'
    Set-Receipt $path $run.head_sha success 'complete'
    Assert-Equal ((Get-Content -Raw -LiteralPath $path | ConvertFrom-Json).state) 'success' 'terminal receipt atomically replaces pending'
    Assert-Equal (Test-Path -LiteralPath "$path.tmp") $false 'no partial receipt left'
}
finally { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }

Write-Host 'Voyager 1 request, target, overflow and receipt guards passed.'

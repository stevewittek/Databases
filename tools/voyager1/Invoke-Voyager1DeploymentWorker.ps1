[CmdletBinding()]
param(
    [string]$StateRoot = "$env:ProgramData\QueryVault\Voyager1",
    [switch]$FunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Repository = 'stevewittek/Databases'
$script:ApiRoot = "https://api.github.com/repos/$script:Repository"
$script:WorkflowPath = '.github/workflows/queryvault-voyager1.yml'
$script:Desktop = 'DESKTOP-CLVE7DV'
$script:RootDatabase = 'QueryVaultDB'

function Get-RequestMode {
    param($Run)
    if ($null -eq $Run -or $null -eq $Run.repository -or $null -eq $Run.head_repository -or
        $null -eq $Run.actor -or $null -eq $Run.triggering_actor -or
        $Run.repository.full_name -cne $script:Repository -or $Run.head_repository.full_name -cne $script:Repository -or
        $Run.head_branch -cne 'master' -or $Run.path -cnotin @($script:WorkflowPath, "$script:WorkflowPath@refs/heads/master") -or
        $Run.event -cne 'workflow_dispatch' -or $Run.status -cne 'in_progress' -or $Run.run_attempt -ne 1 -or
        $Run.actor.login -cne 'stevewittek' -or $Run.triggering_actor.login -cne 'stevewittek' -or
        [string]$Run.id -cnotmatch '^[0-9]+$' -or $Run.head_sha -cnotmatch '^[0-9a-f]{40}$') { return }
    if ($Run.display_title -ceq 'QueryVault Voyager 1 | inspect') { return 'inspect' }
    if ($Run.display_title -ceq 'QueryVault Voyager 1 | deploy') { return 'deploy' }
}

function Test-RequestReady {
    param($Status, [string]$Mode, [datetimeoffset]$Now)
    if ($null -eq $Status -or $Status.state -cne 'pending' -or $Status.creator.login -cne 'github-actions[bot]' -or
        $Status.description -cne "Voyager 1 $Mode requested") { return $false }
    $age = $Now - [datetimeoffset]$Status.created_at
    return ($age.TotalSeconds -ge -120 -and $age.TotalMinutes -lt 10)
}

function Assert-ArchiveTarget {
    param($Snapshot)
    if ($null -eq $Snapshot -or @($Snapshot).Count -ne 1 -or
        $Snapshot.MachineName -ine $script:Desktop -or $Snapshot.DatabaseName -cne $script:RootDatabase -or
        $Snapshot.MajorVersion -lt 15 -or [int]$Snapshot.HasArchive -ne 1) {
        throw 'SQL did not identify itself as the existing Voyager 1 root QueryVaultDB archive on a supported engine.'
    }
}

function Assert-DeploymentReady {
    param($Snapshot, $Config)
    if ($Config.deployment_enabled -isnot [bool] -or -not $Config.deployment_enabled) {
        throw 'Root deployment is disabled locally. Complete backup, isolated restore and migration/clone acceptance first.'
    }
    if ($Snapshot.Updateability -cne 'READ_WRITE' -or $Snapshot.HasReportingSchema -ne 1 -or
        $Snapshot.HasRunPartitioning -ne 1 -or $Snapshot.ObservedRunPartitions -lt 1 -or
        $Snapshot.PopulatedColumnstoreOverflowPartitions -ne 0) {
        throw 'Existing archive is not deployment-ready. Check reporting prerequisites and legacy RunID overflow (#55/#58).'
    }
    if ($Config.backup_root -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+\\)' -or
        -not (Test-Path -LiteralPath $Config.baseline_root -PathType Container)) {
        throw 'A configured SQL Server-side backup directory and an existing local baseline directory are required.'
    }
}

function Set-Receipt {
    param([string]$Path, [string]$Sha, [string]$State, [string]$Message)
    $tempPath = "$Path.tmp"
    @{ sha = $Sha; state = $State; message = $Message; updated_utc = [datetime]::UtcNow.ToString('o') } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $tempPath -Encoding utf8
    [IO.File]::Move($tempPath, $Path, $true)
}

function Invoke-GitHubApi {
    param([string]$Path, [string]$Method = 'Get', $Body)
    $argsForRest = @{
        Uri = "$script:ApiRoot/$Path"; Method = $Method
        Authentication = 'Bearer'; Token = $script:StatusToken; TimeoutSec = 30
        MaximumRedirection = 0
        Headers = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    }
    if ($null -ne $Body) { $argsForRest.Body = $Body | ConvertTo-Json -Compress; $argsForRest.ContentType = 'application/json' }
    Invoke-RestMethod @argsForRest
}

function Publish-Receipt {
    param($Run, $Receipt)
    Invoke-GitHubApi -Path "statuses/$($Run.head_sha)" -Method Post -Body @{
        state = $Receipt.state; description = $Receipt.message; context = "queryvault/voyager1/$($Run.id)"
        target_url = "https://github.com/$script:Repository/actions/runs/$($Run.id)"
    } | Out-Null
}

if ($FunctionsOnly) { return }
if (-not $IsWindows -or $env:COMPUTERNAME -ine $script:Desktop) { throw 'Run this worker on DESKTOP-CLVE7DV only.' }
if ($env:QUERYVAULT_SQL_USER -or $env:QUERYVAULT_SQL_PASSWORD) { throw 'This worker uses Windows integrated SQL authentication, not SQL credential environment variables.' }

$config = Get-Content -LiteralPath (Join-Path $StateRoot 'config.json') -Raw | ConvertFrom-Json
$script:StatusToken = (Get-Content -LiteralPath (Join-Path $StateRoot 'github-status.dpapi') -Raw).Trim() | ConvertTo-SecureString
$lockPath = Join-Path $StateRoot 'worker.lock'
try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
catch [IO.IOException] { $script:StatusToken.Dispose(); return } # Another instance owns the worker.

try {
    $result = Invoke-GitHubApi -Path 'actions/workflows/queryvault-voyager1.yml/runs?branch=master&event=workflow_dispatch&status=in_progress&per_page=10'
    foreach ($listed in $result.workflow_runs) {
        $mode = Get-RequestMode $listed
        if (-not $mode) { continue }
        $runId = [long]$listed.id
        $run = Invoke-GitHubApi -Path "actions/runs/$runId"
        if ((Get-RequestMode $run) -cne $mode -or $run.id -ne $runId -or $run.head_sha -cne $listed.head_sha) { continue }
        $sha = $run.head_sha
        $context = "queryvault/voyager1/$runId"
        $status = Invoke-GitHubApi -Path "commits/$sha/statuses?per_page=100" |
            Where-Object context -CEQ $context | Select-Object -First 1
        if ($status -and $status.creator.login -ceq 'stevewittek' -and $status.state -in @('success','failure','error')) { continue }
        $receiptPath = Join-Path $StateRoot "run-$runId.json"
        if (Test-Path -LiteralPath $receiptPath) {
            $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
            if ($receipt.sha -cne $sha) { throw 'Local receipt does not match the GitHub request.' }
            if ($receipt.state -eq 'running') {
                Set-Receipt $receiptPath $sha failure 'Desktop execution was interrupted; inspect local records before retrying.'
                $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
            }
            if ($status -and $status.state -ceq 'pending') { Publish-Receipt $run $receipt }
            continue
        }
        if (-not (Test-RequestReady $status $mode ([datetimeoffset]::UtcNow))) { continue }

        $sourceDir = Join-Path $StateRoot "source-$runId"
        $log = Join-Path $StateRoot "run-$runId.log"
        Set-Receipt $receiptPath $sha running 'Request claimed by desktop.'
        try {
            $head = Invoke-GitHubApi -Path 'git/ref/heads/master'
            if ($head.object.sha -cne $sha) { throw 'Master moved since this request. Dispatch the new revision.' }
            $zip = Join-Path $StateRoot "source-$runId.zip"
            $sourceUrl = "https://codeload.github.com/$script:Repository/zip/$sha"
            Invoke-WebRequest -Uri $sourceUrl -TimeoutSec 120 -MaximumRedirection 0 -OutFile $zip
            Expand-Archive -LiteralPath $zip -DestinationPath $sourceDir
            $source = Join-Path $sourceDir "Databases-$sha"
            Import-Module SqlServer -MinimumVersion 22 -ErrorAction Stop
            $query = Get-Content -LiteralPath (Join-Path $source 'tools/voyager1/Inspect-RootArchive.sql') -Raw
            $snapshot = Invoke-Sqlcmd -ServerInstance $config.server_instance -Database $script:RootDatabase `
                -Encrypt Mandatory -ConnectionTimeout 10 -QueryTimeout 30 -AbortOnError -Query $query
            Assert-ArchiveTarget $snapshot
            $snapshot | Select-Object MachineName,InstanceName,MajorVersion,DatabaseName,Updateability,HasArchive,HasReportingSchema,HasRunPartitioning,MaxRunBoundary,PopulatedColumnstoreOverflowPartitions,ObservedRunPartitions |
                ConvertTo-Json | Set-Content -LiteralPath $log -Encoding utf8

            if ($mode -ceq 'deploy') {
                Assert-DeploymentReady $snapshot $config
                $freshRun = Invoke-GitHubApi -Path "actions/runs/$runId"
                $freshHead = Invoke-GitHubApi -Path 'git/ref/heads/master'
                if ((Get-RequestMode $freshRun) -cne $mode -or $freshRun.head_sha -cne $sha -or $freshHead.object.sha -cne $sha) {
                    throw 'Request was canceled or master moved before deployment began.'
                }
                $deploy = Join-Path $source 'QueryVault/Scripts/InvokeQueryVaultProductionDeployment.ps1'
                & $deploy -ServerInstance $config.server_instance -DatabaseName $script:RootDatabase `
                    -BackupRoot $config.backup_root -BaselineRoot $config.baseline_root -GitSha $sha *>> $log
                Set-Receipt $receiptPath $sha success 'Voyager 1 backup, deployment and postchecks passed.'
            } else {
                $message = 'Voyager 1 root archive reached; no changes made.'
                if ($snapshot.PopulatedColumnstoreOverflowPartitions -gt 0) { $message = 'Root archive inspected; populated columnstore overflow blocks deployment (#55).' }
                elseif (-not $config.deployment_enabled) { $message = 'Root archive inspected; local deployment remains disabled.' }
                Set-Receipt $receiptPath $sha success $message
            }
        }
        catch {
            $_.Exception.Message | Add-Content -LiteralPath $log -Encoding utf8
            Set-Receipt $receiptPath $sha failure "Voyager 1 $mode stopped; see the desktop receipt and log."
        }
        Publish-Receipt $run (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json)
    }
}
finally { $lock.Dispose(); $script:StatusToken.Dispose() }

<# Offline control-flow tests. No network, token acquisition or SQL execution. #>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runner = Join-Path $root 'QueryVault/Preflight/InvokeQueryStoreReadiness.ps1'
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
. $runner

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action, [string]$Expected) {
    $rejected = $false
    try { & $Action | Out-Null } catch {
        $rejected = $true
        Assert-True ($_.Exception.Message -like "*$Expected*") 'Failure was not safely classified.'
        Assert-True ($_.Exception.ToString() -notmatch 'SECRET_CANARY|private-host|private-db') 'Error leaked sensitive details.'
    }
    Assert-True $rejected 'Expected operation to fail closed.'
}
function New-TestTable([string[]]$Fields, [object[]]$Values) {
    $table = [Data.DataTable]::new()
    for ($i=0; $i -lt $Fields.Count; $i++) {
        $type = if ($Values[$i] -is [string]) { [string] } else { [int] }
        [void]$table.Columns.Add($Fields[$i], $type)
    }
    [void]$table.Rows.Add($Values)
    return ,$table
}
function New-TestConnection([int]$TargetMatched = 1, [int]$EngineEdition = 5,
        [int]$FailExecution = 0, [switch]$FailOpen, [switch]$LeakyResult) {
    $guard = New-TestTable @('TargetMatched','EngineEdition') @($TargetMatched,$EngineEdition)
    $values = @($script:QVReadinessFields | ForEach-Object { 1 })
    $values[1] = $EngineEdition
    if ($LeakyResult) { $values[2] = 'SECRET_CANARY' }
    $result = New-TestTable $script:QVReadinessFields $values
    $command = [pscustomobject]@{
        CommandTimeout=0; CommandText=''; Parameters=[Collections.Generic.List[object]]::new()
        Calls=0; FailExecution=$FailExecution; Guard=$guard; Result=$result; Disposed=$false
        Texts=[Collections.Generic.List[string]]::new()
    }
    $command | Add-Member ScriptMethod CreateParameter {
        [pscustomobject]@{ ParameterName=''; DbType=$null; Size=0; Value=$null }
    }
    $command | Add-Member ScriptMethod ExecuteReader {
        $this.Calls++
        $this.Texts.Add($this.CommandText)
        if ($this.Calls -eq $this.FailExecution) { throw 'Timeout SECRET_CANARY private-host private-db' }
        $table = $this.Result
        if ($this.Calls -eq 1) { $table = $this.Guard }
        return ,$table.CreateDataReader()
    }
    $command | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    $connection = [pscustomobject]@{ Command=$command; FailOpen=$FailOpen.IsPresent; Opened=$false; Disposed=$false }
    $connection | Add-Member ScriptMethod Open {
        if ($this.FailOpen) { throw 'Connection timeout SECRET_CANARY private-host private-db' }
        $this.Opened = $true
    }
    $connection | Add-Member ScriptMethod CreateCommand { return $this.Command }
    $connection | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    return $connection
}

$token = ConvertTo-SecureString 'SECRET_CANARY' -AsPlainText -Force
$settings = New-QVReadinessSettings 'private-host' 'private-db' 'EntraToken' $token $true 7 11
Assert-True ($settings.Encrypt -eq 'True' -and -not $settings.TrustServerCertificate) 'TLS must validate server certificates.'
Assert-True ($settings['Connect Timeout'] -eq 7 -and $settings.ConnectRetryCount -eq 0 -and -not $settings.Pooling) 'Connection must be bounded without retries or pooling.'
Assert-True (-not $settings['Integrated Security'] -and ($settings | ConvertTo-Json) -notmatch 'SECRET_CANARY') 'Connection settings leaked token or mixed authentication.'
Assert-Rejected { New-QVReadinessSettings 'host' 'db' 'Integrated' $null $false 0 5 } 'Timeouts must'
Assert-Rejected { New-QVReadinessSettings 'host' 'db' 'Integrated' $null $false 5 61 } 'Timeouts must'
Assert-Rejected { New-QVReadinessSettings 'host;Password=SECRET_CANARY' 'db' 'Integrated' $null $false 5 5 } 'explicit source endpoint'
Assert-Rejected { New-QVReadinessSettings 'host' 'db' 'EntraToken' $null $true 5 5 } 'SecureString'
Assert-Rejected { New-QVReadinessSettings 'host' 'db' 'Integrated' $token $false 5 5 } 'cannot receive'
Assert-Rejected { New-QVReadinessSettings 'host' 'db' 'Integrated' $null $true 5 5 } 'Azure readiness'

$sql = [IO.File]::ReadAllText((Join-Path $root 'QueryVault/Preflight/InspectQueryStoreReadiness.sql'))
$mismatch = New-TestConnection -TargetMatched 0
Assert-Rejected { Invoke-QVReadinessSession $mismatch 'private-db' $true 11 $sql } 'Source readiness failed'
Assert-True ($mismatch.Command.Calls -eq 1 -and $mismatch.Disposed -and $mismatch.Command.Disposed) 'Target mismatch must stop before inspecting options and dispose resources.'
$wrongEngine = New-TestConnection -EngineEdition 8
Assert-Rejected { Invoke-QVReadinessSession $wrongEngine 'private-db' $true 11 $sql } 'Source readiness failed'
Assert-True ($wrongEngine.Command.Calls -eq 1) 'Azure guard accepted Managed Instance.'
$openFailure = New-TestConnection -FailOpen
Assert-Rejected { Invoke-QVReadinessSession $openFailure 'private-db' $true 11 $sql } 'Source readiness failed'
Assert-True ($openFailure.Command.Calls -eq 0 -and $openFailure.Disposed) 'Open timeout must stop and dispose.'
$commandFailure = New-TestConnection -FailExecution 2
Assert-Rejected { Invoke-QVReadinessSession $commandFailure 'private-db' $true 11 $sql } 'Source readiness failed'
Assert-True ($commandFailure.Command.CommandTimeout -eq 11 -and $commandFailure.Command.Calls -eq 2 -and $commandFailure.Disposed) 'Command timeout must be assigned, fail without retry, and dispose.'
$badResult = New-TestConnection -LeakyResult
Assert-Rejected { Invoke-QVReadinessSession $badResult 'private-db' $true 11 $sql } 'Source readiness failed'
$extraRow = New-TestConnection
[void]$extraRow.Command.Guard.Rows.Add(@(1,5))
Assert-Rejected { Invoke-QVReadinessSession $extraRow 'private-db' $true 11 $sql } 'Source readiness failed'
Assert-True ($extraRow.Command.Calls -eq 1) 'Unexpected guard data must stop before inspection.'
$unknownPermission = New-TestConnection
$unknownPermission.Command.Result.Rows[0]['ViewDatabasePerformanceState'] = [DBNull]::Value
$unknown = Invoke-QVReadinessSession $unknownPermission 'private-db' $true 11 $sql
Assert-True ($null -eq $unknown.ViewDatabasePerformanceState) 'Unknown permission must remain unknown, never granted.'
$success = New-TestConnection
$output = Invoke-QVReadinessSession $success 'private-db' $true 11 $sql
Assert-True ($success.Command.Calls -eq 2 -and $output.TargetMatched -eq 1 -and $output.EngineEdition -eq 5) 'Expected guarded bounded inspection.'
Assert-True (($output | ConvertTo-Json) -notmatch 'private-db|private-host|SECRET_CANARY') 'Output leaked sensitive identifiers.'
Assert-True ($success.Command.Parameters[0].DbType -eq [Data.DbType]::String -and
    $success.Command.Parameters[0].Size -eq 128 -and $success.Command.Parameters[0].Value -eq 'private-db' -and
    $success.Command.Parameters[1].DbType -eq [Data.DbType]::Boolean) 'Target inputs must be typed parameters.'
Assert-True ($success.Command.Texts[0] -notmatch 'database_query_store_options' -and $success.Command.Texts[1] -ceq $sql) 'Only target guard may run before validation.'
Assert-True ($sql -notmatch '(?im)^\s*(INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|DENY|USE)\b') 'Readiness batch contains a mutation.'
Assert-True ($sql -notmatch '(?i)FROM\s+(dbo\.|sys\.query_store_)') 'Readiness batch reads application or Query Store content.'
Write-Output 'PASS: parser, target/engine rejection, typed inputs, TLS/timeouts, no retry, output/error redaction, disposal and fixed SQL scope. Mocked only; live SQL and authentication acceptance are separate.'

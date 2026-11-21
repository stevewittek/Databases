<# Optional transport for the read-only SQL batch. Uses installed SqlServer >=22;
   never installs modules, acquires tokens, stores secrets, or changes source settings.
   Dot-source to load functions without connecting. #>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$ExpectedDatabase,
    [ValidateSet('Integrated','EntraToken')][string]$Authentication = 'Integrated',
    [securestring]$AccessToken,
    [switch]$RequireAzureSqlDatabase,
    [ValidateRange(1,60)][int]$ConnectionTimeoutSeconds = 15,
    [ValidateRange(1,60)][int]$CommandTimeoutSeconds = 15
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:QVReadinessSqlPath = Join-Path $PSScriptRoot 'InspectQueryStoreReadiness.sql'
$script:QVReadinessFields = @('TargetMatched','EngineEdition','ProductMajorVersion','CompatibilityLevel',
    'ViewDatabaseState','ViewDatabasePerformanceState','OptionsReadStatus','ActualState','DesiredState',
    'ReadOnlyReason','CurrentStorageMB','MaximumStorageMB','IntervalMinutes','FlushIntervalSeconds','StaleDays','CaptureMode',
    'RuntimeStatsViewVisible','RuntimeIntervalsViewVisible','WaitStatsViewVisible','WaitCaptureOptionVisible')

function New-QVReadinessSettings {
    param([string]$Server, [string]$ExpectedDatabase, [string]$Authentication,
        [securestring]$AccessToken, [bool]$RequireAzureSqlDatabase,
        [int]$ConnectionTimeoutSeconds, [int]$CommandTimeoutSeconds)
    if ([string]::IsNullOrWhiteSpace($Server) -or $Server.Length -gt 512 -or $Server -match '[;\r\n\x00]') {
        throw 'Supply one explicit source endpoint, not a connection string.'
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedDatabase) -or $ExpectedDatabase.Length -gt 128 -or
        $ExpectedDatabase -match '[\r\n\x00]') { throw 'Supply an explicit expected database of at most 128 characters.' }
    if ($ConnectionTimeoutSeconds -lt 1 -or $ConnectionTimeoutSeconds -gt 60 -or
        $CommandTimeoutSeconds -lt 1 -or $CommandTimeoutSeconds -gt 60) { throw 'Timeouts must be between 1 and 60 seconds.' }
    if ($Authentication -notin @('Integrated','EntraToken')) { throw 'Unsupported authentication mode.' }
    if ($Authentication -eq 'EntraToken' -and (-not $AccessToken -or $AccessToken.Length -eq 0)) {
        throw 'An existing nonempty SecureString Entra access token is required.'
    }
    if ($Authentication -eq 'Integrated' -and $AccessToken) { throw 'Integrated authentication cannot receive an access token.' }
    if ($RequireAzureSqlDatabase -and $Authentication -ne 'EntraToken') {
        throw 'The Azure readiness runner requires an existing Entra access token.'
    }
    return @{
        'Data Source'=$Server; 'Initial Catalog'=$ExpectedDatabase; 'Encrypt'='True';
        'TrustServerCertificate'=$false; 'Persist Security Info'=$false; 'Pooling'=$false;
        'Connect Timeout'=$ConnectionTimeoutSeconds; 'ConnectRetryCount'=0;
        'Integrated Security'=($Authentication -eq 'Integrated');
        'Application Name'='QueryVault Readiness'; 'Application Intent'='ReadOnly'
    }
}

function Read-QVReadinessRow {
    param($Reader, [string[]]$Fields)
    if ($Reader.FieldCount -ne $Fields.Count -or -not $Reader.Read()) { throw 'Invalid readiness response.' }
    $values = [ordered]@{}
    for ($i = 0; $i -lt $Fields.Count; $i++) {
        if ($Reader.GetName($i) -cne $Fields[$i]) { throw 'Invalid readiness response.' }
        $value = $Reader.GetValue($i)
        if ($value -is [DBNull]) { $value = $null }
        elseif ($value -isnot [int] -and $value -isnot [long]) { throw 'Invalid readiness response.' }
        $values[$Fields[$i]] = $value
    }
    if ($Reader.Read() -or $Reader.NextResult()) { throw 'Unexpected extra readiness data.' }
    return [pscustomobject]$values
}

function Add-QVReadinessParameters {
    param($Command, [string]$ExpectedDatabase, [bool]$RequireAzureSqlDatabase)
    $database = $Command.CreateParameter()
    $database.ParameterName = '@ExpectedDatabase'
    $database.DbType = [Data.DbType]::String
    $database.Size = 128
    $database.Value = $ExpectedDatabase
    [void]$Command.Parameters.Add($database)
    $azure = $Command.CreateParameter()
    $azure.ParameterName = '@RequireAzureSqlDatabase'
    $azure.DbType = [Data.DbType]::Boolean
    $azure.Value = $RequireAzureSqlDatabase
    [void]$Command.Parameters.Add($azure)
}

function Invoke-QVReadinessSession {
    param($Connection, [string]$ExpectedDatabase, [bool]$RequireAzureSqlDatabase,
        [ValidateRange(1,60)][int]$CommandTimeoutSeconds, [string]$Sql)
    $command = $null; $reader = $null
    try {
        $Connection.Open()
        $command = $Connection.CreateCommand()
        $command.CommandTimeout = $CommandTimeoutSeconds
        Add-QVReadinessParameters $command $ExpectedDatabase $RequireAzureSqlDatabase
        # Only target identity is read before validating the expected target.
        $command.CommandText = @'
SELECT CASE WHEN DB_NAME() COLLATE Latin1_General_100_BIN2 = @ExpectedDatabase COLLATE Latin1_General_100_BIN2
            AND DATALENGTH(DB_NAME()) = DATALENGTH(@ExpectedDatabase) THEN 1 ELSE 0 END AS TargetMatched,
       CONVERT(int, SERVERPROPERTY('EngineEdition')) AS EngineEdition;
'@
        $reader = $command.ExecuteReader()
        $guard = Read-QVReadinessRow $reader @('TargetMatched','EngineEdition')
        $reader.Dispose(); $reader = $null
        if ($guard.TargetMatched -ne 1 -or $guard.EngineEdition -notin @(2,3,4,5,8) -or
            ($RequireAzureSqlDatabase -and $guard.EngineEdition -ne 5)) { throw 'Source target guard failed.' }
        $command.CommandText = $Sql
        $reader = $command.ExecuteReader()
        $result = Read-QVReadinessRow $reader $script:QVReadinessFields
        if ($result.TargetMatched -ne 1 -or $result.EngineEdition -ne $guard.EngineEdition) {
            throw 'Source target guard failed.'
        }
        return $result
    } catch {
        # Do not include driver exception text, endpoint, token, login, SQL or server messages.
        throw [InvalidOperationException]::new('Source readiness failed or timed out; verify the approved target, identity, TLS, network and read permissions. No capture or configuration changes were requested.')
    } finally {
        if ($reader) { try { $reader.Dispose() } catch {} }
        if ($command) { try { $command.Dispose() } catch {} }
        if ($Connection) { try { $Connection.Dispose() } catch {} }
    }
}

function Invoke-QueryVaultSourceReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$ExpectedDatabase,
        [ValidateSet('Integrated','EntraToken')][string]$Authentication = 'Integrated',
        [securestring]$AccessToken,
        [switch]$RequireAzureSqlDatabase,
        [ValidateRange(1,60)][int]$ConnectionTimeoutSeconds = 15,
        [ValidateRange(1,60)][int]$CommandTimeoutSeconds = 15
    )
    $settings = New-QVReadinessSettings $Server $ExpectedDatabase $Authentication $AccessToken `
        $RequireAzureSqlDatabase.IsPresent $ConnectionTimeoutSeconds $CommandTimeoutSeconds
    $connection = $null; $pointer = [IntPtr]::Zero
    try {
        if (-not ('Microsoft.Data.SqlClient.SqlConnection' -as [type])) {
            Import-Module SqlServer -MinimumVersion 22.0.0 -ErrorAction Stop | Out-Null
        }
        if (-not ('Microsoft.Data.SqlClient.SqlConnection' -as [type])) { throw 'SqlClient is unavailable.' }
        $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
        foreach ($key in $settings.Keys) { $builder[$key] = $settings[$key] }
        $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
        if ($Authentication -eq 'EntraToken') {
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccessToken)
            $connection.AccessToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
            $pointer = [IntPtr]::Zero
        }
        $sql = [IO.File]::ReadAllText($script:QVReadinessSqlPath)
        Invoke-QVReadinessSession $connection $ExpectedDatabase $RequireAzureSqlDatabase.IsPresent $CommandTimeoutSeconds $sql
    } catch {
        throw [InvalidOperationException]::new('Source readiness did not complete. Check installed SqlServer/SqlClient support, the approved target, existing authentication, TLS, network and read permissions. No capture or configuration changes were requested.')
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($connection) { try { $connection.Dispose() } catch {} }
    }
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-QueryVaultSourceReadiness @PSBoundParameters }

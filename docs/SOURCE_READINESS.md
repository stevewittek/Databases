# Read-only source readiness (#38)

Start with `QueryVault/Preflight/InspectQueryStoreReadiness.sql` against one explicitly approved source database. This is an inspection aid, not a collector, installer, credential vault, or permission provisioning script. It does not enable a source or prove unattended collection is ready.

## SQL-first use

Use an existing authenticated SSMS/sqlcmd connection in a dedicated session with certificate validation and bounded connection/query timeouts. The SQL batch does not establish its own timeout; set it in the client before execution. In the **same batch**, prepend these declarations to the script (replace the example database deliberately; do not add `GO` between the declarations and script):

```sql
DECLARE @ExpectedDatabase nvarchar(128) = N'YourApprovedSourceDatabase';
DECLARE @RequireAzureSqlDatabase bit = 1;
-- Paste InspectQueryStoreReadiness.sql below these declarations.
```

Set the Azure requirement to `0` only for an approved SQL Server or Managed Instance target. Database matching is case-sensitive and checks length, including trailing spaces. A missing/wrong database, unrecognized engine, or Azure requirement mismatch stops before inspecting Query Store options. Azure SQL Database is engine edition `5`; Managed Instance is `8` and fails the Azure Database requirement. Azure's product version numbers must not be interpreted as SQL Server release numbers.

For an installed Go sqlcmd supporting `ActiveDirectoryAzCli`, reuse the current authorized Azure CLI identity; no token should appear in command arguments. Example PowerShell, assuming `$batchPath` points to the combined, reviewed SQL batch above:

```powershell
sqlcmd -S 'tcp:your-approved-server.database.windows.net,1433' `
  -d 'YourApprovedSourceDatabase' --authentication-method ActiveDirectoryAzCli `
  -N true -l 15 -t 15 -b -i $batchPath
```

Do not add `-C` (trust server certificate). [SQLCMD authentication and encryption flags](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility) vary by implementation/version; verify the installed tool supports these flags. No install, login, token acquisition, firewall change, grant, source change or archive deployment is part of this check. Prefer a separately reviewed batch file over interpolating database input into SQL. A `SqlCommand` caller should bind the two parameters directly.

## Optional PowerShell transport

`QueryVault/Preflight/InvokeQueryStoreReadiness.ps1` supports existing integrated authentication or an existing **SecureString** Entra SQL access token. It uses already installed `Microsoft.Data.SqlClient` (or imports installed `SqlServer` module version 22 or newer); it does not install anything or obtain/renew tokens. The SQL-first path does not require this module.

```powershell
# Existing integrated-auth identity on an approved SQL Server target:
& ./QueryVault/Preflight/InvokeQueryStoreReadiness.ps1 `
  -Server 'tcp:approved-host,1433' -ExpectedDatabase 'ApprovedDatabase'

# $existingSqlAccessToken is a SecureString from your existing authorized session,
# for the Azure SQL audience https://database.windows.net/. Never paste a token.
& ./QueryVault/Preflight/InvokeQueryStoreReadiness.ps1 `
  -Server 'tcp:approved-server.database.windows.net,1433' `
  -ExpectedDatabase 'ApprovedDatabase' -Authentication EntraToken `
  -AccessToken $existingSqlAccessToken -RequireAzureSqlDatabase
```

TLS encryption and certificate validation are mandatory. Pooling and connection retries are disabled; connection and per-command timeouts default to 15 seconds each, constrained to 1–60 seconds. Two sequential commands run: a target guard, then the fixed inspection batch (which repeats its own guard). The overall duration can exceed one timeout because opening and each command have separate limits; this is not a hard process deadline. `Application Intent=ReadOnly` is a routing hint, not enforcement of permissions. On availability-group deployments it may route to a readable replica, so use the approved endpoint appropriate to the intended source.

The supplied token exists in driver memory while connecting. The script does not persist it, print it, place it in a connection string, or acquire a replacement. SecureString is a transport boundary, not a guarantee against a compromised process/host; managed token memory cannot be guaranteed erased. Driver errors are replaced with a fixed safe message. Do not log raw exception history, environment dumps, connection objects, or PowerShell session transcripts containing credentials. This runner introduces no credential storage choice and does not implement #49.

## What the result means

All returned fields are fixed numeric values or null. No host/database/login names, connection strings, tokens, application rows, query text, plans, or runtime/wait-stat rows are returned. The only data read are current-database metadata, effective permissions, the single-row Query Store options view, and existence of named catalog views/columns. No whole-store scans or row counts occur. SQL Server may record the inspection itself in its own audit/Query Store according to existing settings; read-only means the scripts request no persistent writes or capture operations.

| Field | Meaning |
|---|---|
| TargetMatched | Always `1` on a completed result; otherwise the target guard fails. |
| EngineEdition / ProductMajorVersion / CompatibilityLevel | Numeric engine capabilities. Do not compare Azure's major version with SQL Server release numbers. |
| ViewDatabaseState / ViewDatabasePerformanceState | `1` effective permission, `0` absent, `NULL` invalid/unknown/unavailable. Neither a NULL nor catalog visibility proves access. |
| OptionsReadStatus | `0` options read; `1` no row; `2` inspection failed, including insufficient permission or unsupported view. |
| ActualState / DesiredState | Query Store state (`0` off, `1` read-only, `2` read-write, `3` error; newer engines may add states). |
| ReadOnlyReason | Engine's Query Store read-only reason bitmap; see the options-view reference. |
| CurrentStorageMB / MaximumStorageMB | Query Store configured capacity/use, not a proposed archive sizing estimate. |
| IntervalMinutes / FlushIntervalSeconds / StaleDays / CaptureMode | Existing interval size, flush cadence, stale-query policy and capture setting; no setting changes. Capture mode `1` all, `2` auto, `3` custom, `0` none. |
| RuntimeStatsViewVisible / RuntimeIntervalsViewVisible / WaitStatsViewVisible / WaitCaptureOptionVisible | `1` visible metadata; `NULL` absent or hidden. These do not prove the content can be read. |

Microsoft documents `VIEW DATABASE STATE` for the options view on SQL Server 2016–2019; SQL Server 2022 and later use `VIEW DATABASE PERFORMANCE STATE` or the broader `VIEW DATABASE STATE`. The options-view documentation also identifies the performance permission for current Azure SQL. Runtime-stat-view documentation distinguishes SQL Server 2022+ performance permissions from earlier database-state permissions. This preflight reports both effective permission checks and actual options readability; it intentionally does not select runtime/query/plan content to prove their permissions. An interactive owner/admin success must not be reported as least-privilege service-identity acceptance.

## Validation and remaining acceptance

Run `pwsh -NoLogo -NoProfile -File QueryVault/Tests/TestQueryStoreReadiness.ps1` for offline parser and mock tests. These cover database/engine mismatch stopping before options, connection and command failures without retry, assigned timeouts, typed inputs, validated TLS settings, generic errors, fixed numeric output, disposal and bounded SQL scope. They do not simulate SQL Server's compiler/permissions, real network cancellation, TLS, routing or Entra authentication.

Before closing readiness acceptance, record a reviewed run on the approved live target with date, engine, permission bits, Query Store options and identity class (interactive administrator versus future collector), without secrets. Separately test a deliberately wrong expected database and incompatible engine, expired/no-access identity, verified certificate rejection, and the future service identity's least permissions. Run against supported SQL Server and Azure SQL targets as relevant. Collection, credential-storage design, source enablement, retention, scheduling and remote ingestion remain separate work.

References: [Query Store options and permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-database-query-store-options-transact-sql), [runtime statistics permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql), [effective permission function](https://learn.microsoft.com/en-us/sql/t-sql/functions/has-perms-by-name-transact-sql), [engine edition and version semantics](https://learn.microsoft.com/en-us/sql/t-sql/functions/serverproperty-transact-sql), [SqlClient Entra authentication](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql/azure-active-directory-authentication).

## Portable bundle

Portable ZIPs include this guide and the SQL/PowerShell files together under
`preflight/`. Keep the runner beside `InspectQueryStoreReadiness.sql`. Adjust
source-checkout example paths to that directory; no credentials are bundled.

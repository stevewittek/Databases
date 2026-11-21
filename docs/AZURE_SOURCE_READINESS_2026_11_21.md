# Azure source readiness — November 21, 2026

Scope: owner-authorized preparation to connect QueryVault to the existing Motion
Relay Azure SQL database. No new Azure resource, firewall rule, principal, grant,
linked server, job, source setting or archive capture was created. No application
rows, query text or plan XML were read or exported.

## Live observations from the Mac

| Check | Observed result |
| --- | --- |
| Azure resource | Existing database online, Basic tier, Central US |
| Server connection policy | Default; public network access enabled; minimum TLS 1.2 |
| SQL connection | Successful using existing Azure CLI sign-in through sqlcmd 1.11.0, ActiveDirectoryAzCli, encrypted connection with certificate validation |
| Target guard | Expected database matched; EngineEdition = 5 (Azure SQL Database) |
| Engine/compatibility | Product version 12.0.2000.8, database compatibility 170 |
| Query Store | Enabled; actual and desired state READ_WRITE; readonly reason 0 |
| Query Store storage | Approximately 2 MB used / 10 MB configured limit |
| Capture/retention | AUTO, 60-minute intervals, 900-second flush setting, seven-day stale-query threshold |
| Catalog visibility | Query, query-text, plan, runtime, interval and wait catalogs visible |
| Current inspection identity | VIEW DATABASE STATE and VIEW DATABASE PERFORMANCE STATE available; CONTROL and db_owner also present |

The connection used the existing interactive owner identity. It does **not** prove
least-privilege collection, SQL Server Agent identity propagation, linked-server
provider authentication, or an unattended login. No owner token/password was saved,
printed or transferred to Voyager. Azure management-plane access alone was not
counted as SQL access; the SQL query actually completed against the guarded target.

Seven days is a configured age-retention value, not guaranteed evidence coverage:
size pressure and capture policy can remove or omit evidence earlier. QueryVault
must collect safely closed intervals before they disappear; missing coverage must
remain explicit. The 900-second flush setting is a configured interval, not proof
that every interval has already been durably flushed. No tuning change is proposed
as an automatic consequence of this inspection.

## Query scope and reproducibility

Two short queries were run with a 15-second connection timeout, 10-second command
timeout, 3-second lock timeout and a 35-second outer process limit. Both selected
only the current database's catalog metadata, effective permission bits, Query
Store options and system catalog column counts. They did not scan Query Store
facts, retrieve user query text/plans, run workloads or modify configuration.

After the initial probe, the generic `InspectQueryStoreReadiness.sql` batch was
also executed through the same bounded sqlcmd connection. The approved target
returned the expected numeric metadata. A deliberately wrong expected database
was rejected with error 51401 before options inspection. The optional PowerShell
runner passed offline mocked transport/parser tests; it was not used for the live
connection because the SqlServer PowerShell module is not installed on this Mac.
No module was installed. See SOURCE_READINESS.md for execution instructions.
Private local logs live in ignored artifacts; this public report intentionally
omits account identifiers, tokens, endpoint addresses and application data.

## Remaining gates for #38 and #57

1. Resolve credential storage (#49) and choose a dedicated unattended source
   identity with only the required catalog permissions. The owner's interactive
   identity is not the proposed collector account. Do not reuse Motion Relay's
   application or deployment identity for QueryVault.
2. Confirm the Voyager execution host's SQL version, provider, network route and
   actual execution identity. Existing local Azure CLI login is not portable to a
   SQL Server Agent job. Validate TLS without a certificate bypass.
3. Review the intended bounded Query Store data capture and private destination.
   Query text may contain sensitive literals; do not put it in public tickets,
   logs or fixtures. No real-source capture/import is included in this preflight.
4. Prove linked-server transport, full-length text/plan handling, complete-window
   selection, bounded source overhead, stage/commit/checkpoint and safe retries
   using synthetic independent instances before claiming product acceptance.
5. Keep Azure source compatibility separate from Azure archive placement. The
   first collector remains T-SQL-first; Azure archive topology is still under review.

#38 remains open because its acceptance requires an actual bounded capture and
reconciled import, not merely connectivity and metadata inspection.

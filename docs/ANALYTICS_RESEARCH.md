# Query Store analytics research

Reviewed November 22, 2026. These are design references, not bundled dependencies.

## Erik Darling's sp_QuickieStore

Primary sources:

- [Source code](https://github.com/erikdarlingdata/DarlingData/blob/main/sp_QuickieStore/sp_QuickieStore.sql)
- [Result-set guide](https://erikdarling.com/introducing-sp_quickiestore-what-the-results-show-you/)
- [Repository](https://github.com/erikdarlingdata/DarlingData)

The inspected source identifies version 6.11, version date 20261101. Retrieved
GitHub file/blob SHA: `caac78c046429039e29351fea446953b8db255ad`.
This is a blob identifier, not a pinned repository commit.

Reviewed the procedure parameters, help/license section, and regression comparison
construction around lines 12690-12810. It supports baseline start/end dates,
relative or absolute comparisons, improved/regressed ordering, minimum execution
and duration filters, execution outcome filters, query and plan selectors,
query text search, high-impact investigation, parameter sensitivity investigation,
and optional table logging. Its comparison construction joins metrics by query
hash and converts absolute CPU/duration changes to milliseconds. Its source
contains an MIT license notice.

QueryVault uses independently written SQL. It does not install, execute, copy,
or modify sp_QuickieStore. A separate live-source diagnostic session can use that
tool after reviewing the exact upstream release. Preserve the upstream copyright
and MIT license if a later change redistributes any source. No upstream licensing
permission is implied for unrelated commercial products.

Useful ideas adopted: compare two explicit windows, expose both absolute and
relative changes, filter low execution counts, show wait evidence, and distinguish
latency from resource totals. QueryVault deliberately operates on retained runs
through `qv_report`; a live-source tool is not a substitute for historical archives.
Query hash alone is not a collision-free query identity.

## Microsoft Query Store contract

- [Runtime statistics](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql?view=sql-server-ver17)
- [Wait statistics](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-wait-stats-transact-sql?view=sql-server-ver17)
- [Tuning examples](https://learn.microsoft.com/en-us/sql/relational-databases/performance/tune-performance-with-the-query-store?view=sql-server-ver17)

Active runtime intervals can have multiple contributors at the same
plan/execution-type/interval grain. The existing canonical layer remains the
analytics source. CPU/duration are microseconds at capture and milliseconds in
reports. Reads, memory-grant and tempdb page metrics use 8 KB pages; the new
interval view exposes memory/tempdb in KB. Log usage stays in bytes. Execution
types 0, 3 and 4 distinguish regular, client abort and exception outcomes.
Wait categories are not detailed instance wait types or blocker sessions.

Aggregate Query Store statistics cannot produce a true p95 or p99 latency.
The load runner separately measures client request percentiles and labels them.
Query Store does not provide server CPU utilization, memory pressure, exact
blocking chains, or a proof that a deployment caused a regression.

## Grafana

- [MSSQL variables](https://grafana.com/docs/grafana/latest/datasources/mssql/template-variables/)
- [Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)

Run selectors return unique display labels containing the RunID through `__text`
and pass the ID through `__value`. All new variable substitutions use `sqlstring`,
including numeric values converted with `TRY_CONVERT`. Dashboard SQL uses only
`qv_report`. Dashboard provisioning keeps JSON version controlled; database
credentials remain environment values in datasource provisioning.

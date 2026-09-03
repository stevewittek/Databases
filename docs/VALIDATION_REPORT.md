# QueryVault Validation Report

Validation date: 2026-09-03. Target inspected: Voyager2 / `QueryVaultDB`.
All live database validation in this work was read-only or enclosed in an
explicit transaction that was rolled back. Production objects, data, jobs, and
Grafana were not changed.

## Acceptance matrix

| Area | Status | Evidence |
| --- | --- | --- |
| SQL module compilation | **PASS** | Six views and `qv_report.usp_GetShowplanXml` compiled against Voyager2's live table shapes under temporary schema `qv_report_validation`; rollback confirmed `SCHEMA_ID` was null afterward. Required ANSI/quoted-identifier headers are present. |
| Current capture correctness | **PASS** | Production procedure reads `flush_interval_seconds`, caps the window, and selects only intervals with `end_time <= @EndDateTime`. |
| Historical capture correctness | **PARTIAL** | Nine early RunIDs (1, 2, 5, 6, 7, 8, 9, 14, 15) predate the safeguard and contain intervals ending after the recorded period end. |
| Runtime aggregation grain | **PASS** | Zero duplicate groups at `(RunID, plan_id, execution_type, runtime_stats_interval_id)` and zero interval orphans across 2,366 archived runtime rows. |
| Wait aggregation grain | **PASS** | Zero duplicate groups at `(RunID, plan_id, runtime_stats_interval_id, execution_type, wait_category)` and zero interval orphans across 391 archived wait rows. |
| Reporting reconciliation | **PASS** | Completed period 47 reconciled: 353 executions, 2,199.851 ms CPU, 2,481.193 ms duration, 127,463 logical reads, and 187 ms waits. Direct-minus-reporting deltas were zero. |
| Showplan XML | **PASS** | Period 47 returned a non-null plan whose root matched the native SQL Server Showplan namespace. Retrieval procedure compiled. Actual `.sqlplan` file open in SSMS remains an installation acceptance step. |
| Dashboard query SQL | **PASS** | All 49 variable and panel queries executed successfully against temporary reporting objects using real comparable periods 44 and 47, wait category 6, and query 42036. Rollback removed the schema. |
| Dashboard variables | **PASS** | Required server, database, archived/baseline/comparison period, wait category, and query variables exist in the appropriate dashboards and returned live values in SQL validation. |
| Dashboard JSON | **PASS** | All four files parse; dashboard UIDs and panel IDs are unique. |
| Provisioning YAML | **PASS** | Datasource and dashboard provisioning parse; every dashboard resolves datasource UID `queryvault-mssql`. |
| Reporting boundary | **PASS** | Static scan found no dashboard reference to `dbo` or `sys`; all dashboard SQL uses `qv_report`. |
| Secret handling | **PASS** | No credential value is committed. Datasource password is an environment reference; DBA scripts contain placeholders/instructions only. |
| PowerShell syntax | **PASS** | Voyager2's installed PowerShell parser accepted deployment, pre/post validation, and production orchestration scripts. The scripts were parsed, not executed. |
| Read-only repository SQL tests | **PASS** | `TestQueryStoreAggregationGrain.sql` and `TestReportingContract.sql` passed transactionally against live archived data. |
| Retention integration test | **NOT TESTED** | `TestPurgeExpiredArchives.sql` intentionally exercises switch/truncate behavior. It was not executed against production; run it in an approved non-production database. |
| SQL project XML | **PASS** | Both `.sqlproj` files parse and list reporting modules, bootstrap helper, and tests. |
| SSDT project build | **NOT TESTED** | Local `dotnet build --no-restore` cannot load Visual Studio SSDT `Microsoft.Data.Tools.Schema.SqlTasks.targets`; this is an environment/tooling limitation, not a SQL diagnostic. |
| Live datasource connection | **BLOCKED** | `qv_report` and `queryvault_grafana` are not deployed on Voyager2. |
| Least-privilege execution | **BLOCKED** | The dedicated login/user does not yet exist. Positive `qv_report` and negative `dbo.RunMetadata` tests must follow provisioning. |
| Grafana dashboard rendering | **NOT TESTED** | An unrelated CapLab Grafana 13.1.0 container exists; it was not modified or treated as QueryVault infrastructure. |
| Production readiness | **BLOCKED** | Requires Voyager1 reconciliation, DBA schema bootstrap, approved merge, normal backup/deployment workflow, reader provisioning, and live Grafana acceptance. |

## Repository validation commands

Completed successfully:

- `git diff --check`;
- `jq` parsing plus UID, panel-ID, datasource, and variable assertions;
- Ruby/Psych YAML parsing;
- `xmllint` on both SQL project files;
- dashboard SQL boundary and credential scans;
- remote PowerShell parser checks;
- transactional SQL module, reconciliation, Showplan, capture-grain, and all
  dashboard-query tests.

The only attempted validation that did not run was the SSDT build because its
Visual Studio build targets are not installed locally.

## Voyager2 deployment blocker

The current `queryvault_deployer` cannot create `qv_report AUTHORIZATION dbo`,
which is the intended least-privilege posture. The branch adds an idempotent
one-time DBA bootstrap and makes pre-deployment validation fail before backup or
QueryVault object DDL when the schema prerequisite is absent. Do not solve this by granting
the deployer dbo impersonation or giving Grafana direct internal-table access.

## Release decision

The repository package is ready for review, but production integration is not
ready to dispatch. Follow the exact sequence in
[Target and Gap Analysis](TARGET_GAP_ANALYSIS.md) after reconciling the
independent Voyager1 agent's work.

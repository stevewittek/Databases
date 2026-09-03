# QueryVault Target and Gap Analysis

## Target

QueryVault archives safely completed SQL Server Query Store intervals, exposes
a versioned read-only reporting boundary, and supports Grafana OSS and SSMS
without giving either client access to internal storage. Execution plans remain
native SQL Server Showplan XML.

## Gap matrix

| Capability | Current state | Target state | Required action |
| --- | --- | --- | --- |
| Core archive | Implemented and populated on Voyager2 | Repeatable, completed-interval capture | Keep grain regression checks in release validation |
| Runtime aggregation | PASS for current code/data grain | No double counting from active intervals | Continue excluding intervals newer than one Query Store flush interval |
| Wait aggregation | PASS for current code/data grain | Same guarantee at category grain | Continue completed-interval filter and duplicate-grain check |
| Historical periods | PARTIAL for nine early Voyager2 runs | Baseline-quality periods only | Flag/exclude or re-archive from an authoritative retained source; do not rewrite silently |
| Reporting API | Implemented and live-SQL validated transactionally | Deployed, additive `qv_report` contract | DBA schema bootstrap, reviewed production deployment |
| Period classification | PLANNED | Authoritative controlled classification | Design storage separately; populate existing nullable contract column additively |
| Grafana security | Scripts implemented | Dedicated login can read only `qv_report` | Create secret outside Git, provision user, execute positive/negative permission tests |
| Grafana service | Package implemented; live load NOT TESTED | Provisioned QueryVault dashboards | Use a dedicated or explicitly approved Grafana instance; do not claim the unrelated CapLab service |
| Showplan | SQL contract PASS | Export/open in SSMS | Validate one saved `.sqlplan` after deployment; never build a renderer |
| Automated integration test | PARTIAL | Disposable SQL Server plus Grafana smoke CI | Add only after an approved test environment exists |
| Voyager1 reconciliation | NOT AVAILABLE in this worktree | No conflicting capture/deployment changes | Compare the other agent's commit before merge; reconcile, do not overwrite |

## Smallest safe production sequence

1. Review and reconcile the Voyager1 agent's commit with this branch.
2. Run static validation and the two read-only SQL tests in non-production.
3. Have a DBA run `Security/ProvisionReportingSchema.sql`.
4. Manually dispatch the existing production workflow from a reviewed commit
   after its normal backup and preflight requirements are satisfied.
5. Have a DBA create the SQL login through the approved secret process, then
   run `Security/ProvisionGrafanaReader.sql`.
6. Prove that the reader can query `qv_report` and cannot query
   `dbo.RunMetadata`.
7. Mount the version-controlled Grafana assets, test the datasource, and verify
   all variables and panels against two comparable completed periods.
8. Save one plan as `.sqlplan` and open it in SSMS.

No step requires a custom Grafana plugin or an internal schema redesign.

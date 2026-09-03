# Voyager2 QueryVault V1 Release-Candidate Validation

Validation date: 2026-09-03

## Release identity

- Requested cumulative RC: `origin/codex/queryvault-run-partitioning`
- Requested RC SHA: `65336e2c1588351712e8bd7c8c85af0238cdbeed`
- Verified base: `cac2e5a4391647523b4a42d8b040f260bbd2dac5`
- Relationship: exactly one commit ahead of the verified base
- Local validation branch: `codex/queryvault-v1-rc`
- Necessary post-deployment fix: `cb06d520fa87d043495a2b50d507181e5783f929`
  (`Fix Grafana wait table units`)

The database payload was deployed from the requested SHA. The later fix changes
only Grafana field formatting: identifier columns no longer inherit a
millisecond unit and percentage columns use Grafana's percent unit. No internal
database schema, procedure, reporting-contract object, retention behavior, or
archive data changed in that fix.

Voyager2's existing runner checkout remained on `master` at
`db0d8e6edaf6710117b8f7496fb5aa28e6313e33`. Deployment and Grafana mounts used
clean detached worktrees. No merge or rebase was performed.

## Acceptance matrix

| Area | Result | Evidence |
| --- | --- | --- |
| Deployment | PASS | Guarded production deployment completed from exact requested SHA `65336e2c1588`; 27 additive/refreshed modules deployed, 14 existing tables preserved, and SQL Agent changes were zero. |
| Data preservation | PASS | All 39 pre-existing `RunMetadata` rows survived. Rows for original RunIDs through 47 remained exactly: query 1,690; query text 1,659; plan 1,699; runtime 2,366; intervals 709; waits 391. |
| Canonical runtime aggregation | PASS | Transactional regression passed. Bounded live RunID 101 retained 87 contributors, produced 87 distinct canonical grains, and reconciled 88 executions, 523,042 microseconds CPU, 731,810 microseconds duration, and 50,662 logical reads exactly. |
| Canonical wait aggregation | PASS | Transactional regression passed. Live RunID 101 retained 11 wait contributors, produced 11 distinct canonical grains, and reconciled 187 ms exactly. |
| RunID partition lifecycle | PASS | All ten archive/maintenance table pairs are aligned to `PS_RunID`; live RunID 101 maps to partition 102, boundary 102 provides the empty future partition, fanout is 103, and no canonical partition contains multiple RunIDs. |
| Capacity guards | PASS | Config defaults are 1,000 retained runs and 80% warning threshold. Transactional boundary, ceiling, sparse identity-gap, shared-overflow, and configured-maximum tests passed. |
| Purge | PASS | A disposable transactional run switched and truncated across all ten run-owned tables, metadata was removed, and its obsolete boundary merged. No historical run was used. |
| Pinned-run protection | PASS | Transactional lifecycle tests proved direct switch/truncate/merge and purge reject a protected run. |
| Storage recommendation | PASS | The advisory view returned independent RuntimeStats and WaitStats evidence for all three configured databases. No physical conversion was performed. |
| Grafana datasource | PASS | Native MSSQL datasource health returned `Database Connection OK`; the SQL principal can read/execute `qv_report` but cannot select `dbo.RunMetadata`. |
| QueryVault Overview | PASS | Live dashboard populated source/database/period variables, 353 executions, 2,199.851 ms CPU, 2,481.193 ms duration, 127,463 reads, 94 queries, 94 plans, periods, classification, and waits. |
| Period Comparison | PASS | Periods 44 and 47 returned workload, CPU, duration, read and execution deltas, 20 regressions, 20 improvements, seven plan changes, and three wait-category changes. |
| Wait Analysis | PASS | Period 47 versus baseline 44 populated wait distribution, baseline change, and eight Buffer IO query contributors. Corrected identifier/percentage field formatting was visually revalidated. |
| Query Detail | PASS | Query 42269 populated text preview, execution/resource metrics, two-period history, wait profile, and two plan-metadata rows. |
| Showplan XML | PASS | `qv_report.usp_GetShowplanXml` exported period 47/query 42269/plan 775 to a 40,411-byte `.sqlplan`; root and namespace are native Microsoft Showplan XML. |
| SSMS `.sqlplan` rendering | NOT TESTED | SSMS was not available on the macOS validation host or Linux Voyager2. No rendering success is inferred. |
| Rollback/backup readiness | PASS | Guarded deployment created and checksum-verified a copy-only backup and a pre-deployment state baseline before DDL. A separate pre-bootstrap copy-only backup was also checksum-verified. |

There are no release-validation `FAIL` results and no current `BLOCKED`
results. The single `NOT TESTED` item is graphical opening of the exported plan
in SSMS.

## Environment and guarded deployment

Voyager2 was reachable by its previously documented SSH address. SQL Server
17.0.4075.5 Developer was online with `QueryVaultDB` at compatibility level
170. Approximately 39 GB was free before deployment. PowerShell 7.6.5, the
SqlServer module 22.4.5.1, and sqlcmd 18.6 were available.

The DBA-owned `qv_report` schema was bootstrapped with the documented security
script. The guarded deployment then created:

- state baseline
  `/home/nasa/queryvault-production/baselines/QueryVaultDB_20260903T133908Z_65336e2c1588.json`;
- checksum-verified copy-only backup
  `/var/opt/mssql/userlog/backups/voyager2/QueryVaultDB/FULL/voyager2_QueryVaultDB_FULL_20260903_133909_predeploy_copyonly.bak`.

The independently verified pre-bootstrap backup is:

`/var/opt/mssql/userlog/backups/voyager2/QueryVaultDB/FULL/voyager2_QueryVaultDB_FULL_20260903_133821_predeploy_copyonly.bak`

The deployment verifier passed pre/post row counts, configuration hashes, SQL
Agent hashes, module compilation, and reporting smoke tests. It did not modify
SQL Agent jobs.

## Persistent database result

Before deployment there were 39 archive runs, including 37 completed runs,
with RunIDs 1 through 47. The migration preserved all of those rows and added
the lifecycle settings with these defaults to all three existing
configurations:

| Setting | Migrated value |
| --- | --- |
| `MaxRetainedRuns` | `1000` |
| `PartitionWarningPct` | `80` |
| `StorageMode` | `AUTO` |

The deployed reporting boundary contains six views and one procedure. The
database contains ten run-owned archive tables plus ten aligned maintenance
tables. The six original maintenance tables and four new canonical/contributor
maintenance tables were empty after validation. No legacy tautological switch
constraint remains.

One bounded, non-destructive live correctness capture was retained as RunID
101:

| Field | Value |
| --- | --- |
| Name | QueryVault V1 RC canonical capture validation |
| Source | `voyager2` / `WideWorldImporters` |
| Window | 2026-09-02 07:00:00 through 07:15:00 UTC |
| Status | Completed |
| Runtime contributors / canonical grains | 87 / 87 |
| Wait contributors / canonical grains | 11 / 11 |
| Reported executions | 88 |
| Reported CPU | 523.042 ms |
| Reported duration | 731.810 ms |
| Reported logical reads | 50,662 |
| Reported waits | 187 ms |

The gap between prior RunID 47 and live RunID 101 was caused by identity values
consumed by rolled-back transactional tests. QueryVault correctly treats RunID
as a logical identity and allocated only the exact/future boundaries needed;
it did not allocate one partition for every skipped identity.

## Storage recommendation evidence

`dbo.vw_QueryVaultStorageRecommendation` was queried after the live capture.
All archive fact tables remain physically `COLUMNSTORE`; all configurations
remain `AUTO`. The advisory result is:

| Database | Fact type | Sampled runs | Average rows/run | Suggested mode |
| --- | --- | ---: | ---: | --- |
| NDP_Web | RuntimeStats | 11 | 13.909090 | ROWSTORE |
| NDP_Web | WaitStats | 11 | 5.727272 | ROWSTORE |
| StackOverflow2013 | RuntimeStats | 14 | 53.642857 | ROWSTORE |
| StackOverflow2013 | WaitStats | 14 | 8.071428 | ROWSTORE |
| WideWorldImporters | RuntimeStats | 13 | 119.153846 | ROWSTORE |
| WideWorldImporters | WaitStats | 13 | 17.384615 | ROWSTORE |

Each recommendation is based on average recent fact volume below 100,000 rows
per run. This is evidence for the later rowstore-versus-columnstore benchmark,
not authorization to convert storage.

## Grafana result

A dedicated QueryVault Grafana OSS 13.1.0 container runs separately from the
unrelated CapLab Grafana. It uses the native MSSQL datasource and is bound only
to Voyager2 loopback port 13001. The SQL login/user is
`queryvault_grafana`; generated secrets exist only in a mode-0600 host
environment file outside the repository.

The principal checks returned:

- schema `qv_report` SELECT: allowed;
- `qv_report.usp_GetShowplanXml` EXECUTE: allowed;
- direct `dbo.RunMetadata` SELECT: denied.

The lab SQL Server certificate has no usable DNS identity, so this isolated
instance uses an uncommitted runtime datasource override with
`tlsSkipVerify: true`. The version-controlled datasource keeps certificate
validation enabled. This lab exception must not be copied to production.

All 49 dashboard variable and panel queries were executed through Grafana's
MSSQL backend: 49 succeeded, zero returned errors, and zero required template
variables were empty. Every dashboard SQL target continues to use only
`qv_report` objects.

## Showplan export

The least-privilege reporting principal exported:

`/home/nasa/queryvault-production/showplans/period-47-query-42269-plan-775.sqlplan`

The final file is 40,411 bytes, parses as XML, has `ShowPlanXML` as its root,
and uses namespace `http://schemas.microsoft.com/sqlserver/2004/07/showplan`.
PowerShell's default 4,000-character result limit was encountered during the
first export attempt; the validation export was rerun with a two-million
character limit and the incomplete artifact was replaced. QueryVault itself
returned the complete native XML and no renderer was added.

## Tests rerun after the Grafana fix

- `TestRepositoryContracts.ps1`: PASS (40 build items, 10 reporting-contract
  items, 10 partition safety guards).
- `TestProcedureCompilation.sql`: PASS.
- `TestQueryStoreAggregationGrain.sql`: PASS.
- `TestCanonicalQueryStoreAggregation.sql`: PASS.
- `TestReportingCanonicalRegression.sql`: PASS.
- `TestReportingContract.sql`: PASS.
- `TestPartitionSafetyGuards.sql`: PASS.
- `TestPurgeExpiredArchives.sql`: PASS.
- `TestRunPartitionLifecycle.sql`: PASS.
- Live Grafana variable/panel execution: PASS, 49/49.
- Dashboard JSON parsing and diff checks: PASS.

The checked-in SQL tests use Windows-style SQLCMD include paths and include
unconditional table creation. For the deployed Linux database, the final run
used a stream adapter that changes path separators and omits only table-create
includes for tables already deployed. Procedure, function, view, fixture, and
assertion text remained unchanged. This is a test-harness portability issue,
not a product failure.

## Screenshots

- [QueryVault Overview](images/grafana-overview-period.jpg)
- [Period Comparison](images/grafana-period-comparison.jpg)
- [Wait Analysis](images/grafana-wait-analysis.jpg)
- [Query Detail](images/grafana-query-detail.jpg)

The captures use real WideWorldImporters periods 44 and 47 and query 42269.
They contain no datasource password or other credential. SSMS screenshots were
not captured because SSMS was unavailable.

## Release conclusion

The database migration, historical-data preservation, canonical aggregation,
RunID lifecycle, capacity and retention guards, reporting contract, Grafana
integration, and native Showplan export all pass on Voyager2. The only code fix
needed was the narrowly scoped Grafana field-unit correction at `cb06d52`.

Subject to normal review of the final documentation commit, this candidate is
safe to merge to `master`. It is not authorization to convert archive storage,
deploy beyond Voyager2, or claim SSMS graphical rendering was tested.

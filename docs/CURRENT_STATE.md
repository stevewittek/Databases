# QueryVault Current State

Status date: 2026-09-03. This is the consolidated Voyager1 safety and Mac
Grafana/reporting record.

## Implementation status

QueryVault is a local-instance SQL Server Query Store archive. The repository
currently implements:

- configuration and run metadata;
- partitioned archive and maintenance tables for query text, queries, plans,
  intervals, runtime statistics, and waits;
- guarded archive, partition, purge, initialization, and summary procedures;
- a stable read-only `qv_report` API;
- four Grafana OSS dashboards using the native Microsoft SQL Server datasource;
- production-safe PowerShell deployment with backup and pre/post checks; and
- transactional SQL and repository synchronization tests.

The archive schema has not been redesigned. `RunID` remains both capture-period
identity and physical partition key. Reporting consumers must use `qv_report`,
not physical `dbo` tables.

## Architecture and source scope

`dbo.DatabaseConfig` registers enabled databases on the current SQL Server.
`dbo.usp_ArchiveQueryStore` uses three-part names and `@@SERVERNAME`, so remote
SQL Server capture is not implemented even though server name is stored.

One archive execution creates a `RunMetadata` row and copies six Query Store
surfaces under its `RunID`. It records the effective UTC window, completion
state, protection/retention metadata, and per-entity row counts. Query text and
plans are repeated per run; there is no cross-period immutable-object
deduplication or durable identity beyond source-native IDs.

## Capture correctness

The integrated procedure:

- reads source `flush_interval_seconds`;
- caps the requested end at current UTC minus one flush interval;
- selects intervals using `end_time > start` and `end_time <= effective end`;
- keeps failed-run metadata outside the archive transaction;
- schema-qualifies dynamic execution as `sys.sp_executesql`;
- grows partition boundaries far enough to cover a `RunID` identity jump; and
- rejects runtime or wait data containing more than one row at the documented
  grain before the run can complete.

Runtime grain is `(plan_id, execution_type, runtime_stats_interval_id)`. Wait
grain is `(plan_id, runtime_stats_interval_id, execution_type, wait_category)`.

Status: **PARTIAL** against the hard aggregation requirement. Duplicate-grain
rejection is a safe fail-closed guard; it does not aggregate multiple source
observations. Current completed-interval capture substantially reduces exposure,
but it is not equivalent to a canonical aggregate and there is no provisional
active-interval reconciliation path. See
[Query Store correctness](Query-Store-Correctness.md).

Reporting intentionally sums stored facts and does not hide invalid archive
rows. Consequently, legacy duplicate rows must be quarantined or repaired
before those periods are used for workload comparison.

## Partition and retention safety

All six archive and maintenance tables remain partitioned by `RunID` and have
clustered columnstore indexes plus aligned nonclustered primary keys. The
integrated safety logic:

- calculates partition growth from the identity gap, with ten boundaries as the
  minimum increment;
- rejects `SwitchOut` when any archive table's physical partition contains a
  different `RunID`;
- applies the equivalent rejection before maintenance-partition truncation; and
- owns, commits, or rolls back a direct switch/truncate transaction only when no
  caller transaction exists.

`DoNotDelete = 1` protects a run. Other completed runs can be purge candidates
after `RetentionDate` only when the matching configuration enables automatic
deletion. Purge supports dry-run preview and processes each run transactionally.

Status: useful and safer, but the one-run/one-partition model, concurrent
partition extension, legacy switch constraints, and explicit retention classes
remain future design work.

## Reporting contract

The repository implements:

| Object | Grain / purpose |
| --- | --- |
| `qv_report.periods` | One row per archive run/period |
| `qv_report.period_metrics` | Workload totals per period |
| `qv_report.query_period_metrics` | Workload totals per period/query |
| `qv_report.wait_period_metrics` | Wait totals per period/category |
| `qv_report.query_wait_period_metrics` | Wait totals per period/query/category |
| `qv_report.query_plans` | Plan inventory with native Showplan XML |
| `qv_report.usp_GetShowplanXml` | Native XML retrieval by period/query/plan |

Period classification is not stored. The contract returns nullable
`period_classification`, and dashboards display `Unclassified (not recorded)`.
It is not inferred from free text.

`dbo.usp_GetArchiveSummary` remains an administrative compatibility interface;
it is not superseded or used by Grafana.

## Grafana package and security

The four dashboards are QueryVault Overview, Period Comparison, Wait Analysis,
and Query Detail. Every variable and panel query uses `qv_report`. Plans are
listed as metadata; QueryVault does not render them. Native Showplan XML can be
exported as `.sqlplan` and opened in SSMS.

`qv_report` must be owned by `dbo` so ownership chaining can protect internal
tables. A dedicated `queryvault_grafana` user receives schema-level `SELECT` and
execution of the Showplan procedure only. Passwords are supplied through the
Grafana environment or an approved secret manager and are not stored in Git.

## Repository and DACPAC authority

Operational, repeat-deployable procedures remain under
`QueryVault/StoredProcedures`; idempotent partition wrappers remain under
`QueryVault/Partitions`. Declarative SSDT equivalents live in the respective
`DatabaseProject` subdirectories. Reporting views and the Showplan procedure
follow the same operational/declarative split.

Both SQL project manifests build declarative tables, partitions, core
procedures, the `qv_report` schema, reporting views, and reporting procedure.
They reference the SQL Server 2019 `master.dacpac`. Repository tests enforce
that model procedure/view bodies remain synchronized with deployment sources.

The repository still contains zero-byte legacy files at the QueryVault root.
They are not canonical implementations or build inputs.

## Environment evidence

### Voyager1 audit environment

- SQL Server 2019 Developer, compatibility 150.
- Older deployed capture produced 884 runtime rows with two duplicate logical
  grains; the guarded repository procedure was not deployed.
- Six wait rows showed no duplicate wait grain, which is too small to establish
  correctness.
- Legacy maintenance constraints and deployed/repository table-shape drift were
  observed.
- The isolated safety branch produced a zero-error, zero-warning DACPAC with
  Visual Studio Community 2026 SSDT.

### Voyager2 production-shaped environment

- `QueryVaultDB` online at compatibility 170.
- 39 archive runs, 37 completed, across `NDP_Web`, `StackOverflow2013`, and
  `WideWorldImporters`.
- 2,366 runtime rows and 391 wait rows; no duplicate documented-grain groups or
  interval orphans were found.
- Nine early RunIDs—1, 2, 5, 6, 7, 8, 9, 14, 15—contain intervals ending after
  the recorded period end and predate the completed-interval safeguard. Treat
  them as potentially partial, not authoritative baselines.
- Reporting SQL and all 49 dashboard queries passed inside rolled-back temporary
  schema validation. Period 47 reconciled to direct archive totals and returned
  native Showplan XML.
- `qv_report` and `queryvault_grafana` are not deployed.
- An unrelated `caplab-grafana` 13.1.0 container exists and was not changed.

## Known gaps

- Canonical source aggregation and provisional reconciliation are not
  implemented.
- Overlapping archive windows are allowed and can duplicate periods by design.
- There is no consistent source snapshot across the multi-statement capture.
- Retention classifications, environment/configuration snapshots, Query Store
  context settings, and replica lineage are absent.
- `CompressionDelayMinutes`, `MaxRowsPerBatch`, `@BatchSize`, and
  `EnableParallelCopy` are exposed but not operationally applied.
- Version claims and newer Query Store columns need an explicit compatibility
  policy.
- Live least-privilege Grafana execution and dashboard rendering remain blocked
  until approved deployment and provisioning.

See [target/gap analysis](TARGET_GAP_ANALYSIS.md) and
[validation](VALIDATION_REPORT.md). The unchanged
[Voyager1 safety handoff](HANDOFF_QUERYVAULT_AUDIT_SAFETY.md) remains the
engineering record for the isolated source branch.

# QueryVault Current State

Status date: 2026-09-03. Working branch:
`codex/queryvault-run-partitioning`, created from
`origin/codex/queryvault-canonical-aggregation` at
`cac2e5a4391647523b4a42d8b040f260bbd2dac5`.

## Current architecture

QueryVault is a same-instance, long-term archive of selected SQL Server Query
Store periods. It is not a Query Store replacement and does not provide live
monitoring, a web UI, or an execution-plan renderer. One archive execution
creates a logical `RunMetadata` period, allocates its run-owned storage
lifecycle, copies completed Query Store metadata and native statistic
contributors, materializes canonical observations, and publishes the result
through the stable `qv_report` boundary.

The implementation has three layers:

1. configuration and logical period metadata in `DatabaseConfig` and
   `RunMetadata`;
2. internal RunID-partitioned Query Store metadata, contributor facts,
   canonical facts, and aligned maintenance tables; and
3. the stable `qv_report` views and native Showplan retrieval procedure.

`RunID` is the immutable logical period identity and the lifecycle key carried
by every run-owned row. SQL Server `partition_number` is derived from
`PF_RunID`, is not stored in metadata, and may change when an older boundary is
merged. One retained run is isolated in one intended physical partition; a
configurable capture schedule does not imply calendar-based partitions.

## Current schema

Metadata:

- `dbo.DatabaseConfig`, now including `MaxRetainedRuns` (default 1,000;
  1..14,990), `PartitionWarningPct` (default 80; 50..95), and `StorageMode`
  (`AUTO`, `ROWSTORE`, or `COLUMNSTORE`; default `AUTO`);
- `dbo.RunMetadata`, retaining existing logical identity, period state,
  protection, timing, source, and row-count metadata. No redundant archive key,
  physical partition number, or misleading per-run storage-mode field was
  added.

Run-owned archive tables:

- query text, query, plan, and runtime interval metadata;
- legacy runtime and wait facts;
- lossless runtime and wait contributor facts; and
- canonical runtime and wait facts.

All ten run-owned tables and their ten `PartitionMaintenance` mirrors use
`PF_RunID`/`PS_RunID`, clustered columnstore, and aligned nonclustered keys.
Canonical facts have unique keys at the documented Query Store grains.
Contributor tables retain native statistic IDs and SQL Server 2022+
`replica_group_id` lineage.

There are no shared/deduplicated data tables today. Future immutable query-text
or Showplan objects would be shared and must remain outside the run switch and
truncate lifecycle. `DatabaseConfig` and `RunMetadata` are metadata, not
switchable fact tables.

New administrative objects are:

- `dbo.ufn_EvaluatePartitionCapacity`, a deterministic inline policy function;
- `dbo.vw_QueryVaultStorageRecommendation`, an advisory view that evaluates
  recent RuntimeStats and WaitStats volumes independently; and
- `Scripts/MigrateRunPartitioning.sql`, an idempotent additive migration for
  the three configuration columns and their checks/defaults.

The existing `FixPartitionMaintenanceSwitchConstraints.sql` compatibility
migration is now part of deployment ordering. On older installations it drops
only the six named tautological `CHECK (RunID = RunID)` constraints that SQL
Server cannot semantically validate for `ALTER TABLE ... SWITCH`; partitioning,
keys, data, and meaningful canonical-state constraints are unchanged.

## Existing capture logic

`dbo.usp_ArchiveQueryStore`:

- accepts a local source database and requested window;
- inserts one `RunMetadata` identity, then calls `EnsureRunPartition` for that
  exact RunID and its configuration;
- reads `flush_interval_seconds`, caps the end at current UTC minus one flush
  interval, and captures only completed intervals;
- copies query text, query, plan, and interval metadata;
- retains every selected native runtime and wait row as a contributor;
- projects `replica_group_id` on SQL Server 2022+ and NULL on older versions;
- materializes runtime by `(plan_id, execution_type,
  runtime_stats_interval_id)`;
- materializes waits by `(plan_id, runtime_stats_interval_id, execution_type,
  wait_category)`;
- records existing runtime/wait counts and completes the logical period in the
  archive transaction; and
- preserves failed-run metadata if the archive transaction rolls back.

The partition manager serializes allocation using a transaction-owned
application lock. It allocates only missing boundaries at `RunID` and
`RunID + 1`; identity gaps therefore consume at most two physical boundaries,
not one partition per skipped ID. It refuses to split a nonempty legacy
overflow partition.

## Existing retention logic

`DoNotDelete` protects a period. Otherwise, a completed period with an expired
`RetentionDate` is eligible only when its matching `DatabaseConfig` enables
automatic deletion. Purge supports dry-run preview and rechecks eligibility
under locks.

For each eligible run, purge:

1. switches all ten aligned run-owned partitions to maintenance tables;
2. truncates those maintenance partitions;
3. deletes `RunMetadata`; and
4. merges the obsolete exact RunID boundary.

Switch/truncate reject shared physical partitions, nonempty targets, and pinned
runs. Merge rejects pinned or surviving metadata and verifies the target
partition is empty across all twenty archive/maintenance tables. Direct
maintenance operations commit or roll back only transactions they own.

`MaxRetainedRuns` is evaluated per configured server/database over retained
`In Progress` and `Completed` runs. It is not a lifetime RunID ceiling.
Warnings begin at the configured percentage. A separate physical guard honors
SQL Server's 15,000-partition maximum and reserves ten partitions, making
14,990 the operational ceiling.

Rolling, Baseline, Incident, and Pinned are still not authoritative stored
classifications. `DoNotDelete` provides protection but is not a substitute for
the approved classification model.

## Current Query Store correctness

Canonical runtime aggregation is implemented for new captures at the
documented plan/execution-type/interval grain. Canonical wait aggregation is
implemented at plan/interval/execution-type/wait-category grain with additive
wait totals and matching runtime-execution denominators. Native statistic IDs
are contributor attributes, not canonical keys; replica groups remain lineage.

Runtime counts and totals are additive, means are execution-weighted, extrema
are combined, and chronological last values are selected only when
unambiguous. Unsupported multi-contributor dispersion and ambiguous last values
are explicitly unavailable with status fields. No contributor is discarded.

Normal capture excludes active intervals. The schema and materializer support
`PROVISIONAL`, but active capture and audited close/reconcile orchestration are
not implemented. Legacy facts remain unchanged; `qv_report` prefers canonical
facts per run and falls back to legacy only when a run has no canonical facts.

The local SQL Server 2019 validation archive contains legacy duplicate runtime
groups in RunIDs 8 and 12. It also contains RunID 1004 in the nonempty overflow
partition above boundary 120. The new guard reports that a reviewed migration
is required rather than attempting an unsafe columnstore split. No local data
was moved or deleted.

## Reporting objects

The stable public interface remains unchanged:

| Object | Purpose |
| --- | --- |
| `qv_report.periods` | archived periods and observation state |
| `qv_report.period_metrics` | workload summary per period |
| `qv_report.query_period_metrics` | top-query and query-performance metrics |
| `qv_report.wait_period_metrics` | wait summary per period/category |
| `qv_report.query_wait_period_metrics` | waits per period/query/category |
| `qv_report.query_plans` | plan history and native Showplan XML |
| `qv_report.usp_GetShowplanXml` | native Showplan retrieval |

No `qv_report` or Grafana file changed in this workstream. SSMS, Power BI,
Grafana, scripts, and future consumers should continue using this interface.
The storage recommendation view is an administrative `dbo` object, not a
reporting-contract replacement.

## Python components

There are no Python sources, package manifests, or Python runtime components.
Automation uses PowerShell, SQLCMD/T-SQL, and SSDT/MSBuild.

## Incomplete features

- controlled Rolling/Baseline/Incident/Pinned classifications and transition
  history;
- active-interval capture and audited close/reconcile orchestration;
- a consistent multi-view source snapshot during capture;
- cross-period immutable query-text and Showplan deduplication;
- Query Store context-settings and options snapshots;
- full server/database environment and configuration snapshots;
- production-shaped rowstore versus columnstore benchmarks and any actual
  `StorageMode` conversion workflow;
- evaluated `COLUMNSTORE_ARCHIVE` transitions for cold preserved partitions;
- remote source capture and formal source identity;
- overlap/idempotency policy for archive windows; and
- reviewed migration of legacy rows currently sharing overflow partitions.

## Potential data-loss or correctness problems

- old legacy runtime facts can contain multiple native rows at one logical
  grain and should not be used as canonical baselines without reconciliation;
- historical periods can extend beyond recorded bounds or be partial;
- separate source catalog statements can observe Query Store cleanup/change at
  different moments;
- legacy overflow data prevents safe exact splitting with clustered
  columnstore and requires an explicit migration plan;
- retention is destructive after operator approval; backup remains the
  recovery path;
- active intervals are excluded, so there is no provisional incident capture
  workflow yet; and
- version-dependent metadata beyond replica lineage needs a formal adapter and
  live SQL Server 2022+ validation.

## Reusable functionality

Reusable components include completed-interval selection, lossless contributor
capture, canonical materialization, version-aware replica projection,
RunID-based exact/sparse partition allocation, capacity policy, serialized
partition management, aligned twenty-table lifecycle checks, dry-run purge,
native Query Store metadata capture, the unchanged `qv_report`/Grafana
boundary, native Showplan workflow, SSDT model, deployment pre/post checks, and
transactional deterministic tests.

The requested change was implemented as a focused lifecycle formalization, not
a broad schema redesign. Apart from the three additive settings, function,
view, and removal of the six legacy tautological switch blockers when present,
existing storage is reused. No redundant `ArchiveRunKey` was added, no
reporting contract changed, and no database, SQL Agent job, login, Grafana
instance, master branch, or Voyager2 object was deployed or modified.

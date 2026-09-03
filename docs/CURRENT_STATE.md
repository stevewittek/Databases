# QueryVault current state

Audit date: 2026-09-02; validation updated 2026-09-03

## Scope and evidence

This document describes the checked-in repository at `db0d8e6` and, where explicitly labelled, a read-only snapshot of the local `QueryVaultDB` deployment. The repository is the source of truth for the implementation assessment. The local database is useful evidence, but it is not assumed to represent every deployment.

The review covered every tracked source file, the GitHub Actions workflow, recent Git history, both SQL project manifests, deployment and compatibility scripts, SQL Agent scripts, tests, and the local SQL Server catalogs. No destructive database operation was performed.

Microsoft documentation used for the Query Store correctness review:

- [`sys.query_store_runtime_stats`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql): the complete logical grain is `plan_id`, `execution_type`, and `runtime_stats_interval_id`; multiple rows can represent the active interval and must be aggregated.
- [`sys.query_store_wait_stats`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-wait-stats-transact-sql): the complete logical grain is `plan_id`, `runtime_stats_interval_id`, `execution_type`, and `wait_category`; multiple active-interval rows must be aggregated.
- [`sys.query_store_runtime_stats_interval`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-interval-transact-sql): supplies the collection interval start and end boundaries.
- [`sys.query_context_settings`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-context-settings-transact-sql): records semantic settings that distinguish otherwise identical query text.
- [`sys.database_query_store_options`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-database-query-store-options-transact-sql): exposes Query Store state, interval length, flush interval, capture mode, cleanup, and wait-capture settings.

## Executive assessment

The repository contains a functional prototype of a centralized Query Store copier with run metadata, per-run partitions, clustered columnstore tables, SQL Agent automation, and a retention purge path. Those pieces are reusable, but the current data model is still a snapshot/run archive rather than the approved long-term period archive.

The implementation does not yet satisfy the hard runtime-statistics rule. It copies native rows keyed by `runtime_stats_id` instead of producing one archived observation at the documented grain. Wait statistics are handled the same way. The newer checked-in procedure avoids the most recent flush window and therefore lowers the chance of duplicates, but delaying capture is not equivalent to aggregating the source rows.

The stable `qv_report.*` contract does not exist. Consumers are directed to `dbo` tables and `dbo.usp_GetArchiveSummary`, so storage is not isolated from reporting.

## Current architecture

The implemented flow is:

1. `dbo.DatabaseConfig` registers an enabled database on the local SQL Server and stores schedule, lookback, and retention defaults.
2. A caller or SQL Agent job executes `dbo.usp_ArchiveQueryStore` for a time window.
3. The procedure inserts one `dbo.RunMetadata` row and uses its identity `RunID` as both the logical archive identifier and the physical partition key.
4. Six Query Store catalog views are copied into six `dbo.query_store_*` tables. Metadata rows are restricted to objects that have runtime activity in the selected window.
5. Every archive table has a clustered columnstore index plus a nonclustered primary key, and every table is partitioned by `RunID` through `PS_RunID`/`PF_RunID`.
6. Matching `_PartitionMaintenance` tables support partition switching. `dbo.usp_PurgeExpiredArchives` selects completed, expired, unprotected runs, switches each run's partitions, truncates them, and deletes `RunMetadata`.
7. PowerShell scripts provide guarded deployment, pre/post catalog snapshots, and copy-only backup verification. A manually triggered GitHub Actions workflow targets a self-hosted Voyager 2 runner.

This is centralized and local-instance only. Although configuration stores `ServerName`, capture uses three-part names on the current instance and filters configuration by `@@SERVERNAME`; there is no remote-server capture path.

## Repository authority and deployment paths

The intended deployment sources are under `QueryVault/Partitions`, `QueryVault/Tables`, and `QueryVault/StoredProcedures`. `Scripts/Deploy.sql` and `Scripts/DeployQueryVault.ps1` consume those paths. Because SSDT model files must be declarative, `Partitions/DatabaseProject` and `StoredProcedures/DatabaseProject` contain project-compatible definitions. A repository contract test compares every SSDT procedure body with its deployment source after normalizing only the required `CREATE OR ALTER`/`CREATE` declaration difference.

The repository also contains 31 zero-byte legacy files at the `QueryVault` root, including table, procedure, deployment, and job names. They are not implementations.

Two project manifests coexist:

- `QueryVault.sqlproj` is referenced by `Databases.slnx`. At the start of this audit it built zero-byte root files, canonical files, SQLCMD deployment scripts, SQL Agent scripts, and compatibility scripts together. The audit fix removed the invalid build items; it now builds 21 declarative partition, table, and procedure model sources and references the SQL Server 2019 `master.dacpac` for system-catalog validation.
- `QueryVault_Fixed.sqlproj` is the older cleaned alternative. It remains as a secondary manifest and now tracks the same new test artifacts as non-build items.

The production PowerShell deployer does not publish a DACPAC. It executes canonical table files only when the table is absent, always runs the idempotent partition scripts, and refreshes five stored procedures. Consequently, it preserves data but cannot migrate an existing table shape. Compatibility or constraint fixes are separate manual scripts and are not part of that deployment path.

## Current schema

### Core metadata

| Object | Purpose | Important keys/state |
| --- | --- | --- |
| `dbo.DatabaseConfig` | Source registration and operational defaults | Identity `ConfigID`; unique `(DatabaseName, ServerName)`; enabled flag; lookback; schedule fields; compression-delay setting; retention days; auto-delete flag; batch/parallel settings |
| `dbo.RunMetadata` | One row per capture execution | Identity `RunID`; source and requested/effective time range; `In Progress`/`Completed`/`Failed`; `DoNotDelete`; retention date; per-table row counts |

There is no first-class vault period entity, retention-class lookup, incident/baseline metadata, capture version, reconciliation state, source database identity that survives rename, or environment/configuration snapshot.

### Archive tables

| Table | Current key | Current content |
| --- | --- | --- |
| `dbo.query_store_query_text` | `(RunID, query_text_id)` | SQL text, statement handle, encrypted/restricted flags |
| `dbo.query_store_query` | `(RunID, query_id)` | Query-to-text/context IDs, object and handles, query hash, parameterization, compile aggregates |
| `dbo.query_store_plan` | `(RunID, plan_id)` | Query relationship, engine/compatibility, plan hash, Showplan text, forcing and compile fields, recent-version plan fields |
| `dbo.query_store_runtime_stats_interval` | `(RunID, runtime_stats_interval_id)` | Native interval start/end/comment |
| `dbo.query_store_runtime_stats` | `(RunID, runtime_stats_id)` | Native runtime row, including counts, average/last/min/max/stdev metrics and `replica_group_id` |
| `dbo.query_store_wait_stats` | `(RunID, wait_stats_id)` | Native wait row, including category, execution type, total/average/last/min/max/stdev and `replica_group_id` |

All six archive tables and all six maintenance tables use a clustered columnstore index. The primary keys are aligned nonclustered indexes because they include `RunID`. All partitions currently map to `PRIMARY`.

The `CompressionDelayMinutes` setting is read by the archive procedure but never used. `MaxRowsPerBatch`, the `@BatchSize` parameter, and `EnableParallelCopy` are also unused.

### Partition model

`PF_RunID` is a `RANGE RIGHT` integer function initially containing boundaries 1 through 100. In normal sequential operation, each positive `RunID` receives its own partition. `usp_ArchiveQueryStore` extends the function when the new ID exceeds the current maximum boundary. The audit fix calculates enough new boundaries to cover an identity jump, with ten as the minimum growth increment.

This still makes one logical run equal one physical partition. Concurrent partition extension is not serialized. The audit fix makes `SwitchOut` and `Truncate` refuse a physical partition containing any other `RunID` and makes those operations internally transactional when called without an outer transaction.

The maintenance tables mirror the archive tables. Fresh canonical definitions have no extra check constraints. A separate repair script drops tautological legacy constraints that block switching, but the normal deployment skips existing tables and does not run that repair.

## Existing capture logic

`dbo.usp_ArchiveQueryStore` currently:

- requires an enabled `DatabaseConfig` row for the current server;
- gets `flush_interval_seconds` from the source database;
- clamps the requested end time to `SYSUTCDATETIME() - flush_interval_seconds`;
- selects intervals where `end_time > @StartDateTime` and `end_time <= @EndDateTime`;
- inserts `RunMetadata` before the data transaction so failures remain visible;
- copies intervals, relevant query text, queries, plans, raw runtime-stat rows, and raw wait-stat rows in one transaction;
- rejects the run if either raw fact table contains more than one row at its documented logical grain;
- updates per-table counts and marks the run complete; and
- rolls back fact/dimension inserts and marks metadata failed on an error.

There is no watermark or uniqueness rule for a logical period, so scheduled lookback windows can overlap and archive the same native intervals repeatedly under different `RunID` values. There is no consistent source snapshot across the multiple catalog queries. There is no validation of Query Store actual state, wait-stat capture mode, source compatibility, or available catalog columns before capture.

## Existing retention logic

Retention is binary rather than classified:

- `DoNotDelete = 1` protects a run indefinitely.
- Otherwise, `RetentionDate` is calculated from capture time plus a number of days.
- Automated purge additionally requires the source `DatabaseConfig.AutoDeleteEnabled = 1` and `RunStatus = 'Completed'`.
- `@DryRun = 1` previews eligible runs.
- Purge processes each run in a transaction and continues after individual failures, then throws if any failed.

The repository purge path is a useful foundation. It does not model Rolling, Baseline, Incident, and Pinned explicitly, and it cannot expire a storage partition independently of a logical period because the two concepts are the same `RunID`.

## Query Store correctness

### Runtime statistics

Status: not compliant with the hard correctness rule.

Microsoft defines the observation grain as `(plan_id, execution_type, runtime_stats_interval_id)` and requires aggregation when multiple source rows exist. The procedure inserts each native row and uses `(RunID, runtime_stats_id)` as its key. The audit fix prevents such a run from being marked complete when duplicate grains are detected, but it does not supply the required aggregate. The procedure still does not calculate additive totals, execution-weighted averages, combined extrema, chronological last values, or combined dispersion.

The flush-window cutoff and completed-interval predicate are worthwhile safeguards, but they only reduce exposure to in-memory/persisted duplication. They do not establish the required archived grain and do not provide an active-interval reconciliation path.

Read-only evidence from the local deployment: 884 archived runtime rows contained two duplicate logical grains (two extra rows). Both duplicates came from an interval ending at 19:15 that was captured about one minute later by the older deployed procedure. This proves the archive can contain multiple physical rows for one logical observation.

### Wait statistics

Status: not compliant with the equivalent documented rule.

Microsoft defines the wait observation grain as `(plan_id, runtime_stats_interval_id, execution_type, wait_category)` and explicitly describes the same persisted/in-memory multiplicity for the active interval. The procedure copies native rows keyed by `wait_stats_id` without grouping. The audit fix fails the run if duplicate wait grains are detected. A correct design must still define how totals, per-execution averages, extrema, last value, and dispersion are combined and must account for the relationship to runtime execution counts.

The local deployment had no duplicate wait grains in its six archived rows, but that small result does not validate the path.

### Completed and provisional intervals

The checked-in procedure attempts to capture only safely flushed completed intervals. It has no `COMPLETED`/`PROVISIONAL` data-state column, no option to capture an active interval, and no reconciliation mechanism. The `RunStatus = 'Completed'` value means the copy operation completed; it does not mean every source interval has a final observation.

## Native metadata preservation

The archive preserves much of the six principal Query Store views, including SQL text, query hashes, plan hashes, Showplan XML text, forcing state, compile metrics, interval boundaries, runtime metrics, and wait metrics.

Important gaps include:

- `sys.query_context_settings`, even though `query_store_query.context_settings_id` is stored;
- a snapshot of `sys.database_query_store_options`;
- database compatibility/scoped configuration and other environment settings at period time;
- server/database version, collation, cardinality-estimator-relevant settings, hardware/resource governance, and deployment/application version;
- Query Store replica metadata for stored `replica_group_id` values;
- newer Query Store surfaces such as query variants and Query Store hints, subject to a supported-version policy.

Version support is inconsistent. The project targets SQL Server 2019 (`Sql150`) and documentation claims SQL Server 2016+, while canonical table/procedure sources reference columns introduced in later versions, including `replica_group_id`. Wait statistics themselves require SQL Server 2017+. Historical SQL Server 2019 fix scripts are destructive drop/recreate scripts and diverge from the canonical definitions.

## Reporting objects

There is no `qv_report` schema and none of the required reporting objects exists.

The only reporting-oriented database object is `dbo.usp_GetArchiveSummary`, which returns run metadata and a partition number. README examples tell consumers to query internal `dbo.query_store_*` tables directly. There are no stable contracts for:

- `VaultPeriods`
- `WorkloadSummary`
- `TopQueries`
- `WaitSummary`
- `QueryPerformance`
- `PlanHistory`
- `PeriodComparison`
- `QueryDetail`
- `GetPlan`

No web UI, live monitor, or plan renderer exists, which is consistent with the approved scope.

## Python components

There are no Python source files, packages, dependency manifests, migrations, or tests in the repository.

Automation is implemented in T-SQL, PowerShell, Bash, and GitHub Actions. The PowerShell production sequence provides useful backup and state-preservation controls but does not validate Query Store semantic grain.

## Test and validation coverage

The original database test is `Tests/TestPurgeExpiredArchives.sql`. It inserts an eligible metadata row, executes purge, verifies deletion, and rolls back. It depends on a pre-existing enabled auto-delete configuration and does not insert fact rows, verify all six switches, or test protected/non-completed cases.

This audit adds `TestPartitionSafetyGuards.sql`, a transactional test proving that a shared overflow maintenance partition is rejected without deleting either run, and `TestProcedureCompilation.sql`, which loads and refreshes the changed procedures inside a transaction and rolls back. `TestRepositoryContracts.ps1` verifies project items, source existence, identity-jump growth, runtime/wait grain guards, partition guards, SSDT/deployment procedure synchronization, the system database reference, and required documentation.

`Scripts/TestQueryVaultDeployment.ps1` checks expected objects, row counts, configuration hashes, Agent hashes, and procedure compilation. It does not compare table schemas to source, validate index compression/state, test capture, verify reporting contracts, or detect duplicate logical observations.

Visual Studio Community 2026 18.9.2 and its SSDT targets are installed on this PC independently of VS Code. Validation with `MSBuild.exe`, `VisualStudioVersion=18.0`, and the SQL Server 2019 target now produces `QueryVault.dacpac` successfully with zero build errors and zero warnings. The initial real SSDT run exposed 57 source/model errors; the safe audit fix separated idempotent deployment wrappers from declarative model definitions, removed non-model `PRINT` batches from model inputs, schema-qualified `sys.sp_executesql`, and added the `master.dacpac` reference.

## Local deployment snapshot

Read-only observations on 2026-09-02:

- SQL Server 2019 Developer, database compatibility level 150.
- 14 user tables and four procedures; `usp_PurgeExpiredArchives` is not deployed.
- 11 completed runs, six query/plan/text rows, 884 runtime rows, 887 interval rows, and six wait rows.
- 10 pairs of completed archive runs have overlapping time ranges.
- `PF_RunID` has 121 partitions and a maximum boundary of 120.
- Legacy maintenance-table check constraints are still present, so the repository notes that partition switching can fail until the repair script is applied.
- The deployed plan/runtime/wait tables use the older SQL Server 2019-compatible shape, while canonical repository sources use a newer shape. The guarded deployer skips existing tables, so this drift persists by design.

## Incomplete or misleading features

- `CompressionDelayMinutes`, `MaxRowsPerBatch`, `@BatchSize`, and `EnableParallelCopy` are exposed but have no effect.
- `Deploy_Standalone.sql` says it is complete but only creates the database and prints manual instructions.
- Setup documentation describes an old local deployment as fully operational while also noting a wait-stats syntax error; it is historical and conflicts with current repository code.
- Job templates delete and recreate jobs and default ownership to `sa`; the dedicated Voyager script is newer and safer but environment-specific.
- The production workflow is manual-only, while its handoff document still describes an intended path-triggered workflow.
- The source database named `QueryVault` appears in the historical local configuration even though the archive database is `QueryVaultDB`; this may be intentional but is not explained.

## Potential data-loss and correctness problems

1. Runtime and wait rows are not aggregated at their documented grains, so consumers can double-count or treat partial rows as complete observations.
2. The archive already contains duplicate runtime grains in the inspected deployment.
3. Older deployed procedures remain vulnerable to shared-overflow switching and partial direct maintenance operations until the new guarded procedures are deliberately deployed.
4. Concurrent archive runs are not serialized around partition extension or source-period capture.
5. Overlapping runs duplicate intervals and immutable objects, inflate storage, and make period comparisons ambiguous unless consumers deduplicate deliberately.
6. Existing deployments can retain legacy constraints that block switching because normal deployment skips table migrations.
7. Canonical source columns do not match the declared SQL Server 2019/2016 support policy or the observed deployed schema.
8. Multi-statement catalog capture lacks a consistent source snapshot; Query Store cleanup or change during the run can produce an internally inconsistent archive.
9. The archive stores query text and plans once per run, increasing storage and preventing stable identities across periods.
10. No environment snapshot exists, so a performance difference can be misattributed when compatibility, Query Store settings, scoped configuration, resource limits, or engine version changed.
11. Consumers query internal tables directly, so any necessary storage redesign is a breaking reporting change.

## Reusable functionality

The following pieces should be retained or adapted rather than discarded:

- Source registration and metadata-driven defaults in `DatabaseConfig`.
- Run auditing, failure visibility, and per-entity row counts in `RunMetadata`.
- Safe identifier quoting with `QUOTENAME` for local cross-database reads.
- Restricting query/query-text/plan capture to entities active in the selected period.
- Transactional archive loading with failed-run metadata retained outside the data transaction.
- Completed-interval selection and the conservative flush-window safeguard.
- Partition-aligned clustered columnstore fact storage as a design starting point.
- Partition-switch maintenance tables and per-run transactional purge orchestration.
- Fail-closed duplicate-grain checks and shared-partition maintenance guards added by this audit.
- Dry-run retention preview and exclusion of failed/in-progress/protected runs.
- Guarded production deployment, pre/post state comparison, backup checksums, and `RESTORE VERIFYONLY`.
- A now-valid SSDT/DACPAC build, with synchronization checks protecting the small declarative adapters from deployment-source drift.
- Least-privilege direction in the Voyager Agent/deployer scripts.

These components need to be placed behind a versioned schema/migration strategy and a stable `qv_report` layer before the internal storage model is substantially changed.

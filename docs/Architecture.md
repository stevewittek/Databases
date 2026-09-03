# QueryVault Architecture

## Product boundary

QueryVault is a long-term archive of selected SQL Server Query Store periods.
It does not replace Query Store, monitor live activity, render execution plans,
or host a web UI.

The supported flow is:

Source Query Store -> archive procedure -> internal contributor/canonical
storage -> qv_report -> Grafana, SSMS, Power BI, or scripts.

Only qv_report is a supported consumer contract. The dbo archive tables and
PartitionMaintenance tables are implementation details.

## Capture flow

1. An operator or SQL Agent calls dbo.usp_ArchiveQueryStore for a local source
   database and requested window.
2. Capture creates one `RunMetadata` identity and asks the serialized partition
   manager to ensure an exact partition for that `RunID` plus an empty future
   partition.
3. Capture reads Query Store flush_interval_seconds and sets a safe end no later
   than current UTC minus one flush interval.
4. It copies only intervals whose end is within the selected completed window.
5. It archives query text, query, plan, and interval metadata.
6. It copies every native runtime and wait row to lossless contributor tables.
7. dbo.usp_MaterializeCanonicalQueryStoreStats rebuilds canonical rows for the
   RunID.
8. Capture records canonical fact counts and marks the logical period
   Completed.

All archive writes occur in the capture transaction. Failed-run metadata is
preserved outside it.

## Canonical fact model

Runtime contributors materialize to one fact at:

(RunID, plan_id, execution_type, runtime_stats_interval_id)

Wait contributors materialize to one fact at:

(RunID, plan_id, runtime_stats_interval_id, execution_type, wait_category)

Native statistic IDs and replica_group_id remain contributor lineage. They are
not canonical keys. Mixed replica contributors do not split a workload
observation.

Canonical facts distinguish COMPLETED and PROVISIONAL. Current archive capture
emits COMPLETED only. The schema can rematerialize provisional contributors,
but source recapture after interval close and an audited state transition are
future orchestration work.

## Storage and retention

`RunMetadata` is the logical archived period and `RunID` is its immutable
identity. The same `RunID` is intentionally the lifecycle key on run-owned
storage. SQL Server `partition_number` is a derived implementation detail: it
is never persisted in `RunMetadata`, used as an external identifier, or assumed
stable after older boundaries are merged.

Query Store metadata, contributor facts, canonical facts, and their aligned
maintenance tables use PF_RunID/PS_RunID. Fact storage uses clustered
columnstore. Exact/sparse boundaries isolate each retained run from its empty
future partition without allocating every skipped identity value. The
partition manager serializes allocation and lifecycle work with an application
lock, refuses nonempty legacy-overflow splits, enforces configuration and
physical capacity limits, and rejects any switch/truncate that is not isolated
to one RunID.

Expiration switches all ten run-owned table partitions to aligned maintenance
tables, truncates those partitions, deletes logical metadata, and merges the
obsolete boundary. Pinned metadata blocks switch, truncate, and merge. The
initial 1..100 bootstrap boundaries remain for deployment compatibility; new
growth is exact and sparse. A boundary merge can renumber later physical
partitions without changing any RunID.

Current ownership categories are:

- **Run-owned:** query text, query, plan, runtime interval, legacy runtime/wait,
  contributor runtime/wait, canonical runtime/wait, and all aligned maintenance
  mirrors. All participate in one run lifecycle.
- **Metadata:** `DatabaseConfig` and `RunMetadata`. They are not switched as
  fact partitions.
- **Shared:** none today. A future deduplicated query-text or Showplan store
  would be shared and must not be placed in the run-switch lifecycle.

`MaxRetainedRuns` limits retained logical runs per configured source; it does
not limit the lifetime RunID value. `PartitionWarningPct` controls warning
thresholds. Physical allocation separately protects SQL Server's 15,000
partition maximum and reserves ten partitions, producing an operational limit
of 14,990.

`StorageMode` is policy (`AUTO`, `ROWSTORE`, or `COLUMNSTORE`), not a per-run
claim about physical encoding. `dbo.vw_QueryVaultStorageRecommendation`
independently evaluates recent RuntimeStats and WaitStats volumes. It is
advisory only and never rebuilds an index automatically.

RetentionDate, AutoDeleteEnabled, and DoNotDelete control current expiration.
Rolling, Baseline, Incident, and Pinned require a future authoritative
classification model.

## Reporting boundary

qv_report.periods publishes period metadata and observation state.
qv_report.query_period_metrics and period_metrics publish workload facts.
qv_report.wait_period_metrics and query_wait_period_metrics publish wait facts.
qv_report.query_plans and usp_GetShowplanXml expose native SQL Server Showplan
XML.

For a given RunID, reporting reads canonical facts if present. It reads legacy
facts only when no canonical representation exists, preventing double counting
while retaining compatibility with earlier archive periods.

The existing Grafana dashboards query this interface only. Canonical
aggregation required no dashboard SQL or JSON changes.

## Reporting security

qv_report must be owned by dbo so ownership chaining can protect internal
tables. A reporting reader receives SELECT on the reporting schema and EXECUTE
on the Showplan procedure, not permission on internal dbo tables. Credentials
belong in an external secret source and are never stored in Git.

## Contract evolution

Reporting changes should be additive. Internal storage can evolve, including
immutable-object deduplication, environment snapshots, and cold compression,
without forcing consumers to query a new physical schema.

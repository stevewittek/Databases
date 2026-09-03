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
2. Capture reads Query Store flush_interval_seconds and sets a safe end no later
   than current UTC minus one flush interval.
3. It copies only intervals whose end is within the selected completed window.
4. It archives query text, query, plan, and interval metadata.
5. It copies every native runtime and wait row to lossless contributor tables.
6. dbo.usp_MaterializeCanonicalQueryStoreStats rebuilds canonical rows for the
   RunID.
7. Capture records canonical fact counts and marks the logical period
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

RunMetadata is the logical archived period. Today RunID is also the physical
partitioning key, so the approved long-term separation between logical periods
and physical partitions is not yet achieved.

Query Store metadata, contributor facts, canonical facts, and their aligned
maintenance tables use PF_RunID/PS_RunID. Fact storage uses clustered
columnstore. Partition switch/truncate supports efficient expiration when one
physical partition contains one RunID; safety guards reject a shared
partition.

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
logical/physical partition separation, immutable-object deduplication,
environment snapshots, and cold compression, without forcing consumers to
query a new physical schema.

# QueryVault Current State

Status date: 2026-09-03. Branch:
codex/queryvault-canonical-aggregation, based exactly on integration commit
e3a536d0ae90d326d0c8968a5964f1bcb7053c77.

## Current architecture

QueryVault is a same-instance SQL Server archive for selected Query Store
periods. It is not a Query Store replacement and does not provide live
monitoring. One archive execution creates a RunMetadata period, copies selected
completed Query Store intervals and metadata, preserves native statistic rows
as contributors, and materializes complete observations. Internal dbo storage
is exposed to consumers only through qv_report.

The current implementation has three storage layers:

1. period/configuration metadata in DatabaseConfig and RunMetadata;
2. Query Store metadata, lossless statistic contributors, and canonical facts
   in partitioned dbo tables; and
3. the stable qv_report views and native Showplan retrieval procedure.

Logical periods and physical storage are not yet separated: RunID is both the
period identity and partitioning key.

## Current schema

Metadata and legacy archive tables:

- DatabaseConfig and RunMetadata;
- query_store_query_text, query_store_query, query_store_plan;
- query_store_runtime_stats_interval;
- legacy query_store_runtime_stats and query_store_wait_stats.

Canonical aggregation adds:

- query_store_runtime_stats_contributor;
- query_store_runtime_stats_canonical;
- query_store_wait_stats_contributor; and
- query_store_wait_stats_canonical.

All ten Query Store archive tables have aligned PartitionMaintenance tables.
They are partitioned by RunID using PF_RunID/PS_RunID and use clustered
columnstore with aligned nonclustered keys. Canonical facts have natural
primary keys at the documented Query Store grains. Contributor tables use an
archive surrogate ID and retain native row IDs and SQL Server 2022+
replica_group_id lineage.

## Existing capture logic

dbo.usp_ArchiveQueryStore:

- accepts a local source database and requested window;
- reads flush_interval_seconds and caps the end at current UTC minus one flush
  interval;
- selects intervals with end_time greater than the start and less than or
  equal to the effective end;
- copies query text, query, plan, and interval metadata;
- copies every selected native runtime and wait row into contributor tables;
- projects replica_group_id on SQL Server 2022+ and NULL on older versions;
- materializes runtime by (plan_id, execution_type,
  runtime_stats_interval_id);
- materializes waits by (plan_id, runtime_stats_interval_id, execution_type,
  wait_category);
- records canonical fact counts and marks the period completed in one archive
  transaction; and
- preserves failed-run metadata if the archive transaction rolls back.

Runtime counts and totals are additive, means are execution-weighted, extrema
are combined, and chronological last values are selected only when unambiguous.
Wait totals are additive and average wait is total wait divided by matching
canonical executions. Unsupported multi-contributor dispersion and ambiguous
last values are explicitly NULL with status fields. No source contributor is
discarded.

Normal capture does not archive active intervals. The canonical schema supports
PROVISIONAL state and deterministic rematerialization, but active capture and
automatic close/reconcile orchestration are incomplete.

## Existing retention logic

DoNotDelete protects a period. Otherwise a completed period with an expired
RetentionDate is eligible only when its matching DatabaseConfig row enables
automatic deletion. Purge offers dry-run preview, rechecks eligibility under
locking, then switches and truncates aligned partitions.

Partition extension covers RunID identity jumps. Switch and truncate reject a
physical partition containing another RunID, and direct maintenance operations
only commit or roll back transactions they own.

Rolling, Baseline, Incident, and Pinned are not authoritative stored
classifications. The current DoNotDelete flag can protect data but is not a
substitute for the approved classification model.

## Current Query Store correctness

Canonical runtime aggregation is implemented for new captures. Canonical wait
aggregation is implemented using the documented wait grain and per-execution
average semantics. Native row IDs are contributor attributes, not canonical
keys. Replica groups remain lineage and do not split the canonical grain.

Completed-interval preference is implemented. Provisional state exists at the
fact/materializer layer, but active capture and later reconciliation are not
implemented.

Legacy facts remain unchanged. qv_report prefers canonical rows for a run and
uses legacy rows only when that run has no canonical representation. The local
SQL 2019 archive contains duplicate legacy runtime groups in RunIDs 8 and 12;
those periods require recapture or independent reconciliation before baseline
use.

## Reporting objects

The stable public interface is:

| Object | Purpose |
| --- | --- |
| qv_report.periods | Archived periods, classification placeholder, observation state |
| qv_report.period_metrics | Workload summary per period |
| qv_report.query_period_metrics | Top-query and query-performance metrics |
| qv_report.wait_period_metrics | Wait summary per period/category |
| qv_report.query_wait_period_metrics | Waits per period/query/category |
| qv_report.query_plans | Plan history and native Showplan XML |
| qv_report.usp_GetShowplanXml | Native Showplan retrieval |

The existing four Grafana dashboards continue to query only these objects.
Their JSON and SQL were not modified by canonical aggregation. SSMS, Power BI,
scripts, and future clients should use the same interface.

## Python components

There are no Python source files, Python package manifests, or Python runtime
components in the repository. Deployment and validation automation is
PowerShell, SQLCMD/T-SQL, and SSDT/MSBuild.

## Incomplete features

- controlled Rolling/Baseline/Incident/Pinned classifications;
- separation of logical periods from physical partitions;
- active-interval capture and close/reconcile scheduling;
- a consistent multi-view source snapshot during capture;
- cross-period query text and Showplan deduplication;
- Query Store context-settings and options snapshots;
- full server/database environment and configuration snapshots;
- evaluated COLUMNSTORE_ARCHIVE transitions for cold preserved partitions;
- remote SQL Server capture and a formal source identity;
- overlap/idempotency policy for archive windows; and
- live least-privilege Grafana and Voyager2 acceptance after an approved
  deployment.

## Potential data-loss or correctness problems

- legacy runtime facts can contain multiple native rows at one logical grain;
- old periods can extend beyond their recorded end and may be partial;
- several source catalog views are read in separate statements, so Query Store
  cleanup or change during capture can produce an inconsistent snapshot;
- current partition design couples retention granularity to RunID and refuses
  unsafe shared-partition operations rather than eliminating that layout risk;
- multi-contributor standard deviation cannot be reconstructed exactly without
  a documented native variance convention, so it is intentionally unavailable;
- active intervals are not archived, avoiding mislabelling but leaving no
  provisional incident workflow; and
- SQL Server version-dependent metadata beyond replica_group_id still needs a
  formal compatibility adapter and live SQL Server 2022+ validation.

## Reusable functionality

Reusable components include the completed-interval selector, additive
contributor/canonical schema, canonical materializer, version-aware replica
projection, partition safety guards, dry-run retention path, native Query Store
metadata capture, qv_report boundary, Grafana package, native Showplan
workflow, SSDT model, deployment pre/post checks, and deterministic
transactional tests.

No database, SQL Agent job, login, Grafana instance, or Voyager2 object was
changed while producing this branch.

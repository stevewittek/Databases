# Query Store Capture Correctness

Status date: 2026-09-03.

## Documented source grains

Microsoft documents that an active interval can expose more than one
sys.query_store_runtime_stats row because persisted and in-memory values are
separate. A complete runtime observation is:

(plan_id, execution_type, runtime_stats_interval_id)

The documented wait grain is:

(plan_id, runtime_stats_interval_id, execution_type, wait_category)

Native runtime_stats_id and wait_stats_id values identify source rows; they are
not canonical observation keys and can repeat among legitimate contributors.
SQL Server 2022 and later also expose replica_group_id. Replica is contributor
lineage, not part of either canonical grain.

References:

- [sys.query_store_runtime_stats](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql?view=sql-server-ver17)
- [sys.query_store_wait_stats](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-wait-stats-transact-sql?view=sql-server-ver17)

## Capture and materialization

dbo.usp_ArchiveQueryStore now preserves every selected native row in lossless
contributor tables, then calls dbo.usp_MaterializeCanonicalQueryStoreStats.
Duplicate source IDs or multiple rows at a documented grain are retained and
aggregated; they are no longer rejected or discarded.

Runtime materialization:

- sums count_executions into DECIMAL(38,0);
- computes each mean with count_executions as its weight;
- takes the minimum of minima and maximum of maxima;
- takes the earliest first_execution_time and latest last_execution_time;
- takes last-value metrics from the sole contributor at the latest execution
  time; a latest-time tie sets those values to NULL and records
  last_value_ambiguous = 1;
- preserves native standard deviation only for a single contributor; multiple
  contributors use NULL and UNAVAILABLE_MULTIPLE_CONTRIBUTORS, because
  Microsoft does not document whether Query Store's value is sample or
  population standard deviation; and
- keeps one replica ID only when all contributors have the same lineage.
  Otherwise the canonical replica is NULL, replica_count records the
  multiplicity, and the contributor rows retain every value.

Wait materialization:

- sums total_query_wait_time_ms into DECIMAL(38,0);
- calculates avg_query_wait_time_ms as canonical total wait divided by the
  matching canonical runtime execution count;
- combines minima and maxima;
- preserves last and standard deviation only for a single contributor;
- marks multi-contributor last values ambiguous because the wait catalog view
  exposes no execution timestamp with which to order contributors; and
- applies the same replica-lineage rule as runtime materialization.

Canonical primary keys enforce one row per RunID and documented grain.
Contributors keep independent surrogate IDs, so native IDs are never
misrepresented as unique archive observations.

## Completed and provisional intervals

Normal capture remains completed-interval-only. It reads
flush_interval_seconds, caps the requested end at current UTC minus one flush
interval, and requires interval.end_time <= effective end.

Canonical tables and the materializer support explicit COMPLETED and
PROVISIONAL states. Deterministic tests prove a run can be rematerialized from
the same contributor set as provisional. Capture of active intervals and an
automated close/reconcile workflow are not yet implemented; no current capture
silently labels an active interval complete.

## Reporting and legacy periods

qv_report uses canonical facts for a run when present. It falls back to the
legacy runtime/wait tables only for runs with no canonical rows, preserving
backward compatibility without mixing both representations. Legacy fallback is
labelled LEGACY_UNVERIFIED through qv_report.periods.

Legacy rows are not rewritten. The local SQL 2019 archive contains repeated
runtime grains in RunIDs 8 and 12, so those periods are not authoritative
baselines until independently reconciled or recaptured.

## Regression coverage

TestCanonicalQueryStoreAggregation.sql supplies deterministic rows covering
lossless duplicate IDs, grain isolation by plan/interval/execution/category,
execution-weighted runtime means, additive wait totals, wait denominators,
extrema, chronological last values, tied last timestamps, standard-deviation
status, replica lineage, canonical uniqueness, and provisional
rematerialization.

TestQueryStoreAggregationGrain.sql verifies completed-interval predicates,
contributor capture, both materialized grains, canonical uniqueness, interval
references, and legacy duplicate reporting. TestReportingCanonicalRegression
verifies canonical-first reporting and legacy fallback inside a transaction.

Source rows -> contributor tables -> canonical runtime/wait facts -> qv_report.
Legacy facts enter qv_report only for runs that have no canonical facts.

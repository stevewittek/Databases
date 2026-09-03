# QueryVault Target Gap Analysis

Status date: 2026-09-03. Allowed classifications are IMPLEMENTED, PARTIAL,
MISSING, NEEDS REDESIGN, and NEEDS VALIDATION.

## Approved core requirements

| # | Requirement | Status | Current evidence and remaining gap |
| --- | --- | --- | --- |
| 1 | Preserve selected Query Store periods outside normal retention | IMPLEMENTED | Completed intervals, metadata, contributor facts, and canonical facts are stored in QueryVaultDB under RunMetadata periods. Window overlap/idempotency policy remains desirable but does not prevent preservation. |
| 2 | Rolling, Baseline, Incident, and Pinned classifications | MISSING | DoNotDelete and RetentionDate exist, but the approved controlled classifications and transition history do not. |
| 3 | Separate logical periods from physical partitions | NEEDS REDESIGN | RunID is both period identity and partition key. Safety guards reject shared physical partitions; they do not decouple the concepts. |
| 4 | Partition-friendly high-volume fact storage | IMPLEMENTED | Runtime/wait contributor and canonical tables are RunID-partitioned with aligned keys and maintenance tables. The long-term physical key should be revisited with requirement 3. |
| 5 | Evaluate clustered columnstore for RuntimeStats and WaitStats | NEEDS VALIDATION | CCI is implemented on legacy, contributor, canonical, and maintenance tables. Workload compression, load, point-lookup, and reporting benchmarks have not been completed. |
| 6 | Partition switching for efficient expiration | PARTIAL | Aligned switch/truncate paths and multi-RunID safety guards exist. Coupling to RunID, concurrency, and populated canonical-fact expiration require production-shaped validation. |
| 7 | Evaluate COLUMNSTORE_ARCHIVE for cold preserved partitions | MISSING | No compression-tier transition or benchmark exists. |
| 8 | Preserve native Query Store metadata needed for interpretation | PARTIAL | Query text, query, plan, interval, runtime, wait, native row IDs, and SQL Server 2022+ replica lineage are retained. Context settings, Query Store options, and an explicit version adapter remain missing. |
| 9 | Deduplicate immutable query text and Showplan XML where safe | MISSING | Query text and plans are repeated by RunID. No content-addressed immutable-object store or reference migration exists. |
| 10 | Preserve environment/configuration metadata for comparison | PARTIAL | Source server/database and selected engine/compatibility fields are stored. Database-scoped configuration, Query Store options, hardware/edition, and other environment snapshots are absent. |

## Hard Query Store correctness

| Requirement | Status | Current evidence and remaining gap |
| --- | --- | --- |
| Runtime aggregation at (plan_id, execution_type, runtime_stats_interval_id) | IMPLEMENTED | Every native row is retained as a contributor; canonical counts, weighted means, extrema, chronological last values, ambiguity, dispersion status, and replica lineage are materialized with a unique canonical key. |
| Wait aggregation at (plan_id, runtime_stats_interval_id, execution_type, wait_category) | IMPLEMENTED | Additive total, runtime-execution denominator, extrema, ambiguity, conservative dispersion, contributor IDs, and replica lineage are implemented. Live SQL Server 2022+ multi-contributor evidence is still desirable. |
| Prefer completed Query Store intervals | IMPLEMENTED | Capture caps the end by flush_interval_seconds and requires interval end at or before the effective end. |
| Mark active captures PROVISIONAL | PARTIAL | Canonical facts and the materializer support PROVISIONAL. The normal capture procedure intentionally excludes active intervals. |
| Reconcile provisional observations after interval close | MISSING | Rematerialization is deterministic, but there is no source recapture/replacement scheduler or state-transition audit. |
| Do not treat native row IDs as canonical keys | IMPLEMENTED | Contributor surrogate keys retain native IDs; canonical primary keys use documented grains. |
| Preserve SQL Server 2022+ replica contribution | IMPLEMENTED | Version-aware capture stores replica_group_id per contributor. Mixed replicas are summarized without changing canonical grain. Live SQL Server 2022+ capture validation remains. |

## Reporting contract

| Contract capability | Status | Implementation |
| --- | --- | --- |
| Stable qv_report boundary | IMPLEMENTED | Six views and one procedure isolate internal tables; every dashboard query uses qv_report. |
| VaultPeriods | IMPLEMENTED | qv_report.periods |
| WorkloadSummary | IMPLEMENTED | qv_report.period_metrics |
| TopQueries | IMPLEMENTED | ordering/filtering over qv_report.query_period_metrics |
| WaitSummary | IMPLEMENTED | qv_report.wait_period_metrics |
| QueryPerformance | IMPLEMENTED | qv_report.query_period_metrics |
| PlanHistory | IMPLEMENTED | qv_report.query_plans |
| PeriodComparison | IMPLEMENTED | paired period_metrics/query_period_metrics/wait_period_metrics queries used by the existing dashboard |
| QueryDetail | IMPLEMENTED | query_period_metrics, query_wait_period_metrics, and query_plans |
| GetPlan/native Showplan XML | IMPLEMENTED | qv_report.usp_GetShowplanXml and qv_report.query_plans.showplan_xml |
| Canonical/legacy isolation | IMPLEMENTED | Reporting prefers canonical facts per run and falls back to legacy only when no canonical facts exist. Observation state exposes COMPLETED, PROVISIONAL, or LEGACY_UNVERIFIED. |

No web UI, custom plan renderer, or live-monitoring surface is implemented or
planned by this branch.

## Other engineering gaps

| Capability | Status | Remaining work |
| --- | --- | --- |
| Same-point-in-time source snapshot | NEEDS REDESIGN | Stage the selected Query Store surfaces under a documented consistency strategy that remains safe during Query Store cleanup. |
| Capture-window idempotency | MISSING | Define source identity and overlap/retry policy. |
| Remote source capture | MISSING | Current three-part names target the local SQL Server instance. |
| SQL Server version compatibility | PARTIAL | Replica columns are version-aware; newer query/plan/runtime columns need an explicit adapter and supported-version tests. |
| SSDT model | IMPLEMENTED | Visual Studio 2026 SSDT builds 38 objects with zero warnings/errors. |
| Deterministic aggregation tests | IMPLEMENTED | Synthetic test covers more than the 14 required correctness cases and rolls back all database changes. |
| Live Voyager2 acceptance | NEEDS VALIDATION | Direct hostname connection was unavailable from this PC. No deployment was attempted. |
| Retention integration test on this PC | NEEDS VALIDATION | Local QueryVaultDB predates the purge procedure and has no auto-delete configuration; procedure compilation and partition safety pass, but the existing purge scenario needs an approved suitable database. |

## Safe next sequence

1. Review and integrate this branch on top of the Mac reporting workstream.
2. Validate additive deployment planning against a copy of Voyager2 schema; do
   not infer migrations for existing tables.
3. Run SQL Server 2022+ source capture with genuine duplicate runtime and wait
   contributors and verify replica lineage.
4. Design active-interval recapture/reconciliation before enabling provisional
   capture.
5. Add authoritative retention classifications and decouple periods from
   physical partitions before expanding expiration automation.
6. Benchmark CCI and COLUMNSTORE_ARCHIVE on production-shaped fact volumes.

No step requires replacing Query Store, building a web UI, rendering plans, or
changing the existing Grafana dashboard SQL.

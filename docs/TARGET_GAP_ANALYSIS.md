# QueryVault Target Gap Analysis

Status date: 2026-09-03. Allowed classifications are `IMPLEMENTED`, `PARTIAL`,
`MISSING`, `NEEDS REDESIGN`, and `NEEDS VALIDATION`.

## Approved core requirements

| # | Requirement | Status | Current evidence and remaining gap |
| --- | --- | --- | --- |
| 1 | Preserve selected Query Store periods outside normal retention | IMPLEMENTED | Completed intervals, native metadata, all statistic contributors, and canonical observations are stored under durable `RunMetadata` periods. Window overlap/idempotency policy remains desirable. |
| 2 | Rolling, Baseline, Incident, and Pinned classifications | MISSING | `DoNotDelete` and `RetentionDate` protect/expire runs, but no authoritative controlled classification or transition history exists. |
| 3 | Separate logical archived periods from physical storage partitions | IMPLEMENTED | `RunID` remains the immutable logical identity and run lifecycle key; SQL Server `partition_number` is derived, never persisted or exposed, and may renumber after boundary merge. One intended physical partition contains one retained run. A future many-period physical grouping would require redesign, but is not needed for the approved run lifecycle. |
| 4 | Partition-friendly high-volume fact storage | IMPLEMENTED | All ten run-owned metadata/fact tables and ten maintenance mirrors are RunID-partitioned with aligned indexes. Exact/sparse growth allocates at most the missing RunID and empty future boundary, independent of identity gaps. |
| 5 | Evaluate clustered columnstore for RuntimeStats and WaitStats | NEEDS VALIDATION | Runtime/wait legacy, contributor, canonical, and maintenance tables use clustered columnstore. The new advisory evaluates RuntimeStats and WaitStats separately, but production-shaped load, compression, point-lookup, and reporting benchmarks remain. |
| 6 | Partition switching for efficient expiration | IMPLEMENTED | Purge transactionally switches and truncates all ten run-owned entities, deletes metadata, and merges the obsolete boundary. Pinned/shared/nonempty/alignment guards and real local switch/merge behavior are tested. Production-scale timing remains operational validation rather than a design gap. |
| 7 | Evaluate `COLUMNSTORE_ARCHIVE` for cold preserved partitions | MISSING | No cold-tier transition, operational policy, or benchmark exists. |
| 8 | Preserve native Query Store metadata needed for interpretation | PARTIAL | Query text, query, plan, interval, runtime, wait, native statistic IDs, and SQL Server 2022+ replica lineage are retained. Context settings, Query Store options, and a complete version adapter remain missing. |
| 9 | Deduplicate immutable query text and Showplan XML where safe | MISSING | Query text and plans remain run-owned and repeated by RunID. No shared content-addressed object store/reference migration exists. |
| 10 | Preserve environment/configuration metadata for comparison | PARTIAL | Source server/database and selected engine/compatibility fields are stored. Database-scoped configuration, Query Store options, edition/hardware, and other environment snapshots are absent. |

## Run lifecycle requirements

| Requirement | Status | Evidence and remaining gap |
| --- | --- | --- |
| Reuse existing RunID; no redundant archive key | IMPLEMENTED | Existing `RunMetadata.RunID INT IDENTITY` remains the sole logical identity and partition key. No `ArchiveRunKey` was added. |
| One retained run per intended physical lifecycle | IMPLEMENTED | `EnsureRunPartition` validates that RunID and RunID+1 map to distinct partitions; switch/truncate reject any other RunID in the partition. |
| Schedule remains configurable and not calendar-based | IMPLEMENTED | Existing schedule fields are unchanged. Partition allocation uses RunID, not date/month assumptions. |
| `partition_number` remains an implementation detail | IMPLEMENTED | It is calculated at operation time, not stored in metadata or used by `qv_report`. Boundary merge can safely renumber later partitions. |
| Exact/sparse allocation plus empty future partition | IMPLEMENTED | Only missing RunID and RunID+1 boundaries are split. Existing bootstrap boundaries 1..100 are retained for compatibility. |
| Switch/truncate then merge obsolete boundary | IMPLEMENTED | `usp_PurgeExpiredArchives` performs this order in one owned/caller transaction, with eligibility recheck. |
| Protect pinned/preserved periods | IMPLEMENTED | `DoNotDelete=1` blocks candidate selection and direct switch, truncate, and merge. Merge also refuses any surviving metadata. |
| Classify run-owned/shared/metadata storage | IMPLEMENTED | Ten archive entities are run-owned; `RunMetadata`/`DatabaseConfig` are metadata; no shared store exists. Future deduplicated immutable objects must be shared and excluded from switch lifecycle. |
| `MaxRetainedRuns` 1..14990/default 1000 | IMPLEMENTED | Declarative schema, additive migration, initialization procedure, checks, and deterministic tests exist. Count applies per config to retained `In Progress`/`Completed` runs. |
| `PartitionWarningPct` 50..95/default 80 | IMPLEMENTED | Schema/procedure validation and warning-threshold tests exist. |
| `StorageMode` AUTO/ROWSTORE/COLUMNSTORE/default AUTO | IMPLEMENTED | Schema/procedure validation exists. It is an advisory preference, not a false per-run physical claim. |
| Capacity warnings/configured maximum/hard ceiling | IMPLEMENTED | Deterministic function and serialized allocator enforce per-config count, configured warning, SQL Server hard 15,000, ten-partition reserve, and operational 14,990. |
| RunID can exceed physical partition count | IMPLEMENTED | Sparse policy depends on missing boundaries, not lifetime ID magnitude; deterministic policy and repository contracts test this. |
| Index alignment/minimal indexes | IMPLEMENTED | All twenty run-owned/maintenance tables retain aligned CCI and aligned nonclustered keys; lifecycle test verifies alignment. No new fact indexes were added. |
| Small-data rowstore advisory; runtime/wait independent | IMPLEMENTED | `dbo.vw_QueryVaultStorageRecommendation` emits separate RuntimeStats and WaitStats recommendations over the latest 20 completed runs. It makes no automatic physical change. Threshold tuning needs production validation. |
| Avoid misleading RunMetadata fields | IMPLEMENTED | No partition number, duplicated fact counts, or per-run physical storage-mode field was added. Existing runtime/wait count fields remain authoritative. |
| `qv_report` and Grafana unchanged | IMPLEMENTED | Git scope and repository contracts show no reporting view/procedure or dashboard change. |

## Hard Query Store correctness

| Requirement | Status | Current evidence and remaining gap |
| --- | --- | --- |
| Runtime aggregation at `(plan_id, execution_type, runtime_stats_interval_id)` | IMPLEMENTED | Every native row is retained as a contributor; canonical counts, weighted means, extrema, chronological last values, ambiguity, dispersion status, and replica lineage are materialized with a unique key. |
| Wait aggregation at `(plan_id, runtime_stats_interval_id, execution_type, wait_category)` | IMPLEMENTED | Additive total, matching runtime-execution denominator, extrema, ambiguity, conservative dispersion, native IDs, and replica lineage are implemented. Live SQL Server 2022+ multi-contributor evidence remains desirable. |
| Prefer completed Query Store intervals | IMPLEMENTED | Capture caps by `flush_interval_seconds` and requires interval end at or before the effective end. |
| Mark active captures PROVISIONAL | PARTIAL | Canonical schema/materializer support `PROVISIONAL`; normal capture intentionally excludes active intervals. |
| Reconcile provisional observations after close | MISSING | Deterministic rematerialization exists, but source recapture/replacement scheduling and audited state transitions do not. |
| Do not treat native row IDs as canonical keys | IMPLEMENTED | Contributor surrogate keys retain native IDs; canonical primary keys use documented grains. |
| Preserve SQL Server 2022+ replica contribution | IMPLEMENTED | Version-aware capture retains `replica_group_id` per contributor without changing canonical grain. Live 2022+ capture validation remains. |

## Reporting contract

| Contract capability | Status | Implementation |
| --- | --- | --- |
| Stable `qv_report` boundary | IMPLEMENTED | Six views and one procedure isolate internal tables; dashboards use this boundary. |
| VaultPeriods | IMPLEMENTED | `qv_report.periods` |
| WorkloadSummary | IMPLEMENTED | `qv_report.period_metrics` |
| TopQueries | IMPLEMENTED | ordering/filtering over `qv_report.query_period_metrics` |
| WaitSummary | IMPLEMENTED | `qv_report.wait_period_metrics` |
| QueryPerformance | IMPLEMENTED | `qv_report.query_period_metrics` |
| PlanHistory | IMPLEMENTED | `qv_report.query_plans` |
| PeriodComparison | IMPLEMENTED | paired period/query/wait metric queries |
| QueryDetail | IMPLEMENTED | query metrics, query waits, and plans |
| GetPlan/native Showplan XML | IMPLEMENTED | `qv_report.usp_GetShowplanXml` and `query_plans.showplan_xml` |
| Canonical/legacy isolation | IMPLEMENTED | Reporting prefers canonical facts per run and falls back only when canonical facts are absent. |

No web UI, custom plan renderer, or live-monitoring surface is implemented.

## Other engineering gaps

| Capability | Status | Remaining work |
| --- | --- | --- |
| Same-point-in-time source snapshot | NEEDS REDESIGN | Stage selected Query Store surfaces under a documented consistency strategy safe during Query Store cleanup. |
| Capture-window idempotency | MISSING | Define formal source identity and overlap/retry policy. |
| Remote source capture | MISSING | Current three-part names target the local SQL Server instance. |
| SQL Server version compatibility | PARTIAL | Replica columns are version-aware; newer metadata needs an explicit adapter and supported-version tests. |
| SSDT model | IMPLEMENTED | Installed Visual Studio 2026 SSDT builds both 40-object project manifests with zero reported warnings/errors. |
| Deterministic aggregation tests | IMPLEMENTED | Contributor/canonical fixture covers more than the original correctness minimum and rolls back. |
| Deterministic run lifecycle tests | IMPLEMENTED | Allocation, sparse policy, defaults/validation, warning/max/ceiling, alignment, real switch/truncate/merge, pin, purge, and reporting/canonical regressions pass transactionally. |
| Legacy overflow migration | NEEDS REDESIGN | Local validation found RunID 1004 in the populated overflow above boundary 120. The guard prevents an unsafe CCI split; migration must be separately reviewed and tested. |
| Live Voyager2 acceptance | NEEDS VALIDATION | This branch was not deployed to Voyager2. |
| SQL Server 2022+ replica capture | NEEDS VALIDATION | Static/synthetic behavior passes; a live 2022+ source capture was unavailable. |
| Production storage recommendation thresholds | NEEDS VALIDATION | The initial 100,000-row/recent-20-run advisory is deliberately non-mutating and requires representative benchmarks. |

## Safe next sequence

1. Review and integrate this branch on top of the lead Mac reporting workstream.
2. Generate and review an SSDT deployment plan against a production-like copy;
   do not infer a safe rewrite of populated overflow partitions.
3. Design and test the legacy-overflow migration separately.
4. Benchmark rowstore, columnstore, and `COLUMNSTORE_ARCHIVE` using
   production-shaped runtime and wait volumes.
5. Add authoritative retention classifications and environment snapshots.
6. Design active-interval recapture/reconciliation before enabling provisional
   capture.

This work avoided a broad redesign: it reused RunID, kept reporting stable,
added only configuration/policy/admin objects, and hardened the existing
partition lifecycle.

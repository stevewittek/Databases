# QueryVault Target and Gap Analysis

Status date: 2026-09-03. Status meanings are `IMPLEMENTED`, `PARTIAL`,
`MISSING`, `NEEDS REDESIGN`, `NEEDS VALIDATION`, and `BLOCKED`.

## Core archive and safety

| Capability | Status | Integrated implementation | Remaining target |
| --- | --- | --- | --- |
| Preserve Query Store history | PARTIAL | Six Query Store surfaces copied by UTC window into a centralized archive | Define logical-period idempotency, overlap policy, source identity, and completeness/reconciliation state |
| Completed-interval preference | IMPLEMENTED | Effective end is capped at one flush interval before now; interval end predicate is enforced | Prove source consistency under cleanup/concurrent Query Store change |
| Runtime source aggregation | PARTIAL | Duplicate documented-grain observations reject and roll back the run | Build one canonical source aggregate with defined metric and lineage semantics |
| Wait source aggregation | PARTIAL | Equivalent category-grain rejection guard | Define canonical total/average/extrema/last/dispersion behavior tied to executions |
| Identity-jump partition growth | IMPLEMENTED | Adds `max(10, RunID - maximum boundary)` boundaries | Serialize concurrent partition extension |
| Shared-partition protection | IMPLEMENTED | Switch and truncate reject another `RunID` in the physical partition | Decouple logical periods from physical storage partitions |
| Direct maintenance transaction safety | IMPLEMENTED | Direct switch/truncate owns and rolls back only its own transaction | Expand concurrency and populated-fact testing |
| Retention purge | PARTIAL | Dry-run, completed/unprotected/expired eligibility, transactional per-run purge | Add explicit Rolling/Baseline/Incident/Pinned policy and audit transitions |
| Columnstore storage | NEEDS VALIDATION | CCI exists on all archive and maintenance tables | Benchmark facts separately from text/plan/dimension data and evaluate archive compression |
| Native metadata preservation | PARTIAL | Broad query/text/plan/runtime/wait fields retained | Add context settings, Query Store options, environment snapshot, replica lineage, and version policy |

## Smallest correct source-aggregation design

Do not replace the fail-closed guard with `DISTINCT`, arbitrary `MIN`/`MAX`, or
last-writer selection. Those approaches silently discard measurements.

The smallest safe follow-on is a versioned capture adapter, behind the unchanged
`qv_report` contract, that:

1. materializes the selected source interval/runtime/wait rows in one consistent
   staging scope;
2. groups runtime rows by `(plan_id, execution_type,
   runtime_stats_interval_id)` and wait rows by that grain plus
   `wait_category`;
3. sums execution/additive totals, calculates execution-weighted means, combines
   minima/maxima, chooses “last” values from the row with the latest execution
   time, and uses a reviewed pooled-variance formula for dispersion;
4. preserves every contributing source identifier and replica group as lineage,
   instead of relabeling `MIN(runtime_stats_id)` as though it were a native
   observation;
5. reconciles staged counts/totals to the inserted canonical rows; and
6. leaves the current guard in place until tests prove those semantics.

The current archive row shape cannot represent multi-row lineage without
misstating a native identifier. Because this integration is not authorized to
redesign internal schema, aggregation is documented but not fabricated here.
Current completed-only capture remains safe-by-rejection but is not complete
support for source multiplicity.

## Reporting and visualization

| Capability | Status | Integrated implementation | Remaining target |
| --- | --- | --- | --- |
| Stable reporting boundary | IMPLEMENTED | Six views and one procedure under `qv_report`; no dashboard uses `dbo` | Deploy after DBA schema bootstrap and live validation |
| Overview dashboard | IMPLEMENTED | Periods, classification placeholder, executions, CPU, duration, reads, query/plan counts, waits | Render against approved live Grafana |
| Period Comparison | IMPLEMENTED | Baseline/comparison variables, workload/query/plan/wait deltas | Add duration normalization only through an additive contract change |
| Wait Analysis | IMPLEMENTED | Distribution, baseline change, selected-wait contributors | Validate empty/sparse waits in live UI |
| Query Detail | IMPLEMENTED | Text preview, metrics, waits, plans, period history | Validate query identity across known Query Store lifecycle events |
| Native Showplan path | IMPLEMENTED | XML view/procedure and `.sqlplan`/SSMS workflow | Complete one live export/open acceptance test |
| Period classification | MISSING | Nullable contract column; explicit “Unclassified” display | Add authoritative controlled classification without inferring run names |
| Least-privilege reader | BLOCKED | Password-free provisioning scripts and `dbo` ownership design | DBA bootstrap, login creation, positive API and negative internal-table tests |
| Grafana provisioning | NEEDS VALIDATION | Native MSSQL datasource and four file-provisioned dashboards | Load into a dedicated/approved QueryVault Grafana instance |

## Build, deployment, and testing

| Capability | Status | Integrated implementation | Remaining target |
| --- | --- | --- | --- |
| SSDT model | IMPLEMENTED | Declarative model sources, `master.dacpac` reference, operational/model synchronization tests | Rebuild integrated 29-object model in the verified Voyager1 SSDT environment |
| Production-safe deployer | IMPLEMENTED | Preserves tables/data, deploys repeatable core/reporting modules, checks schema ownership | Validate integrated branch transactionally on Voyager2; do not dispatch yet |
| Repository tests | IMPLEMENTED | Model/source sync plus partition, capture-grain, reporting, and asset checks | Add automated CI on an approved disposable SQL Server/Grafana environment |
| Existing deployments | NEEDS VALIDATION | Deployment avoids inferred table migrations | Inventory legacy constraints/table shape and use reviewed migrations only |

## Release sequence

1. Finish repository/DACPAC and transactional integration tests.
2. Validate the integrated branch against Voyager2 without persistence.
3. Review known legacy periods and deployment table-shape differences.
4. Have a DBA create the `dbo`-owned `qv_report` schema.
5. Merge only after approval, then use the existing backup/preflight production
   workflow.
6. Provision the external-secret-backed Grafana login/user and prove it cannot
   read `dbo.RunMetadata`.
7. Load dashboards into an approved Grafana instance and export one native plan
   to SSMS.

No step requires a custom Grafana datasource, plan renderer, or an unreviewed
internal schema redesign.

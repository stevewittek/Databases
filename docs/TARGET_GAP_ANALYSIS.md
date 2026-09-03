# QueryVault target gap analysis

Audit date: 2026-09-02; validation updated 2026-09-03

Status meanings:

- `IMPLEMENTED`: present and aligned with the approved direction.
- `PARTIAL`: useful implementation exists, but material required behavior is absent.
- `MISSING`: no substantive implementation exists.
- `NEEDS REDESIGN`: the current design conflicts with the approved requirement or correctness contract.
- `NEEDS VALIDATION`: code exists, but fitness, compatibility, performance, or safety has not been demonstrated.

## Approved core requirements

| # | Requirement | Status | Existing implementation | Gap / target action |
| --- | --- | --- | --- | --- |
| 1 | Preserve selected Query Store periods outside normal Query Store retention | `PARTIAL` | Time-window capture copies six Query Store surfaces to `QueryVaultDB`; run metadata records source and range. | Introduce a first-class logical period, deterministic interval membership, idempotency/watermark rules, overlap policy, source identity, and completeness/reconciliation state. |
| 2 | Support Rolling, Baseline, Incident, and Pinned retention classifications | `NEEDS REDESIGN` | `DoNotDelete` plus `RetentionDate` provides only protected vs expirable behavior. | Add explicit constrained retention class and class-specific metadata/policy. Do not infer all preserved runs from one Boolean. Define transitions, audit history, and whether Pinned overrides every automatic policy. |
| 3 | Separate logical archived periods from physical storage partitions | `NEEDS REDESIGN` | `RunMetadata.RunID` is simultaneously capture run, logical period identifier, and partition key. | Model periods independently and map one or more periods/interval ranges to storage partitions. Partition lifecycle must not define period identity. |
| 4 | Use partition-friendly storage for large historical facts | `PARTIAL` | All archive tables are partitioned on `RunID`, including facts and small/immutable metadata. | Choose a scalable physical key (normally time/storage bucket plus source shard as needed), keep aligned fact indexes, and avoid one partition per capture run and unnecessary partitioning of deduplicated dimensions. |
| 5 | Evaluate clustered columnstore for high-volume RuntimeStats and WaitStats | `NEEDS VALIDATION` | Clustered columnstore is already applied to every archive and maintenance table. | Retain CCI as a strong fact-table candidate, but benchmark rowgroup quality, load sizes, compression, segment elimination, reporting patterns, NCI overhead, and partition size. Evaluate facts separately from query text, query metadata, plans, and intervals. |
| 6 | Use partition switching for efficient expiration where appropriate | `PARTIAL` | Mirror tables, aligned indexes, `SwitchOut`, `Truncate`, a purge coordinator, shared-partition rejection, and owned transactions for direct operations exist. | Decouple switching from logical run identity; add concurrency control, migration of legacy constraints, and broader behavioral tests with fact rows. Switch only partitions wholly eligible for expiration. |
| 7 | Evaluate `COLUMNSTORE_ARCHIVE` for cold preserved partitions | `MISSING` | No archival-compression state, policy, command, benchmark, or reporting exists. | Add an explicit evaluation and lifecycle for cold Baseline/Incident/Pinned storage. Microsoft notes that archive compression saves more space at the cost of slower access; measure before enabling. See [ALTER INDEX](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-index-transact-sql). |
| 8 | Preserve native Query Store metadata needed to understand historical performance | `PARTIAL` | Query text, query, plan, interval, runtime, and wait columns are broadly copied. | Add context settings, Query Store configuration snapshot, supported replica metadata, source/version capability metadata, and a version policy. Decide which query hints/variants and newer fields are required. Preserve native values without implying unsupported cross-version columns. |
| 9 | Deduplicate large immutable query text and Showplan XML where beneficial and safe | `MISSING` | Query text and Showplan are repeated once per `RunID`. | Introduce content-addressed or source-stable dimensions with collision-safe hashes plus full-value verification, source identity, restricted/encrypted handling, and period bridge tables. Keep native IDs as source-scoped attributes, not global identities. |
| 10 | Preserve environment/configuration metadata so comparisons remain interpretable | `MISSING` | Source server/database names and plan compatibility/engine fields are the only meaningful context. | Snapshot Query Store options, database compatibility and scoped configurations, engine build/edition, collation, relevant server settings, resource governance/service tier, hardware capacity where available, and application/deployment labels at period capture time. |

## Hard Query Store correctness contract

| Rule | Status | Evidence and gap |
| --- | --- | --- |
| Do not assume one runtime row is one complete interval observation | `NEEDS REDESIGN` | The table key is `(RunID, runtime_stats_id)` and capture copies rows verbatim. A new guard rejects duplicate grains rather than completing the run, but it does not aggregate them. The local archive contains duplicate rows from the older deployed procedure. |
| Aggregate runtime statistics at `(plan_id, execution_type, runtime_stats_interval_id)` | `MISSING` | No source grouping or canonical aggregate exists. A design is needed for sums, execution-weighted averages, extrema, chronological last values, and statistically valid combined dispersion. [`sys.query_store_runtime_stats`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql) defines the grain. |
| Prefer completed intervals | `PARTIAL` | The checked-in procedure filters on interval end and subtracts one flush interval. This is a conservative improvement, but completion is not recorded per observation and source consistency is not proven. |
| Mark active captures `PROVISIONAL` and reconcile after close | `MISSING` | Active intervals are not intentionally supported; no provisional state, natural key/upsert, reconciliation job, or lineage exists. |
| Perform equivalent wait-stat review and aggregation | `NEEDS REDESIGN` | The review confirms a documented grain of `(plan_id, runtime_stats_interval_id, execution_type, wait_category)`. Capture remains row-for-row and now rejects duplicate grains rather than completing the run. [`sys.query_store_wait_stats`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-wait-stats-transact-sql) requires aggregation for actual interval state. |

### Required design decision before runtime/wait implementation

Do not merely apply `GROUP BY` with unweighted `AVG`. Runtime averages must be weighted by `count_executions`; totals and extrema have different algebra; `last_*` values require a defensible chronological source; and combining standard deviations requires the source statistic convention and a pooled-variance formula. Wait averages and dispersion additionally require a defensible execution-count denominator. Until those semantics and tests are approved, a capture-time duplicate rejection guard is safer than silently producing approximate facts.

## Reporting contract

| Required interface | Status | Current nearest object | Gap |
| --- | --- | --- | --- |
| `qv_report` schema and stable consumer boundary | `MISSING` | None | Create the schema, grant consumers access only through it, and version behavioral contracts independently of internal storage. |
| `qv_report.VaultPeriods` | `MISSING` | `dbo.usp_GetArchiveSummary` | Expose logical periods and retention/completeness state, not physical partition internals. |
| `qv_report.WorkloadSummary` | `MISSING` | None | Define totals/rates and units over canonical aggregated facts. |
| `qv_report.TopQueries` | `MISSING` | README ad hoc query | Define ranking metric, period filters, source identity, query identity, and deterministic ties. |
| `qv_report.WaitSummary` | `MISSING` | None | Build only after wait-grain correctness and category/version semantics are settled. |
| `qv_report.QueryPerformance` | `MISSING` | None | Expose interval facts with explicit units and completion state. |
| `qv_report.PlanHistory` | `MISSING` | Direct plan table access | Define source-scoped query/plan identity and plan validity over periods. |
| `qv_report.PeriodComparison` | `MISSING` | None | Define matching rules, normalization, missing-query behavior, and environment differences. |
| `qv_report.QueryDetail` | `MISSING` | Direct multi-table joins | Provide a stable query-centric contract across deduplicated storage. |
| `qv_report.GetPlan` | `MISSING` | `query_store_plan.query_plan` | Return native Showplan XML through a stable procedure/function with clear not-found/restricted behavior. |

Grafana, SSMS, Power BI, and scripts are currently coupled to `dbo` internals. New reporting work should precede disruptive storage changes or arrive in the same versioned migration.

## Supporting engineering gaps

| Area | Status | Gap / target action |
| --- | --- | --- |
| Supported SQL Server versions | `NEEDS REDESIGN` | Claims range from SQL Server 2016 to 2025; project target is SQL 2019; canonical columns require newer capabilities. Establish a minimum version and capability-driven capture projections. |
| Schema migration | `MISSING` | The safe deployer skips existing tables, while old fix scripts drop data. Add additive, versioned, restartable migrations with preconditions and rollback/forward recovery guidance. |
| Capture idempotency | `MISSING` | No unique logical-period/interval rule or watermark; observed runs overlap. |
| Capture concurrency | `MISSING` | Partition extension and source-window ownership are not serialized. |
| Partition safety | `PARTIAL` | Identity-jump growth, shared-partition rejection, and direct-operation atomicity were added. Concurrency, logical/physical decoupling, and legacy deployment migration remain. |
| Source consistency | `NEEDS VALIDATION` | Multiple Query Store views are read in separate statements without a documented consistency strategy. |
| Security | `PARTIAL` | Voyager scripts establish dedicated identities, but generic jobs use `sa`; query text can contain sensitive content and needs access/audit policy. |
| Automated tests | `PARTIAL` | Purge, shared-partition rejection, transactional compilation, SSDT/deployment source synchronization, a zero-warning Visual Studio 2026 SSDT build, repository contracts, and deployment-state checks exist. Add grain aggregation fixtures, provisional reconciliation, retention-class tests, broader switch isolation, migration tests, and reporting-contract tests. |
| CI validation | `PARTIAL` | Production deployment is manually triggered; no pull-request build/test workflow exists. |
| Python | `MISSING` | No Python component exists. None is required merely to meet the product direction; add Python only for a concrete orchestration or test need. |

## Recommended sequence

1. Establish a supported-version/capability policy and a versioned migration mechanism.
2. Define logical period, retention classification, capture lineage, and completed/provisional state independently of physical partitions.
3. Specify and test exact runtime and wait aggregation semantics using fixtures with multiple source rows per documented grain.
4. Introduce `qv_report` contracts over the canonical logical model.
5. Redesign fact partitioning and retention mapping, then validate CCI and partition switching at representative volume.
6. Add deduplicated query-text/plan storage and environment snapshots behind the reporting layer.
7. Benchmark and, if justified, add `COLUMNSTORE_ARCHIVE` for cold preserved partitions.

Do not deploy destructive compatibility scripts or reshape populated tables until migrations, backups, reconciliation, and reporting compatibility are in place.

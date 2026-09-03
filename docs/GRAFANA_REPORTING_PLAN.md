# QueryVault Grafana and Reporting Plan

## Decision

Grafana OSS is the QueryVault V1 reference visualization platform. It uses Grafana's Microsoft SQL Server data source (`type: mssql`); no custom data source or execution-plan renderer is introduced.

The stable integration boundary is the `qv_report` schema. Dashboards do not query `dbo` archive tables. The existing QueryVault storage model remains unchanged.

## Repository inspection

This assessment was made before adding the reporting assets in this change;
the objects listed later in this document are the implemented result.

### Existing reporting objects

No `qv_report` schema, views, or procedures existed. The only reporting-oriented database object was:

- `dbo.usp_GetArchiveSummary`: filters archive runs by source database, run ID, date window, or status and returns run metadata, archived row counts, elapsed archive duration, and partition number.

There was no Grafana directory, datasource configuration, dashboard provisioning, dashboard JSON, container configuration, or Grafana documentation.

### Existing objects that can support dashboards

| Existing object | Dashboard-relevant data |
| --- | --- |
| `dbo.RunMetadata` | Archive/run ID, name, source server/database, archived window, status, retention/protection, archive timestamps, and archived row counts |
| `dbo.DatabaseConfig` | Registered source server/database and archive scheduling/retention settings |
| `dbo.query_store_runtime_stats_interval` | Archived Query Store interval start/end timestamps |
| `dbo.query_store_runtime_stats` | Executions, duration, CPU, logical/physical I/O, writes, memory, DOP, row count, and related aggregates by plan and interval |
| `dbo.query_store_query` | Source-native query ID, query text ID, query hash, object ID, compile metrics, and execution metadata |
| `dbo.query_store_query_text` | SQL text plus encrypted/restricted-text flags |
| `dbo.query_store_plan` | Source-native plan/query IDs, plan hash, plan attributes, and native SQL Server Showplan XML stored in `query_plan` |
| `dbo.query_store_wait_stats` | Native Query Store wait category, category description, and wait aggregates by plan and interval |

The partition-maintenance mirror tables are operational implementation details and are not reporting sources.

### Data currently available

The existing archive contains enough fields to compute:

- available archive periods and source dimensions;
- total and average execution, CPU, duration, and logical-read metrics;
- distinct query and observed-plan counts;
- query text previews, with restricted/encrypted text suppressed;
- wait-category totals and per-query wait contribution;
- query performance across multiple archived periods;
- plan metadata and native Showplan XML retrieval.

Query Store duration and CPU values are stored in microseconds; the reporting contract converts totals and averages to milliseconds. Logical reads remain page counts. Wait values remain milliseconds.

### Missing information and limitations

1. **Period classification is not recorded.** `RunMetadata` has a run name and comments but no authoritative classification such as baseline, release, incident, or business cycle. V1 exposes a nullable `period_classification`; dashboards display `Unclassified (not recorded)`. Do not infer classification from free text.
2. **Cross-period query identity has a lifecycle limitation.** V1 comparisons match the source-native `query_id` within the selected source server/database. Query IDs are useful while Query Store identity remains stable, but can be reassigned after Query Store cleanup/reset. `query_hash_hex` is exposed as supporting evidence, not treated as a collision-free key.
3. **Periods may overlap or differ in duration.** V1 shows absolute workload totals and explicit deltas. Operators must compare equivalent windows when interpreting regressions. A future contract may add normalized per-hour/per-day metrics.
4. **No deployment fixture containing real archived data exists in this repository.** Live acceptance therefore uses Voyager2's persistent archive while repository tests continue to use transactional fixtures.
5. **Some early archived periods predate the completed-interval safeguard.** Nine
   Voyager2 periods contain an interval ending after the period's recorded end.
   Treat those periods as potentially partial; see
   [Query Store correctness](Query-Store-Correctness.md).
6. **Reporting does not reinterpret legacy capture multiplicity.** New captures
   retain every native contributor and materialize canonical runtime/wait
   observations at documented grains. `qv_report` prefers canonical facts for
   those runs and falls back to unchanged legacy facts only when a run has no
   canonical data.

## V1 `qv_report` contract

This change adds the following contract without changing internal tables:

| Object | Grain and purpose |
| --- | --- |
| `qv_report.periods` | One row per archived period, including source, window, status, retention, protection, and archive row counts |
| `qv_report.period_metrics` | One workload rollup per period |
| `qv_report.query_period_metrics` | One workload rollup per period/query |
| `qv_report.wait_period_metrics` | One wait rollup per period/wait category |
| `qv_report.query_wait_period_metrics` | One wait rollup per period/query/wait category |
| `qv_report.query_plans` | Plan inventory and native Showplan XML |
| `qv_report.usp_GetShowplanXml` | Native XML retrieval by period and query or plan |

Column names carry units (`*_ms`) where needed. IDs retain their SQL Server Query Store meanings. This contract should evolve additively; dashboards must not silently bind to `dbo` tables.

### Required future contract for period classification

When QueryVault gains classifications, `qv_report.periods.period_classification` must return the authoritative value while preserving its existing name and nullable `nvarchar(100)` shape. How the classification is stored internally is intentionally outside this integration contract. Recommended controlled values are `Baseline`, `Release`, `Incident`, `Peak`, and `Ad hoc`, but the storage design and vocabulary require a separate QueryVault schema decision.

## Initial dashboard set

### QueryVault Overview

- Variables: source server, source database, archived period.
- Panels: executions, total CPU, total duration, logical reads, query count, plan count, available periods, classifications, and major wait categories.
- Status: working from existing archived data. Classification is explicitly shown as not recorded.

### Period Comparison

- Variables: source server, source database, baseline period, comparison period.
- Panels: percentage KPI deltas, absolute workload changes, top duration regressions, top duration improvements, plan-count changes, and wait-category changes.
- Status: working from existing archived data. Comparisons use source-native `query_id`.

### Wait Analysis

- Variables: source server, source database, archived period, baseline period, wait category.
- Panels: selected wait total, change from baseline, wait distribution, category deltas, and top contributing queries.
- Status: working where archived wait rows exist. An empty wait archive produces empty panels rather than querying live Query Store.

### Query Detail

- Variables: source server, source database, one or more archived periods, query.
- Panels: query text preview, executions, CPU, duration, reads, total waits, observed plan count, performance across periods, wait profile, and plan metadata.
- Status: working from existing archived data. Showplan XML is deliberately retrieved through SQL Server/SSMS, not rendered in Grafana.

## Security and packaging

- Datasource UID: `queryvault-mssql`.
- Dedicated SQL login/user: `queryvault_grafana`.
- Required schema owner: `dbo`, created once by a DBA with
  `QueryVault/Security/ProvisionReportingSchema.sql`.
- Database permissions: `SELECT` on schema `qv_report` and `EXECUTE` only on `qv_report.usp_GetShowplanXml`.
- Password source: `QV_GRAFANA_SQL_PASSWORD` in the Grafana process environment; no password is committed.
- Version-controlled paths:
  - `grafana/provisioning/datasources/`
  - `grafana/provisioning/dashboards/`
  - `grafana/dashboards/`

## Validation and acceptance

Static validation requires:

1. every dashboard file parses as JSON;
2. every provisioning file parses as YAML;
3. dashboard UIDs and panel IDs are unique;
4. every dashboard datasource UID resolves to `queryvault-mssql`;
5. every dashboard SQL statement references only `qv_report`;
6. every required template variable exists on the appropriate dashboard;
7. both SQL project files remain valid XML and include all reporting objects.

Deployment acceptance requires a populated non-production QueryVault database:

1. deploy the database project or ordered deployment script;
2. create the restricted Grafana login/user;
3. verify the login can select every `qv_report` view and cannot select `dbo.RunMetadata`;
4. provision Grafana and test the datasource;
5. load each dashboard with at least two comparable completed periods;
6. reconcile one period's aggregates to the underlying archive as an administrator;
7. retrieve one plan with `qv_report.usp_GetShowplanXml` and open it in SSMS.

## Voyager2 integration status (2026-09-03)

- **PASS:** the DBA-owned `qv_report` schema, six views, and Showplan procedure
  are deployed and compile against persistent QueryVault data.
- **PASS:** period 47 reconciles to 353 executions, 2,199.851 ms CPU,
  2,481.193 ms duration, 127,463 reads, 94 queries, 94 plans, and 187 ms waits.
- **PASS:** the least-privilege `queryvault_grafana` principal can read the
  contract and execute the Showplan procedure but cannot read
  `dbo.RunMetadata`.
- **PASS:** the native MSSQL datasource and all four dashboards are live in a
  dedicated QueryVault Grafana OSS 13.1.0 instance. All 49 variable/panel
  queries pass, and actual dashboard screenshots are committed.
- **PASS:** native Showplan XML was exported as a 40,411-byte `.sqlplan`.
- **NOT TESTED:** graphical opening in SSMS; SSMS was unavailable.

The unrelated `caplab-grafana` service was not changed. See
[Voyager2 RC Validation](VOYAGER2_RC_VALIDATION.md) for the full acceptance
matrix and lab TLS exception.

## Future work

- Add an authoritative period-classification source behind the existing contract column.
- Add normalized rates for unequal period durations.
- Add interval-grain reporting views only when a within-period timeline dashboard is approved.
- Add integration tests against a disposable SQL Server/Grafana environment with seeded archive data.

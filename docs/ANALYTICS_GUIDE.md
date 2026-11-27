# QueryVault analytics expansion

Development candidate, November 22, 2026. Code and static/build evidence are
available. Live deployment, SQL fixture execution, Grafana rendering and real
load-test outcomes have not been verified for this candidate.

## What is built

| Surface | What it answers |
| --- | --- |
| Run Regressions | Which queries became slower, used more CPU or reads, changed plan inventory, appeared, or stopped appearing? |
| Load Test Lab | How did two named variants of one experiment compare? What happened across its archived runs? |
| Interval Investigation | When inside a run did throughput, latency, CPU, reads, memory, tempdb or execution outcomes change? |
| SSMS reports | The same comparison and investigation leads as reusable read-only SQL |
| Power BI starter | A parameterized M function returning quality, run, query and wait tables |

The original four Grafana dashboards remain available. Seven dashboard JSON files
now use the same native MSSQL datasource. New dashboard UIDs are
`qv-run-regressions`, `qv-load-test-lab`, and `qv-interval-investigation`.

## Comparison rules

Select source server/database, a date range, the candidate RunID and an earlier
baseline RunID. Query ID cells link to that query in the candidate interval dashboard. Labels include run date, name and variant. The date range filters
run choices by intersection with recorded archive bounds; the chosen run supplies
its complete captured metrics, not a newly clipped window.

`qv_report.fn_CompareRunQuality(before,after)` always returns one diagnostic row.
A pair is ready only when both runs exist, are distinct, belong to the same exact
source labels, have completed canonical observations, have positive interval
coverage without invalid/overlapping/out-of-window intervals or missing metadata,
and do not overlap each other. Conflicting recorded Query Store epochs block the
pair. Unrecorded epochs remain explicitly unverified. Server/database labels are
not a global source identity; endpoint reuse or restore requires an epoch change.
A deployment label is correlation evidence, not causation.

Query matching starts with source-native query_id and checks hash, context ID,
object ID, initial compile timestamp and SHA-256 of full available text. A
changed or restricted identity is excluded from regression deltas. IDs are not
matched across resets or by query hash alone. Same-epoch labels are operator
assertions, not automatic reset detection. Initial compile changes are treated
conservatively and can produce false negatives after unusual metadata changes.

New and not-observed queries retain NULL on the missing side. They are not
presented as infinite regressions or 100% improvements. A zero baseline average
has no percentage change. Minimum execution filters apply on both sides.

- Average duration/CPU/reads compare execution-weighted per-execution cost.
- Absolute totals also depend on execution frequency and window duration.
- Executions/second and CPU ms/hour divide by the sum of captured Query Store
  interval durations. Gaps are excluded from this denominator; inspect captured
  versus requested seconds and coverage bounds. Rates are not per wall-clock
  requested window and do not remove workload-mix differences.
- Estimated extra duration = (candidate average duration - baseline average
  duration) * candidate executions. This is a counterfactual investigation score,
  not a measured deployment impact or guaranteed recoverable time.
- Plan inventory compares distinct archived plan-hash sets, not counts or plan
  IDs. Historical unused plans can be present. A change does not prove that an
  executed plan changed or caused the regression.
- Query-level wait intensity uses that query's execution count. Category-level
  intensity uses all executions in the run. Missing wait observations stay
  unavailable. SQL Server 2016 has no Query Store waits; no waits is not proof of
  zero waiting on any version.
- Summary comparisons combine captured execution outcomes. The interval report
  separates regular, aborted and exception outcomes; check for a workload/outcome
  mix change before concluding latency regressed.

Legacy runs remain visible in the original reports and quality view but are not
accepted by the new comparison API until reconciled into canonical observations.
There is no fabricated percentile, spill count, server utilization or automatic
index/plan-forcing recommendation.

## Database objects and upgrade

`dbo.RunAnalysisContext` is optional run metadata with controlled classification,
experiment, workload, variant, deployment label, Query Store epoch and notes.
Its RunID foreign key cascades only when run metadata is deleted. It is not
partition-switched. Adding a label does not pin a run; use existing DoNotDelete
protection. Load-test capture recipes pin their runs explicitly.

`qv_report.periods.period_classification` now returns that authoritative nullable
nvarchar(100) label. Existing unlabelled runs remain NULL. Additional views are
`run_quality`, `query_identity`, and `query_interval_metrics`; additional inline
functions are `fn_CompareRunQuality`, `fn_CompareRuns`, `fn_CompareWaits`, and
`fn_CompareQueryWaits`. Both SQL projects contain all 48 model objects.

For an existing non-production archive with the current reporting/canonical
contract, take a backup, select that database explicitly, change directory to
`QueryVault/Scripts`, and run `DeployAnalytics.sql` with SQLCMD mode and abort on
error. It creates the context table if missing and changes reporting objects in
one transaction. It does not change archive facts or schedule jobs. On failure,
close/roll back the connection before retrying. Re-running preserves labels.
Do not apply a fresh-install DACPAC to a populated archive. Full deployment
helpers also include the new objects; production post-checks require them.

A DBA writes run labels using ordinary parameterized INSERT/UPDATE against
RunAnalysisContext. Grafana users retain SELECT on qv_report and cannot edit labels.
The existing schema SELECT grant covers inline TVFs; no broad EXECUTE or dbo
SELECT grant is added. Verify that ownership chains and least privilege hold on
the actual server. `query_identity` exposes text digests, not hidden query text.

## Grafana launch

`grafana/compose.analytics.yaml` provisions all seven dashboards into a separate
lab instance on loopback port 3031, with a 512 MB memory limit and one CPU. It
requires a tested Grafana image tag/digest and secret environment variables.
Use a trusted certificate for the SQL host reachable from the container.
`localhost` inside the container is not the host SQL Server. Review
`grafana/provisioning/datasources/queryvault-mssql.yaml` for required `QV_*`
variables. `QV_GRAFANA_ADMIN_PASSWORD` and `QV_GRAFANA_SQL_PASSWORD` are distinct.
Do not commit an environment file or connection secrets.

```sh
docker compose -f grafana/compose.analytics.yaml config --quiet
docker compose -f grafana/compose.analytics.yaml up -d
```

SQL analytics must be deployed first. Existing installations can provision just
the three new JSON files after testing against a separate datasource. Do not
replace Voyager2's current service or datasource during lab validation. The
original dashboards still label classification as unavailable in some help text;
use the new dashboards for the new metadata workflow.

## Controlled load experiment

1. Use a dedicated SQL lab instance or available non-production capacity.
   `workload/SetupLoadLab.sql` creates QueryVaultLoadLab and 50,000 synthetic rows.
   It refuses an existing database and enables Query Store only in that new lab.
2. Generate one UUID for this Query Store lifetime. Retain it for both variants.
   Capture `SELECT SYSUTCDATETIME()` from the server immediately before/after
   each test. Keep clocks synchronized and runs separate.
3. Run baseline, then regressed variant with identical duration, workers, pause,
   seed, dataset, host and server settings. Record warmup and cache state. Do not
   clear global caches or change instance settings to make the difference larger.

```sh
python3 workload/run_load.py --server LAB_HOST --experiment predicate-lab-01 \
  --epoch YOUR_UUID --variant baseline --duration-seconds 180 --workers 2 \
  --output artifacts/load/baseline.json
python3 workload/run_load.py --server LAB_HOST --experiment predicate-lab-01 \
  --epoch YOUR_UUID --variant regressed --duration-seconds 180 --workers 2 \
  --output artifacts/load/regressed.json
```

Install pyodbc and ODBC Driver 18 where needed. Integrated authentication is the
default; SQL authentication reads a named password environment variable. TLS
verification is required. The runner checks the database name and lab marker,
allows at most eight workers/900 seconds/15 seconds query timeout, caps requests
per worker, and stops on the first SQL error. Each worker has its own connection.
An in-flight query/connect may finish after the duration deadline within its
configured timeout. Client success counts and latency include boundary intervals
that the archive recipe excludes, so do not expect exact client/archive equality.

Both variants return equivalent sums for the same nonnegative Bucket data.
The default `predicate` scenario introduces a non-sargable predicate in the regressed variant.
The additional `--scenario sort` uses equivalent ordered output and a sort expression;
use a separate experiment name for it and keep the scenario identical across each pair. The size of any performance
change depends on the actual optimizer, plan and hardware; verify the result
rather than promising a regression. The bounded runner is a closed-loop client:
a faster query can execute more often, making per-execution comparisons essential.
Repeat at least three pairs and report variability before making performance claims.

4. Wait until full contained one-minute intervals are closed and older than the
   source flush grace. Configure the source using the existing initialization
   procedure if required. Run `workload/ArchiveLoadRun.sql` in the lab archive with
   measured server UTC boundaries, experiment, variant and epoch. Set the matching scenario as well. It rejects
   duplicate overlapping captures made through this recipe and returns the RunID.
   It is a same-instance recipe, not Azure SQL Database cross-database ingestion.
5. Select those two RunIDs in Load Test Lab and compare readiness, per-execution
   latency/CPU/reads, execution rates, wait intensity and plan evidence. Retain
   client JSON receipts separately. No automatic ingestion of client percentiles
   into SQL is implemented. Do not manually insert duplicate snapshots to make a
   timeline look longer.

## Other reporting tools

Run `reports/sql/CompareRuns.sql` in SSMS after setting explicit IDs. It returns
quality, selected runs, regressions, improvements, membership and wait changes.
`reports/sql/QueryFindings.sql` identifies workload concentration, plan
multiplicity, non-success outcomes and major query waits for investigation.

In Power BI Desktop, create a blank query, paste `reports/powerbi/RunComparison.pq`,
and invoke it with server, archive database and two RunIDs. Create referenced
queries for its Quality, Runs, Queries and Waits fields. Authenticate in Power BI.
Do not sum baseline averages or join waits to query metrics before grouping;
use query_id and the selected pair as the relationship grain. This is an M
starter, not a tested PBIX/PBIT or SSRS report. Grafana and SQL are the current
implemented reporting surfaces.

See [the work plan](ANALYTICS_ROADMAP.md), [research](ANALYTICS_RESEARCH.md),
and [validation evidence](ANALYTICS_VALIDATION.md).

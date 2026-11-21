# QueryVault functional and load test review

Prepared November 21, 2026. This is a plan for review, not a record of new test execution. Start with the [user walkthrough](START_HERE.md). Test execution and results remain tracked in [12](https://github.com/stevewittek/Databases/issues/12), with existing correctness, retention, remote transport and platform tickets below.

The goal is to establish that QueryVault saves the right history, preserves protected periods and has an acceptable collection cost. Test the workload being observed separately from the cost of collecting its Query Store history.

## Test location and starting conditions

- Use an isolated synthetic source and a fresh QueryVault lab archive. No workload generation, purge, Query Store clearing, configuration change or capture of real query text on MotionRelay is included in this plan's initial execution.
- Select a host with verified storage health and sufficient capacity. Voyager 1's historical disk errors and old archive layout need resolution; Voyager 2 authentication and recovery evidence remain outstanding. Neither is automatically selected for load testing.
- Record the commit, engine/version, provider, authentication mode, hardware, data size, Query Store settings and test window in UTC. Keep credentials and private source data out of evidence files.
- Start with jobs and automatic purge disabled. Use one test controller; do not run the existing mutation suites against the same archive concurrently.
- Create a clean baseline and restore it between comparisons. Do not clear shared server caches or change production settings to obtain repeatability.

## Functional acceptance sequence

| Stage | Exercise | Evidence required to pass |
| --- | --- | --- |
| 1 Installation | Fresh empty database; repeat deployment against populated archive | Fresh schema succeeds; unsafe fresh-install redeployment is rejected without changing retained data |
| 2 Registration | Explicit source, wrong database/port, disabled source, restricted reporting account | Correct target only; failures are clear; disabled sources do not collect; reporting cannot retrieve credentials |
| 3 First period | Known synthetic workload and closed Query Store intervals | Completed run with correct source and actual coverage; executions, weighted duration/CPU, reads and waits reconcile with the source snapshot |
| 4 Useful reports | Capture two equivalent workloads with one controlled change | SQL reporting and Grafana agree; plan/text values are complete; missing measurements stay missing rather than becoming zero |
| 5 Retention | Lab fixtures just before/at/after expiry, plus a protected period with a note | Preview lists only eligible completed unpinned runs; lab purge removes those runs and preserves pinned facts, notes and report visibility |
| 6 Races and interruption | Pin during maintenance; interrupt capture/purge; rerun | No protected data lost; failed/partial work reported; retries of the future remote path do not duplicate committed facts or advance the checkpoint prematurely |
| 7 Remote collection | Independent second SQL instance, then separately approved Azure source | Correct endpoint/TLS/identity; exact reconciliation; complete Unicode text/large plans; bounded failures; one failed source does not prevent other sources progressing |
| 8 Recovery | Restore archive and required credential recovery material into isolation | Saved periods, notes, source identities and reports survive; connection recovery works without publishing secrets |

Use actual native contributors when reconciling metrics. Counts of raw rows alone cannot prove correctness, and averaging averages is insufficient. Multiple runtime-stat rows can represent one plan/interval/execution-type group. [Microsoft runtime-stat documentation](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql).

For a short local test, use the existing synthetic source's one-minute intervals and wait for completed intervals plus flush allowance. Do not change MotionRelay's 60-minute interval just to accelerate a demonstration. A configured flush delay alone does not prove stable or complete coverage.

## Load experiment

The following levels and limits are proposed lab settings, not product defaults or a claimed capacity.

1. **Small smoke test:** one source, a fixed set of parameterized queries, one workload worker, one completed capture window. Establish correctness first.
2. **Typical workload:** repeat an identical seeded mix at 1, 4 and 8 workers. Include reads, small writes and joins against synthetic tables. Warm up for five minutes, measure for fifteen minutes, and repeat each comparison three times.
3. **Large history:** hold workload concurrency constant and increase archived interval count, distinct queries/plans and text/plan size. Include ad hoc queries so metadata growth is measured independently of transaction volume.
4. **Multiple sources:** use 1, 3 and 5 separate synthetic databases with the same per-source workload. Compare sequential capture with only the bounded parallelism the implemented collector actually supports. Do not assume a configuration field already enforces a limit.
5. **Failure and recovery:** inject a lab-only disconnect, timeout, source outage and process interruption. Verify recovery before increasing scale.
6. **Retention and reporting together:** run reports during lab purge and capture, with a pinned baseline retained. Measure blocking, report latency and cleanup duration.

For every workload level, compare **A: Query Store enabled, QueryVault idle** against **B: the same workload and Query Store settings, QueryVault collecting**. Alternate A/B order across repetitions, hold data/indexes and cache warm-up consistent, and record natural run-to-run variation. One combined run cannot isolate collector overhead.

Use a separate quiet capture/reconciliation run for deterministic totals. Under concurrent workload, record precisely which closed intervals were compared and any source changes; do not claim exact agreement from two unrelated snapshots.

## Measurements and proposed acceptance limits

| Measure | Record or proposed target |
| --- | --- |
| Workload impact | Throughput, errors and client-measured p50/p95 latency. Proposed target: no more than 5% throughput loss or 10% p95 latency increase versus A, interpreted alongside repeatability |
| Source cost | CPU percentage points, logical reads, collection duration and blocking; proposed target: no more than 5 additional average CPU percentage points |
| Transfer and ingestion | Rows and bytes read/transferred/committed, wall time, peak memory, archive log growth and checkpoint lag |
| Reporting | Repeat representative queries during idle and active collection; report p50/p95 and sample count, not a percentile from three captures |
| Storage | Actual table/index bytes, raw contributors, canonical facts, text/plan bytes, retained partitions and protected-period space |
| Correctness | Zero unexplained missing or duplicated contributions; zero lost protected data; large text/plan values remain intact |
| Cleanup | Exact preview versus purge result, elapsed time, lock waits, remaining partitions and report reconciliation |

Calculate relative impact as `(B - A) / A × 100`; use CPU percentage points separately. Do not derive request p95 from Query Store average durations. Instrument the workload client for that measurement.

Before load starts, agree the maximum duration, concurrency and disk/log allowance for the selected host. Suggested initial stop conditions are CPU above 85% for two minutes, any deadlock caused by collection, more than 30 seconds of collector blocking, or free disk below the greater of 10 GB and 20%. These are proposed controls for the test controller; the product does not currently enforce them. Any wrong-target connection, unexplained data mismatch or lost pin stops testing immediately.

Estimate storage from measured retained data per source/day, then add separately measured text/plan overhead, pinned history, staging/log headroom and backups. Compare rowstore and columnstore on equivalent clean fixtures. Do not assume columnstore or future deduplication saves a particular percentage before measurement.

## What can run now and what must wait

The repository already contains local capture, aggregation, reporting, retention and two-session pin tests. The small source fixture is a smoke test, not a load generator. Bob Ward's [sqlsimtools](https://github.com/microsoft/sqlsimtools) is now being evaluated under ticket 12 as the workload generator. Prefer evaluating that existing tool before creating another runner. QueryVault-specific fixtures, resource sampling, collection coordination and correctness checks still need integration; tool availability alone does not complete this plan.

Developer commands, from the repository root, without a database connection:

```sh
python3 -m unittest discover -s tests -v
pwsh -NoProfile -File QueryVault/Tests/TestRepositoryContracts.ps1
pwsh -NoProfile -File QueryVault/Tests/TestQueryStoreReadiness.ps1
```

For a prepared disposable Docker lab only, follow [the harness setup](PORTABLE_BUILD.md#disposable-sql-regression-harness), then run the existing suite and pin tests sequentially. The harness writes to its lab databases; it is not a general remote-server test command.

Remote retry, registry-driven scheduling and load-budget enforcement must wait for implementation in [57](https://github.com/stevewittek/Databases/issues/57), [39](https://github.com/stevewittek/Databases/issues/39) and [11](https://github.com/stevewittek/Databases/issues/11). Credential choice is [49](https://github.com/stevewittek/Databases/issues/49). Multi-source partition scale is [37](https://github.com/stevewittek/Databases/issues/37); retention acceptance is [50](https://github.com/stevewittek/Databases/issues/50). Azure capture acceptance is [38](https://github.com/stevewittek/Databases/issues/38). Existing archive migration is [55](https://github.com/stevewittek/Databases/issues/55).

For each test, report: commit and environment, scenario and fixed seed, timestamps and sample counts, expected versus actual result, measured overhead, evidence location, and **passed / failed / not run / blocked**. Mark the ticket complete only when its implementation and required execution evidence both exist.

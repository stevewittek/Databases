# QueryVault analytics work plan

November 22, 2026. This plan covers the new analytics expansion. It does not
replace issue #27, the repository release sequence, or any ROADMAP.md available
in the full Databases repository. This workspace did not contain that roadmap.
No GitHub issues, board items or releases were created during this work.

## First working increment

| Deliverable | State | Acceptance |
| --- | --- | --- |
| Run readiness and guarded comparisons | Implemented, model compiled | Execute deterministic SQL fixture and reconcile real retained runs |
| Run Regressions dashboard | JSON and SQL validated | Render against two real canonical runs; verify controls and totals |
| Load Test Lab dashboard | JSON and SQL validated | Capture baseline/regressed variants and independently reconcile |
| Interval Investigation dashboard | JSON and SQL validated | Plot canonical intervals, outcomes and units without duplicate run snapshots |
| Run experiment metadata | Implemented, additive upgrade | Verify upgrade rerun, label persistence, permissions and purge cascade |
| Bounded lab runner | Offline behavior tests pass | Verify TLS, cancellation, caps and lab-only execution on actual SQL |
| SQL reports | Written, syntax checked | Execute with explicit IDs and compare to dashboard values |
| Power BI M starter | Written | Open and authenticate in Desktop, verify type/relationship behavior |
| Grafana lab Compose | Written | Validate config, start separately and capture screenshots |

## Parallel machine assignments

Steve can give each machine its matching prompt in `docs/work-orders`. Work in
separate branches or worktrees. Use the same transferred source snapshot first.
Do not run simultaneous experiments against the same lab database. Keep the
Mac workspace focused on integration and review.

| Owner | Assigned scope | Expected evidence |
| --- | --- | --- |
| Voyager 1, Windows SQL lab | Dedicated source/archive lab, regression fixtures, three paired load experiments, client receipts, comparison reconciliation, optional Power BI Desktop validation | Engine build, scripts/commands, run IDs, raw client metrics, SQL totals and findings |
| Voyager 2, Linux SQL lab | Separate archive lab, SQL 2025/Linux checks, dedicated Grafana lab, all variable/panel execution, TLS and restricted-user verification | Screenshots, datasource checks, query count, SQL/JSON errors, measured reporting query performance |
| Integration workspace | Review both patches, consolidate release evidence, preserve existing collector/capture work, prepare reviewed additive upgrade | Reproducible checks, open issues, final change list and deployment plan |

## Work order

1. Transfer the snapshot, compare checksums and establish exact source state.
   The snapshot includes pre-existing compatibility work plus this analytics work.
2. Build and run static checks. Run the deterministic comparison fixture in a
   disposable archive before generating workload. Fix correctness failures first.
3. Create the bounded synthetic source. Generate baseline/regressed pairs using
   one Query Store lifetime, controlled workload settings and separated intervals.
4. Archive completed interior intervals, label runs, verify readiness and totals.
5. Provision Grafana separately. Verify every variable/panel, screenshots and
   access through the reporting user. Measure cold and warm reporting latency.
6. Run read-only review against existing archive metadata to identify legacy
   quality problems. Do not migrate or delete historical facts as a side effect.
7. Integrate test evidence and review upgrades before any existing service rollout.

Work until the machine's acceptance criteria are satisfied or an actual blocker
is evidenced. Do not spend credits on repetitive tests after passing evidence or
invent performance improvements. Report unavailable infrastructure precisely.

## Next increments after lab acceptance

| Priority | Work | Why it follows |
| --- | --- | --- |
| P0 | Live SQL fixtures and seven-dashboard acceptance | Static compilation cannot prove runtime correctness or layout |
| P0 | Automatic source epoch/reset evidence and context-settings capture | Operator labels and context IDs cannot prove continuity |
| P0 | Query Store capability/options snapshots | No wait rows must be distinguished from unsupported/disabled capture |
| P1 | Plan-grain execution comparisons and executed-plan-set evidence | Archived plan inventory alone can include unused plans |
| P1 | Fixed-arrival-rate workloads, controlled blocking/sort/memory scenarios | Current runner is closed-loop and models bounded predicate and sort-expression scenarios |
| P1 | Client receipt ingestion and experiment/run linkage | Client percentiles are currently separate JSON evidence |
| P1 | Stable source identity and remote collector ingestion | Existing exporter does not ingest into a destination yet |
| P1 | Reporting performance at large run/query counts | Inline aggregation is correct-by-contract but not benchmarked at scale |
| P2 | Reviewed reporting indexes or precomputed summary facts | Use measured bottlenecks before adding storage/write costs |
| P2 | Power BI model, measures and actual PBIX/PBIT | M starter needs Desktop validation and a defined semantic model |
| P2 | SSRS deployment-quality RDL with parameters and export layouts | Build if printable reporting is a real consumer requirement |
| P2 | Deployment annotations from CI/CD and comparable-window suggestions | Requires trusted deployment and source-lifetime metadata first |
| P2 | Regression gates for CI using agreed materiality/sample rules | Deterministic threshold filtering is not statistical significance |

## Return format from both machines

Return the branch/commit or patch; engine and dependency versions; exact target
instance/database/service names; checks executed and outcomes; generated run IDs;
measured deltas with units and denominators; evidence paths; limitations; and
remaining work. Clearly distinguish compiled, executed, rendered and measured.
Never commit credentials, private query text, backups or live connection details.

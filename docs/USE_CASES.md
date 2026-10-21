# QueryVault: preserving the before-and-after evidence

## The problem

SQL Server Query Store is excellent for investigating execution plans, runtime statistics, and waits on a database. But a source database is not always a durable home for performance evidence. Older Query Store periods can age out under retention and size limits, and planned database refreshes, replacements, or Query Store cleanup can remove the very baseline needed for a later comparison.

This matters most during long-running engineering work. If a team begins a quarter of indexing, query refactoring, or technical-debt reduction in July, it needs more than the current week's numbers to assess whether the October workload is actually healthier.

The original need behind QueryVault also included **load and benchmark testing**. We wanted to preserve the evidence from a particular test window before the database was refreshed or replaced, then compare it against a later run without depending on the source Query Store surviving.

## The engineering approach

1. **Capture a known interval.** QueryVault reads completed Query Store intervals from a local source database. Operators can request explicit UTC start/end times or a relative duration; collection is bounded by Query Store flush behavior.
2. **Keep the evidence separately.** It stores query text, query identity, plan metadata, runtime intervals, runtime contributions, and wait contributions in a separate archive database, retaining run-level provenance.
3. **Mark and protect the baseline.** Each captured period gets a RunID and run metadata. Important baselines can be protected from ordinary retention cleanup with `DoNotDelete`.
4. **Measure the later workload.** Capture another comparable window after a release, tuning project, migration, or load-test iteration.
5. **Compare intentionally.** The `qv_report` reporting contract and Grafana dashboards offer archived period views, query-level changes, wait analysis, and period comparisons. Compare equivalent workloads and intervals; a change in traffic volume, query mix, or seasonality can otherwise mislead.

The archive supports longer-lived analysis, not automatic proof that a specific engineering change caused an improvement.

## Example: a quarterly technical-debt initiative

| Milestone | Example period | What to preserve |
| --- | --- | --- |
| Baseline | July 1 | Capture a representative workload before application and index changes |
| Investigation | July through September | Preserve selected load-test or production-like windows, keeping notable regression plans |
| After changes | October 1 | Capture an equivalent workload and duration after the engineering work |
| Review | October | Compare query runtime distributions, execution counts, plans, logical reads, CPU, and Query Store wait categories |

These **July 1 and October 1 dates are an illustrative use case, not a claim that this exact production assessment has been performed**. The usefulness comes from preserving comparable evidence over the calendar gap rather than assuming both periods remain in the source database.

### Practical questions the archive can help answer

- Did total CPU or logical reads change for the same high-volume query family?
- Did a plan regression disappear, or did a different plan introduce a new wait pattern?
- Did work shift to a smaller number of expensive queries?
- Did a load test after a database refresh behave differently from the same test before the refresh?
- Are gains attributable to the tuned workload, or are we comparing different execution counts and query mixes?

## What is preserved, and what is different?

QueryVault uses **SQL Server Query Store data as its source**, so the underlying query, plan, interval, runtime, and wait concepts remain familiar. It is **not an exact live clone of the source system tables**. It retains native contributors and presents validated canonical aggregates and a stable reporting interface, along with separate archive run metadata, partition lifecycle, retention controls, and Grafana views.

The current implementation is an archive and analysis system, not an execution-plan renderer, Query Store replacement, or live workload monitor. A source period must be captured **before** it is deleted or overwritten. QueryVault cannot recover Query Store evidence that has already disappeared.

## Architecture and proof

- [Source and installation](../QueryVault/README.md)
- [Actual Grafana screenshots](SCREENSHOT_PLAN.md)
- [Reporting contract and SQL objects](GRAFANA_REPORTING_PLAN.md)
- [Technical architecture](Architecture.md)
- [Validated release-candidate results](VALIDATION_REPORT.md)

The September 2026 validation exercised bounded sample workloads, archive preservation, partition lifecycle, report contracts, and Grafana queries in a controlled SQL Server lab. It should not be interpreted as production certification across all SQL Server versions and configurations.

*Project created and maintained by Steve Wittek, Netherwood Data Partners.*

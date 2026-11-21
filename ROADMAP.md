# QueryVault | Netherwood DBA Toolkit - Engineering Roadmap

> Last planned: 2026-11-20. This file describes proposed work, not completed implementation or deployment.  
> [Master release tracker #27](https://github.com/stevewittek/Databases/issues/27) | [All open QueryVault tickets](https://github.com/stevewittek/Databases/issues?q=is%3Aopen)

## Product focus

Deliver a dependable, locally installable, shareable SQL Server Query Store performance toolkit. First release priority: **read-only regression detection, evidence-backed plan comparison, and a working Grafana dashboard**. Do not begin with AI, automatic plan forcing, a hosted SaaS platform, or public outreach.

QueryVault V1 already has same-instance Query Store capture, canonical contributor aggregation, columnstore archive, RunID-based protected retention, a stable `qv_report` interface, SQL Agent scheduling, and four Grafana dashboards. Those capabilities must remain compatible.

## R0 - Reliable lab and deploy safety (target November 23 to December 4, 2026)

**Exit gate:** A trustworthy development host, independently restorable archive, and no unapproved automated deploys to Voyager2.

1. [#28: Gate Voyager2 automatic production deployment](https://github.com/stevewittek/Databases/issues/28) **BLOCKER**. Current `.github/workflows/queryvault-prod.yml` deploys `master` pushes changing `QueryVault/**` to Voyager2. User reports intermittent USB database storage failure. Do not merge QueryVault code before resolving this gate.
2. [#29: Inventory Voyager1 suitability](https://github.com/stevewittek/Databases/issues/29) **BLOCKER**. Verify stable internal disk, disk health, OS support status, SQL Server edition, RAM, storage, backup, remote connectivity. Windows 10 support/ESU status requires checking.
3. [#30: Independent off-host backup and verified isolated restore](https://github.com/stevewittek/Databases/issues/30) **BLOCKER**. Do not rely on backups located on the same untrusted USB volume. Reconcile RunIDs and Query Store facts before using inherited historical baselines.
4. [#13: Existing capture consistency and legacy data risks](https://github.com/stevewittek/Databases/issues/13) **RISK**. Exclude ambiguous/unverified archived periods from trusted regression results; preserve original data.

## R1 - Regression Preview (target December 7, 2026 to January 8, 2027)

**Exit gate:** A fresh lab install can create/collect two completed comparable query histories, detect a known regressed plan, correctly reject a traffic-only false positive, show evidence and safe suggested investigation in Grafana.

1. [#31: Add query-plan-interval report contract](https://github.com/stevewittek/Databases/issues/31). New additive `qv_report` interface at query + plan + Query Store interval grain. Preserve weighted CPU/duration/reads, execution counts, provenance, no double counting.
2. [#32: Deterministic regression scoring and read-only recommendations](https://github.com/stevewittek/Databases/issues/32). Rank by normalized per-execution deterioration and total workload impact. Distinguish different plan, unchanged plan, and higher execution volume. No automatic tuning.
3. [#34: Synthetic workload and acceptance tests](https://github.com/stevewittek/Databases/issues/34). Work alongside #31/#32, including plan regression, sample-size safeguards, overlap and legacy-reliability checks, and existing V1 tests.
4. [#33: Fifth Grafana dashboard](https://github.com/stevewittek/Databases/issues/33). Baseline/current plan trends, impact-ranked results, native Showplan export, explanatory suggestions and query detail links.
5. [#36: Scheduled evaluation and freshness](https://github.com/stevewittek/Databases/issues/36). Prefer daily/normal archive cadence initially. No every-15-minute RunID-per-partition polling before #37.
6. [#35: Shareable install/demo and release checklist](https://github.com/stevewittek/Databases/issues/35). Reproducible demo, version support statements, installation/rollback instructions, screenshots, license decision.
7. Parents: [#15 deterministic regression epic](https://github.com/stevewittek/Databases/issues/15), [#22 toolkit packaging](https://github.com/stevewittek/Databases/issues/22).

## R2 - Scalable remote collection and Azure SQL (target January 11 to February 12, 2027; depends on R1)

**Exit gate:** Two independent sources (local SQL Server and Azure SQL Database), safe read-only capture, persistent checkpoints, explicit source version support, visible health and safe scalable retention.

1. [#37: Partition scaling redesign](https://github.com/stevewittek/Databases/issues/37) **BLOCKER**. V1 has one physical partition per retained RunID with ~14,990 operational partition ceiling. At 15-minute capture, even one source creates ~35,040 runs/year if all retained. Separate logical capture ID from physical storage partitioning.
2. [#38: Voyager1-to-Azure SQL read-only POC](https://github.com/stevewittek/Databases/issues/38). Prefer a separate test DB. Existing Motion Relay Azure SQL production is strictly a possible read-only source, never synthetic load generation or source tuning without authorization.
3. [#39: Multi-source collector, durable checkpoints and idempotent ingest](https://github.com/stevewittek/Databases/issues/39).
4. Architectural epics: [#7 architecture](https://github.com/stevewittek/Databases/issues/7), [#8 capability matrix](https://github.com/stevewittek/Databases/issues/8), [#9 source/query identity](https://github.com/stevewittek/Databases/issues/9), [#10 remote collection](https://github.com/stevewittek/Databases/issues/10), [#11 interval reconciliation](https://github.com/stevewittek/Databases/issues/11), [#12 bulk ingest benchmarks](https://github.com/stevewittek/Databases/issues/12), [#14 retention/compression](https://github.com/stevewittek/Databases/issues/14).

## R3 - Advanced advisory / optional AI (after R2)

[#16 Deployment baselines](https://github.com/stevewittek/Databases/issues/16) · [#17 Azure Monitor correlation](https://github.com/stevewittek/Databases/issues/17) · [#18 IQP/configuration history](https://github.com/stevewittek/Databases/issues/18) · [#19 Index analysis](https://github.com/stevewittek/Databases/issues/19) · [#20 Human-approved plan forcing and Query Store hints](https://github.com/stevewittek/Databases/issues/20) · [#21 Web UI/API](https://github.com/stevewittek/Databases/issues/21) · [#23 Evidence-grounded AI](https://github.com/stevewittek/Databases/issues/23) · [#24 Fleet drift](https://github.com/stevewittek/Databases/issues/24) · [#25 Pre-deployment gates](https://github.com/stevewittek/Databases/issues/25).

[#26 Optional public demo](https://github.com/stevewittek/Databases/issues/26) is in **Icebox**. No outreach, polls or posting is planned as part of development.

## Known engineering blockers

- Current production deployment workflow targets Voyager2; storage is reported unreliable.
- Current archive is optimized for selected completed snapshots, not 15-minute collection from hundreds of sources.
- Current `qv_report.query_period_metrics` is by period + query, not plan + interval.
- V1 three-part catalog queries assume same SQL Server instance; Azure SQL Database requires its own connection/adapter and has no SQL Server Agent.
- SQL Server 2016 lacks Query Store wait statistics; version support must be validated rather than presumed.
- Native `query_id` and `plan_id` are scoped to the source Query Store lifecycle, not global identities.
- Archived Showplan XML alone does not mean an old plan can still be forced in the live source.
- Query Store interval aggregation does not prove exact p95 or instant per-execution alerts.
- Existing public repository has no selected open-source license; choose one before promoting the toolkit as reusable open source.

## Board setup (GitHub Projects, separate from Issues)

Suggested personal GitHub Project: **QueryVault | Netherwood DBA Toolkit**.

- Status: Backlog, Ready, In Progress, Blocked, Validation, Done.
- Release field: R0, R1, R2, R3, Icebox.
- Views: Current Sprint, Release Roadmap, Blockers, All Tickets.
- Import open issues from `stevewittek/Databases`; issue #27 is the master tracker.
- Link the GitHub Project to the repository's Projects tab and set the repository as its default.
- **Note:** A repository roadmap file and issues do not automatically create a GitHub Projects board.

## Definition of done

A finished implementation ticket requires an appropriate code review; version-specific and automated test evidence; no silent query aggregation changes; V1 dashboard and archive compatibility; least-privilege security; backup/rollback and migration guidance when applicable; documented scope and limitations. No AI-generated advice may be presented as verified causation, and no source index/plan/hint write is permitted in R1.

Never deploy test changes to Voyager2 or manipulate Motion Relay production data without separate explicit approval.


## Sprint execution calendar

These are issue-based sprint records and GitHub labels. They are **not** a GitHub Projects v2 board. Each record links the canonical implementation tickets and their acceptance criteria.

| Sprint | Dates (proposed) | Focus | GitHub issue |
| --- | --- | --- | --- |
| Sprint 0 | Nov 23 to Dec 4, 2026 | Deployment safety, Voyager1 host, recoverable archive | [#40](https://github.com/stevewittek/Databases/issues/40) |
| Sprint 1 | Dec 7 to Dec 18, 2026 | Plan-level metrics, deterministic regression detection, tests | [#41](https://github.com/stevewittek/Databases/issues/41) |
| Sprint 2 | Dec 21, 2026 to Jan 8, 2027 | Fifth Grafana dashboard, scheduled analysis, demo release | [#42](https://github.com/stevewittek/Databases/issues/42) |
| Sprint 3 | Jan 11 to Jan 22, 2027 | Scalable storage architecture, query identity and adapter design | [#43](https://github.com/stevewittek/Databases/issues/43) |
| Sprint 4 | Jan 25 to Feb 5, 2027 | Azure SQL read-only POC and collector | [#44](https://github.com/stevewittek/Databases/issues/44) |
| Sprint 5 | Feb 8 to Feb 19, 2027 | Cross-source integration/QA and R2 preview | [#45](https://github.com/stevewittek/Databases/issues/45) |

### Filter the backlog by label
- [Sprint 0](https://github.com/stevewittek/Databases/issues?q=is%3Aissue+is%3Aopen+label%3Asprint%3A0)
- [Sprint 1](https://github.com/stevewittek/Databases/issues?q=is%3Aissue+is%3Aopen+label%3Asprint%3A1)
- [Sprint 2](https://github.com/stevewittek/Databases/issues?q=is%3Aissue+is%3Aopen+label%3Asprint%3A2)
- [Sprint 3](https://github.com/stevewittek/Databases/issues?q=is%3Aissue+is%3Aopen+label%3Asprint%3A3)
- [Sprint 4](https://github.com/stevewittek/Databases/issues?q=is%3Aissue+is%3Aopen+label%3Asprint%3A4)
- [Blockers](https://github.com/stevewittek/Databases/issues?q=is%3Aissue+is%3Aopen+label%3Atype%3Ablocker)
- [Ready to work](https://github.com/stevewittek/Databases/issues?q=is%3Aissue+is%3Aopen+label%3Astatus%3Aready)

### Active safety status
On Nov 20, 2026, commit [c656d388](https://github.com/stevewittek/Databases/commit/c656d388a9f6fc9d8071486b9ef0ec07429e6861) removed the automatic push trigger from `.github/workflows/queryvault-prod.yml`. Manual deployment remains possible. This does not verify backup integrity or authorize a manual Voyager2 deployment. See #28.

# QueryVault lab kickoff

Start on Voyager 1. The first milestone is one repeatable demonstration using
synthetic data: generate a workload, archive it, compare two verified runs, then
follow the evidence into the relevant query, interval, waits and plan. Use the
same candidate for Voyager 2 and Azure readiness, but validate each separately.

## What is prepared

| Area | Evidence and boundary |
| --- | --- |
| Historical Voyager 2 lab | Four original Grafana dashboards have real screenshots and September 2026 acceptance evidence. See `docs/SCREENSHOT_PLAN.md` and `docs/VOYAGER2_RC_VALIDATION.md`. |
| November compatibility candidate | Fresh installs, native Query Store collection and canonical data checks ran in a disposable SQL Server 2022 container. See `docs/LOCAL_VALIDATION_2026_11_20.md`. |
| November analytics candidate | Seven total Grafana dashboards, comparison SQL, a synthetic load kit, and a Power BI Power Query starter. The three new dashboards passed static checks, not a live rendering test. There is no validated PBIX or finished video. See `docs/ANALYTICS_VALIDATION.md`. |
| Azure SQL Database | A compiled rowstore archive model and an experimental per-source exporter that stops at a local file. There is no integrated Azure capture-to-Grafana path yet. |

## 1. Voyager 1: prove capture and comparison

1. Copy `QueryVault-Analytics-Source.zip` to Voyager 1. Compare its SHA-256 with
   the one sent with the bundle, then extract into a new directory. Windows:
   `Get-FileHash .\QueryVault-Analytics-Source.zip -Algorithm SHA256`.
   Do not substitute an older Git checkout for this working-tree snapshot.
2. Open the extracted folder in Codex and use `VOYAGER1_ANALYTICS_PROMPT.md`.
   Check the actual SQL build, available capacity, ODBC Driver 18, trusted TLS
   and `sqlcmd`. Run repository tests, build for the installed engine, and run
   the SQL fixtures in a dedicated archive lab before measuring anything.
3. Use `workload/SetupLoadLab.sql` for the synthetic source and `workload/run_load.py`
   for a short connectivity smoke test. Use an actual certificate hostname, not
   a TLS bypass. Then run a predicate baseline and candidate at two workers,
   180 seconds, 20 ms pause and seed 1729. Use the same epoch and unchanged
   source data. Record SQL server UTC before and after each run; use separate
   windows that can each yield at least one fully contained, closed interval.
4. After flush grace, use `workload/ArchiveLoadRun.sql` in the lab archive and
   keep both RunIDs. For the exact same RunIDs reconcile canonical counts, CPU,
   duration, reads and observed waits to `reports/sql/CompareRuns.sql`. Record
   client p95 and throughput separately; Query Store aggregates are not client
   percentiles and cover a narrower measurement window.
5. Once one pair reconciles, collect two more matched pairs. Alternate order
   after the first pair if practical; record warmup/cache state. Inspect actual
   plans for both variants. If there is no repeatable difference, report it and
   try the prepared sort scenario. Do not present a manufactured regression.

Keep the snapshot/hash, environment versions, exact RunIDs and UTC windows,
test outcomes and raw receipts. Keep private hostnames and query text out of
public exports. If comparable runs display incorrect numbers, move that defect
ahead of dashboard polish. Do not change the existing archive or Agent jobs.

## 2. Dashboard and Voyager 2 follow-on

Make the existing Grafana Overview the product home. It already links to Period
Comparison and Wait Analysis. Add a last-successful-capture/coverage view by
source, clear stale or missing-data states, and direct drill-through into Run
Regressions, Load Test Lab, Interval Investigation, Wait Analysis and Query
Detail. Keep source selection and time context on consistent links. Only carry
RunIDs when the target uses the same source and archive; require the user to
choose a distinct baseline if one is not known. Do not make a second web app
or a Power BI model a prerequisite for the first working demo.

When Steve starts Voyager 2 follow-on work, use `VOYAGER2_GRAFANA_PROMPT.md`.
Keep its existing QueryVault archive and Grafana services untouched. In an
isolated lab, test all seven dashboards through the restricted reporting user.
Verify populated, empty, stale and incompatible-window states, link context,
accurate units and usable tables. Benchmark representative panels on known
row counts before adding indexes or summaries. Keep the generator and JSON in
sync. In the older dashboards use the existing capture evidence as a reference,
not as proof this candidate works.

## 3. Azure SQL Database readiness

Use a non-production source and a separate archive in an approved lab. Inventory
database tiers, Query Store state/interval/retention, network path, authentication,
existing scheduler, backup/restore and where Grafana will run. Keep Azure SQL
Managed Instance a separate compatibility target.

1. Build the Azure rowstore package and exercise `DeployReport` against an empty
   lab archive before any publish. Verify the deployed schema on the live service.
2. Read one closed Query Store window through a direct source connection. The
   current same-instance archiver relies on three-part names, which are not a
   cross-database collection path for Azure SQL Database. Prove TLS, then implement
   and test Microsoft Entra token auth for the collector, which does not support
   it today. Use a managed identity for a scheduled Azure deployment.
3. Implement batch ingestion into the archive, reusing canonical grain. Keep a
   stable source ID, a Query Store epoch, a transactional receipt and a per-source
   checkpoint. Test retries, overlapping windows, cleanup/reset gaps and a second
   synthetic client source. A failed write must not advance the checkpoint. Keep
   raw query text and plans scoped to authorized readers and verify that client
   separation holds before proposing a shared archive.
4. Schedule with Azure Automation or an approved worker once manual ingest passes.
   Keep capture health and data freshness distinct from query performance. Treat
   Azure Monitor and cost telemetry as a later integration, not as metrics
   inferred from Query Store. Keep Bicep and CI validation separate from deployment.

Microsoft reference material: [Azure SQL Database T-SQL differences](https://learn.microsoft.com/en-us/azure/azure-sql/database/transact-sql-tsql-differences-sql-server),
[Azure SQL job automation](https://learn.microsoft.com/en-us/azure/azure-sql/database/job-automation-overview),
[Azure Automation managed identity](https://learn.microsoft.com/en-us/azure/automation/manage-sql-server-in-automation).

## 4. Demo evidence for Netherwood Data Partners

Capture four views from real synthetic runs: Overview with capture status, Load
Test Lab with both RunIDs, Run Regressions with a verified change, and Query
Detail/Interval Investigation showing how you checked it. Capture an optional
native plan in SSMS if it renders. Use the same pair throughout and note which
data is public synthetic lab data. Then record a 60 to 90 second walkthrough.

For RegEd, show the SQL Server workflow and how you would tie the comparison to
a release. For Banjo Health, show the same workflow on actual Azure lab data
once the missing ingestion path has passed. Until then, label Azure as in
validation. Nothing here publishes a screenshot or changes an existing service.

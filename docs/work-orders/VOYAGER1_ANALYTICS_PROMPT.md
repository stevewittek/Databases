# Voyager 1 Codex work order

Paste the following into Codex on Voyager 1 with the current QueryVault source snapshot.

```text
Build and validate the QueryVault analytics expansion on this Windows machine.
Steve authorizes bounded work in a dedicated non-production SQL lab. Work through
this assignment without stopping at a plan. Do not change existing production
archives, global SQL settings, Agent jobs, clear global caches, deploy to Voyager2,
or send messages/publish anything externally.

Source gate:
- Use the updated QueryVault workspace/snapshot supplied with this prompt.
- Verify the ZIP SHA-256 from the lab kickoff before extraction. To build from
  the ZIP, keep the extracted files unchanged through the first build. The
  builder verifies their handoff manifest and does not require a Git checkout.
- Read AGENTS.md where present, docs/ANALYTICS_GUIDE.md,
  docs/ANALYTICS_ROADMAP.md and docs/ANALYTICS_RESEARCH.md.
- Require tools/build_analytics_dashboards.py,
  QueryVault/Functions/qv_report.fn_CompareRuns.sql,
  QueryVault/Tests/TestRunComparisonAnalytics.sql and workload/run_load.py.
- If those are absent, do not recreate the feature from an older origin/master.
  Complete a read-only environment inventory and report that the source snapshot
  must be transferred. The originating workspace has uncommitted compatibility
  changes, so origin/master alone is not the source of truth for this assignment.
- Preserve existing work. For fixes, use a dedicated branch/worktree. If only the
  ZIP is available, keep the verified extraction as a baseline, initialize a
  separate local Git repository from a copy for fixes, and return its patch.

Own these deliverables:
1. Inventory the SQL edition/build, available lab capacity, authentication,
   ODBC Driver 18, Python, pyodbc, sqlcmd, PowerShell and .NET. Record actual
   versions. Use credentials from existing secure configuration; never print them.
2. Run the Python suite and repository contract check. Build the correct portable
   package for the engine. SQL Server 2016 uses rowstore; do not assume newer
   columnstore support. Do not apply the fresh-install DACPAC to a populated DB.
3. Create an isolated archive lab, named QueryVaultRowstoreLab if using the
   existing local harness, and use workload/SetupLoadLab.sql to create the NEW
   QueryVaultLoadLab source. If either name already exists, inspect it and verify
   it is a disposable QueryVault lab before making changes. Never drop/recreate
   a database to force the setup script to pass. Apply DeployAnalytics.sql only
   to an existing dedicated archive lab with the prerequisite canonical contract.
4. Execute TestRunComparisonAnalytics.sql and the existing aggregation/reporting
   checks. When using tools/test_local_sql.py, remember it only supports dedicated
   disposable Docker container names; do not bypass that guard for native SQL.
   For a native Windows lab, run the SQL fixtures with sqlcmd -b and SQLCMD mode;
   resolve historical bootstrap includes as the harness does for a fresh model.
   Do not run destructive fixture scripts against a retained archive.
5. Prove weighted means, frequency-only changes, unequal window normalization,
   zero baselines, new/absent query semantics, source/epoch/identity guards,
   provisional/overlap rejection, restricted text handling, query waits and
   annotation cascade. Investigate any assertion failure; return actual evidence.
6. Run at least three baseline/regressed pairs with workload/run_load.py. Start
   with 2 workers, 180 seconds, 20 ms pause and the same seed/data/settings.
   Use one epoch until reset/restore. Measure SQL server UTC before/after each run.
   Wait for closed intervals and flush grace; use ArchiveLoadRun.sql in the lab
   archive to pin, label and capture only full interior intervals. Configure
   QueryVaultLoadLab through the existing initialization procedure if needed.
   Record each RunID and client JSON receipt. Stop on errors or lab resource
   problems. Do not manufacture a regression if this engine produces similar plans.
7. Independently reconcile CPU/duration/reads/execution counts and wait intensity
   with canonical facts at their documented grain. Compare identical run IDs
   using reports/sql/CompareRuns.sql. Report measurement variability across pairs,
   workload throughput effects and client-versus-archive boundary differences.
8. If Power BI Desktop is installed, validate the M function in
   reports/powerbi/RunComparison.pq and write exact working setup steps. Do not
   claim an actual PBIX/SSRS report exists unless you create and verify it.
9. Fix defects in your scope, add meaningful regression coverage and return a
   patch plus docs/VOYAGER1_ANALYTICS_RESULTS.md with commands, versions, outcomes,
   run IDs, measured values and outstanding limitations. Do not modify Grafana
   dashboard JSON; Voyager2 owns rendering feedback. Coordinate any SQL contract
   changes through a proposed patch to avoid concurrent incompatible rewrites.

Done means actual SQL fixture execution and at least one verified comparable
load-test pair, or a precise evidenced blocker. Passing model compilation alone
is not live SQL acceptance. Keep all credentials, receipts with private endpoints,
backups and captured query text out of public commits.
```

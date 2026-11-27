# Voyager 2 Codex work order

Paste the following into Codex on Voyager 2 with the same current source snapshot.
This is the follow-on lab work order. Start only when Steve asks to run it.

```text
Validate QueryVault's new analytics reporting and Grafana on Voyager2 Linux.
Steve authorizes bounded non-production lab work. Continue through implementation
and evidence collection without stopping at a proposal. Do not alter the existing
QueryVaultDB archive, current Grafana services/datasources, production configuration,
retention, Agent jobs or any unrelated service. Do not deploy to existing services
or publish/send anything externally.

Source gate:
Read AGENTS.md where present, docs/ANALYTICS_GUIDE.md,
docs/ANALYTICS_ROADMAP.md and docs/ANALYTICS_RESEARCH.md. Require all three new
qv-* analytics dashboards, RunAnalysisContext and the four fn_Compare* functions.
Use the supplied current snapshot, not an older origin/master clone. Missing
files are a source-transfer blocker, not permission to guess their contents.
Verify the ZIP SHA-256 from the lab kickoff before extraction. Keep the extracted
files unchanged through the first build so the builder can verify the manifest.
For fixes, use a separate branch/worktree or local Git repository copied from the
verified extraction. Preserve other work.

Own these deliverables:
1. Inventory actual SQL engine, Linux, Docker/Compose, Grafana, certificate and
   capacity state read-only. Historical documents are not proof of current state.
   Do not reveal secret environment values or dump docker inspect/config output
   containing secrets. Use compose config --quiet for validation.
2. Run Python tests, repository contract checks and correct SQL package builds.
   Use a new dedicated archive lab if capacity permits. Never publish the fresh
   install DACPAC into QueryVaultDB. For an existing disposable lab, review the
   additive DeployAnalytics.sql migration and execute it only with explicit DB
   targeting, a recoverable baseline and abort-on-error behavior.
3. Execute the new deterministic comparison fixture and collect at least two
   canonical nonoverlapping lab runs. Use the synthetic load lab on this machine
   only if it is separate from Voyager1's active experiment. Do not load-test
   historical StackOverflow/WideWorldImporters or production sources by default.
   Reconcile canonical totals and check SQL Server 2025/Linux behavior.
4. Verify restricted reporting access: SELECT on qv_report views and inline TVFs
   succeeds, Showplan retrieval succeeds, dbo.RunMetadata and run label writes are
   denied. No broad dbo SELECT/EXECUTE grant. Validate the server certificate
   rather than committing tlsSkipVerify=true.
5. Launch a separate Grafana lab using grafana/compose.analytics.yaml, a tested
   explicit image tag/digest, separate volume/service name and loopback port 3031
   or another unused loopback port. Keep existing services intact. Provide admin
   and reporting passwords only through secure environment configuration.
   If resources or permissions block a separate instance, provide exact evidence
   and do not replace an existing service as a workaround.
6. Provision all seven dashboards. Execute every variable and panel query through
   the restricted datasource. Test date/source/run dependencies, baseline versus
   candidate selection, experiment variants, no-data states, mismatched/legacy/
   provisional runs, new/absent queries, threshold/minimum-execution filters,
   UTC labels, units and hidden/restricted text. Empty guarded comparisons must
   show the readiness reason, not imply successful zero-regression analysis.
7. Render the new Run Regressions, Load Test Lab and Interval Investigation
   dashboards with genuine lab data. Capture screenshots and SQL reconciliation
   evidence. Verify panels do not overlap, tables are usable and legends/units
   make sense. Fix dashboard generator code in tools/build_analytics_dashboards.py
   and regenerate JSON rather than introducing generator drift.
8. Measure representative reporting queries on actual retained lab data with
   execution plans, IO and duration. Report dataset sizes and warm/cold conditions.
   Propose indexes or summary tables only for measured bottlenecks; no automatic
   changes to production facts, storage or global SQL settings. Examine query
   plan inventory versus actually executed plans and document any limitation.
9. Return a patch and docs/VOYAGER2_ANALYTICS_RESULTS.md with environment versions,
   exact lab target names, check outcomes, panel/query totals, screenshots,
   verified local Grafana URLs, SQL RunIDs and remaining defects. Never claim a
   screenshot or live dashboard exists without observing it. Coordinate SQL
   contract changes as proposals; Voyager1 owns the paired workload measurements.

Done means actual restricted-user SQL execution and rendered new dashboards,
or a specific evidenced blocker. Static JSON/SQL validation is already available
and does not count as runtime/rendering acceptance. Preserve the lab and evidence
for Steve to review. Do not remove databases, volumes or experiment runs at the end.
```

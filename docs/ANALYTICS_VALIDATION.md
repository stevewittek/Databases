# Analytics candidate validation

November 22, 2026. Evidence is from the current local working tree, including
pre-existing November compatibility changes. No commit or remote publication was
made. This report does not supersede historical deployment evidence with new
runtime claims.

## Passed locally

| Check | Result | Scope |
| --- | --- | --- |
| Python unittest discovery | 26 passed | Existing portability tests plus dashboard contracts and bounded-runner behavior |
| PowerShell repository contract check | Passed; 48 canonical SQL build items | Both project manifests and operational/model definitions agree |
| SQL Server 2016 rowstore model | Compiled | DacFx Sql130 |
| SQL Server 2017 columnstore model | Compiled | DacFx Sql140 |
| SQL Server 2019 columnstore model | Compiled | DacFx Sql150 |
| SQL Server 2022 columnstore model | Compiled | DacFx Sql160 |
| SQL Server 2025 columnstore model | Compiled | DacFx Sql170 |
| Azure SQL rowstore model | Compiled | DacFx SqlAzureV12 |
| New dashboard queries | 49 SELECT statements compiled against full SQL model | Variables replaced by representative typed values; ordering removed only in temporary validation views |
| T-SQL syntax | 55 files/statements parsed without errors | 49 dashboard queries plus upgrade, fixture, workload setup/capture and two SQL reports |
| YAML parsing | Passed | Grafana provisioning, Compose and portable CI workflow |
| Compose configuration | Passed with placeholder environment and --quiet | No image download, startup or SQL connection |
| Changed PowerShell syntax | Passed | Deployment, post-verification and repository-check scripts |
| Python syntax and git diff --check | Passed | Source parsing and whitespace |

Builds used previously cached NuGet packages through a temporary offline feed.
The first ordinary restore could not retrieve online package vulnerability data;
the final offline model builds succeeded without compiler warnings/errors.
Compiled models are not runtime certification of the engine or Azure service.

`tools/validate_dashboard_sql.py` makes SQL projection/schema validation reproducible.
It copies a prepared portable model into an ignored validation directory and adds
temporary views containing each new dashboard SELECT. It never connects to SQL.
ScriptDom independently parsed the actual ORDER BY-bearing SQL and new scripts.

## Not executed or verified here

- `TestRunComparisonAnalytics.sql` and other live SQL assertions;
- the additive SQL upgrade on a populated database, rerun behavior or rollback;
- restricted-user permissions and cascade deletion on a live server;
- workload execution, real baseline/regressed pairs or performance improvements;
- actual Grafana startup, datasource connectivity, dashboard rendering/screenshots;
- Power BI Desktop invocation or any PBIX, PBIT or SSRS artifact;
- reporting performance at production data volumes;
- remote work on Voyager 1 or Voyager 2, or deployment to existing services.

Docker daemon access was denied for the current sandbox. External shell DNS was
also restricted; research used the connected web/GitHub tools and builds used the
local package cache. No approval override was attempted. These restrictions do not
prevent another local Codex session with suitable machine permissions from running
the provided lab work orders.

## Deterministic SQL assertions prepared for the machines

The new transactional fixture covers weighted run comparisons, normalized rates
for unequal windows, frequency-only growth, new/absent queries, zero baselines,
identity/context changes, restricted text, plan-hash inventory changes, missing
wait observations, query-level wait intensity, missing/same/foreign runs,
conflicting epochs, provisional observations, invalid coverage, overlapping
windows, and experiment metadata following run deletion. It rolls back its rows.
The script has been parsed; the assertions are not reported as passed.

## Reproduction

```sh
python3 -m unittest discover -s tests -v
pwsh -NoProfile -File QueryVault/Tests/TestRepositoryContracts.ps1
python3 tools/build_analytics_dashboards.py
python3 tools/package_queryvault.py --target 2022 --storage columnstore
python3 tools/validate_dashboard_sql.py
python3 tools/package_analytics_handoff.py
```

For the full build matrix use each target/storage pair above. An optional
`--nuget-source PATH` on the dashboard validator allows a prepared offline NuGet
feed. On Voyager, follow the dedicated work order for actual SQL and Grafana
acceptance. Capture environment versions, commands and evidence rather than
copying these local status labels into a new runtime report.

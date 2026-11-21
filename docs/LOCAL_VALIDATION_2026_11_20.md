# Local validation — November 20, 2026

Historical foundation evidence only. The later combined candidate is documented
in `REGISTRY_VALIDATION_2026_11_20.md`; do not apply these 40-item results to it.

Repository baseline: `0687cfe`, local branch
`codex/queryvault-compatibility-foundation`. Validation covers the local candidate,
not the deployed Voyager2 archive. Times in raw SQL logs are UTC and can show
November 21 while the user-facing Eastern date is November 20.

## Executed results

| Check | Result |
| --- | --- |
| Original Windows SSDT project under Mac `dotnet build` | Confirmed failure: missing Visual Studio SSDT targets; new portable path addresses this |
| Existing repository contracts | PASS: 40 canonical model items, procedure/view synchronization and existing safety checks |
| Offline collector/package/CLI tests | PASS: 16 tests |
| SQL 2016 / rowstore model | PASS: zero compiler errors or warnings |
| SQL 2017 / columnstore model | PASS: zero compiler errors or warnings |
| SQL 2019 / columnstore model | PASS: zero compiler errors or warnings |
| SQL 2022 / columnstore model | PASS: zero compiler errors or warnings |
| SQL 2025 / columnstore model | PASS: zero compiler errors or warnings |
| Azure SQL / rowstore model | PASS: zero compiler errors or warnings |
| Package dependencies and hashes | PASS: QueryVault.dacpac and master.dacpac included; SHA-256 checks and ZIP integrity verified |
| SqlPackage 170.5.96 offline script generation | PASS against an empty target DACPAC |
| Generated SQL deployment to disposable SQL 2022 | PASS: complete schema, views and procedures installed |
| Reinstall over populated archive | PASS: predeployment guard rejected it with error 51090 |
| Real Query Store archive capture | PASS: two query texts, queries, plans and native runtime contributors archived; two canonical runtime grains |
| Reduced-capability fixture | PASS: absent plan/runtime fields became NULL, wait collection was skipped, availability recorded; original procedure restored |
| Canonical Query Store aggregation SQL assertions | PASS |
| Partition safety guard SQL assertions | PASS |
| Run partition lifecycle SQL assertions | PASS |
| Expired archive purge SQL assertions | PASS |
| Reporting contract and canonical reporting regression | PASS with two retained sample periods |
| Ambient transaction ownership guard | PASS: error 51006, caller transaction count preserved |
| Fresh rowstore schema and live capture | PASS on SQL 2022; both live and reduced-capability captures |

The rowstore package uses a model targeting SQL 2016. The rowstore regression
suite was also run at compatibility level 130 on the SQL 2022 engine. This is
**not** actual SQL Server 2016 engine validation.

## Environment and method

- macOS Apple Silicon host; local .NET SDK 11.0.100.
- Microsoft.Build.Sql 2.3.0; target-specific system DACPAC versions pinned in the builder.
- Disposable SQL Server 2022 Developer container, version 16.0.4325.4 (CU28).
- Image digest: `sha256:4525e3efac9f3e241cb003bb2ff2a82818b502f37e12049d788b1a9fa7e13b7f`.
- Linux amd64 image under local emulation; no host port published, production
  credentials, mounted production data or cloud resource access.
- Generated lab-only password; certificate trust override used only by SQLCMD
  inside this disposable container. The product CLI/exporter retain TLS verification.
- SqlPackage generated SQL offline from the SQL 2022 candidate and an empty
  model; that generated script was executed locally. The rowstore profile was
  installed from its generated declarative sources.
- Existing SQL tests were expanded by `tools/test_local_sql.py`, omitting only
  additive table bootstrap includes already present in the fresh full schema.
- The live sample generated no Query Store wait rows. Nonzero wait aggregation
  is covered by the existing synthetic canonical test, not by this live workload.
- The reduced-capability fixture removes metadata entries before projection;
  it proves the fallback branch behavior, not an older engine's entire catalog.

The harness initially exposed setup prerequisites (SQLCMD quoted identifiers and
two retained periods for comparison). These were supplied before the successful
runs. No failing SQL assertion was disabled to get a pass.

## Evidence files

Local-only output under ignored `artifacts/`:

- `build-matrix.log` and each package's `manifest.json`;
- `install-local.sql`, `local-dacpac-install.log`;
- `local-capture.log`, `local-capability-fallback.log`;
- `local-sql-tests.log`, including both columnstore and rowstore runs;
- `local-redeploy-guard.log`, `local-final-state.log`;
- six `QueryVault-<target>-<storage>.zip` deployment bundles.

The disposable container and generated password file are removed after testing.
The downloaded test image remains cached. No user data was removed.

## Not verified / not implemented

- Actual SQL 2016, 2017, 2019, 2025, Express or Standard instances.
- Azure SQL Database / Managed Instance deployment or collection.
- Native supported-host performance, scale, concurrency, failover and recovery.
- Existing-archive nullable-column upgrades or storage conversion.
- Integrated/Entra authentication through the deployment wrapper.
- The new Python exporter's ODBC connection against a real server; its orchestration
  and serialization are tested with fixtures. The T-SQL collector was exercised live.
- Remote batch ingestion, source registry resolution, transactional receipt and
  checkpoints, scheduler/leases, automatic source-epoch detection.
- Durable spool recovery after power loss, encrypted spool lifecycle or tenant isolation.
- Azure cost estimates, automatic capacity recommendations or resizing.
- New Grafana panels, browser dashboard execution or an optional web UI.

The existing September dashboard screenshots and 49-query validation are historical;
they were not regenerated. The four dashboard JSON files were checked for parseability.
The new CI workflow was prepared locally, not posted or run on GitHub.

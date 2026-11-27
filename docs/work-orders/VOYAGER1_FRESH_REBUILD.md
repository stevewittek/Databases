# Voyager 1 fresh rebuild after the stopped deployment

Target only `QueryVaultDB` on `DESKTOP-CLVE7DV`. This runbook uses the fresh-install package. The GitHub `QueryVault | Voyager 1` **deploy** mode is an in-place updater with a backup and is not the way to perform this one-time rebuild.

## Get the correct source on the desktop

- From the existing `D:\Dev\QueryVault\Databases` checkout, inspect the configured `origin` and local changes, then fetch `stevewittek/Databases`. Use a separate checkout or detached worktree at Steve's exact supplied revision. Do not reset or force-update the existing checkout.
- Verify the revision, model and release contents. The revision must contain `QueryVault/Functions/DatabaseProject/qv_report.fn_CompareRuns.sql` and the other three `qv_report.fn_Compare*` functions, `RunAnalysisContext`, `tools/package_queryvault.py`, and `.github/workflows/queryvault-voyager1.yml`. The cached `cd20d8e` and `dc0f471` revisions are not this release.
- Run `python -m unittest discover -s tests`, `pwsh -NoProfile -File QueryVault/Tests/TestRepositoryContracts.ps1` and `python tools/package_queryvault.py --target 2019 --storage columnstore` after verifying engine 15.x. The current project contract has 48 model items. Verify the package manifest records the expected commit and verify the DACPAC and adjacent `master.dacpac` checksums. Build and prepare the install script before taking the current database offline.

## Use the working Windows identity

The intercepted session reported `DESKTOP-CLVE7DV\codexsandboxoffline` and `Failed to generate SSPI context`. Do not repeat the same failing connection or create a SQL login for that sandbox account. `MSSQLSERVER` is the default service name. Use the bare server name or the verified local endpoint, not `DESKTOP-CLVE7DV\MSSQLSERVER` as a named instance.

Use the existing connected local SSMS session or `sqlcmd -E` / PowerShell launched by the same signed-in Windows account that already works with SQL Server. Prove the instance, principal, visibility of the database and job, and the permissions needed for the exact rebuild before any change. If Codex cannot use that Windows identity, prepare reviewable scripts and give Steve a precise handoff to run those in SSMS. Do not ask him to paste a password or token into chat. Do not change TLS trust, firewall, SQL authentication or permissions to force a connection.

## Rebuild and verify

1. In the authenticated session, record only operational configuration needed to rebuild. Inspect `QueryVaultDB.dbo.DatabaseConfig` for enabled source names and settings. Inspect the one existing archive Agent job for the step target, schedule, owner and whether it is currently running. Keep this information local. Do not save archive data, take a backup, take a snapshot or copy the old database.
2. Disable the existing `QueryVault - Archive All Enabled Databases` job for the maintenance window. If a run is active, let that run finish before rebuilding. From the verified instance, drop and recreate **only** `QueryVaultDB`. Apply the built SQL Server 2019 DACPAC only to the now-empty target. If using a generated SQL script in SSMS, review the target and enable SQLCMD Mode for its directives. Do not change any other database, job or linked server.
3. Verify the `dbo`-owned `qv_report` schema, canonical archive tables, partition function/scheme, `RunAnalysisContext`, and all four comparison functions on the live target. Restore only verified source configuration. Leave auto-purge disabled for this fresh bring-up. Recreate or update the existing job without duplicating it. Prefer updating its existing definition in place to preserve Agent history and the observed schedule rather than blindly running the job-create template.
4. With the daily job still disabled, use a known configured local source and a closed Query Store window for a bounded capture. Verify a completed RunID, positive canonical runtime row count, and a read through `qv_report`. If possible validate the comparison fixture in the fresh environment and ensure it rolls back as designed. Re-enable the daily job only when checks pass, then re-read its schedule and target. Do not start an unbounded workload or trigger all sources for validation.
5. Return exact source SHA, SQL instance/version, deployed schema checks, Agent job state and next schedule, RunID and archived row counts. If the job cannot pass, identify the exact failing operation and keep it disabled. Do not substitute a successful build for a live deployment.

## GitHub pipeline

The repository already has `Actions > QueryVault | Voyager 1`. Keep its Windows worker and local TLS / status-token setup separate from this first install. Follow `docs/work-orders/VOYAGER1_DEPLOYMENT_PROMPT.md` for that worker and validate with `inspect` after the rebuild. Do not switch on the in-place `deploy` mode merely to make this replacement happen, and do not dispatch the Voyager 2 workflow.

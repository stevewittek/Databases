# QueryVault V1 Release-Candidate Validation Report

Validation date: 2026-09-03. Branch: `codex/queryvault-v1-rc`.

The cumulative candidate at
`65336e2c1588351712e8bd7c8c85af0238cdbeed` was deployed to Voyager2 through
the guarded production workflow. A necessary Grafana-only display fix was then
committed as `cb06d520fa87d043495a2b50d507181e5783f929` and the complete affected
Grafana validation was rerun. After integration, current `master` at
`dc0f471038776832d303168d660082dcab143fff` was deployed successfully by
[production workflow run 33803899971](https://github.com/stevewittek/Databases/actions/runs/33803899971).

The full evidence, exact values, environment notes, and acceptance matrix are
in [Voyager2 RC Validation](VOYAGER2_RC_VALIDATION.md).

## Final acceptance summary

| Area | Result |
| --- | --- |
| Guarded deployment | PASS |
| Historical archive and configuration preservation | PASS |
| Canonical runtime aggregation and contributor lineage | PASS |
| Canonical wait aggregation and contributor lineage | PASS |
| RunID partition lifecycle and switch compatibility | PASS |
| Retained-run and physical partition capacity guards | PASS |
| Disposable-run purge and obsolete-boundary merge | PASS |
| Pinned-run protection | PASS |
| RuntimeStats and WaitStats storage recommendations | PASS |
| Least-privilege native MSSQL Grafana datasource | PASS |
| QueryVault Overview | PASS |
| Period Comparison | PASS |
| Wait Analysis | PASS |
| Query Detail | PASS |
| Native Showplan XML retrieval/export | PASS |
| SSMS `.sqlplan` graphical rendering | NOT TESTED |
| Backup and rollback readiness | PASS |

There are no `FAIL` or current `BLOCKED` results. SSMS was unavailable on the
macOS/Linux validation hosts, so graphical plan rendering is intentionally not
inferred.

## Data-preservation result

The pre-deployment database had 39 archive runs. All survived the additive
migration. Original RunIDs through 47 retain exactly:

| Archive object | Rows |
| --- | ---: |
| Query | 1,690 |
| Query text | 1,659 |
| Plan | 1,699 |
| Runtime stats | 2,366 |
| Runtime intervals | 709 |
| Wait stats | 391 |

The migration added lifecycle configuration defaults of
`MaxRetainedRuns = 1000`, `PartitionWarningPct = 80`, and
`StorageMode = AUTO` without replacing existing configuration values.

## Live canonical evidence

A bounded WideWorldImporters capture was retained as RunID 101. Its 87 runtime
contributors produced 87 documented canonical grains; its 11 wait contributors
produced 11 documented canonical grains. Execution count and weighted CPU,
duration, logical-read, and wait totals reconcile exactly. Duplicate canonical
grains and interval orphans are zero.

RunID 101 maps to physical partition 102; boundary 102 leaves the required
future partition. The partition-function fanout is 103. All ten archive tables
and ten maintenance mirrors remain aligned, no canonical partition contains
multiple RunIDs, maintenance tables are empty, and no tautological switch
constraint remains.

## Tests

The following passed after the Grafana correction:

- repository contracts: 40 SQL project items, 10 reporting-contract items,
  and 10 partition safety assertions;
- procedure compilation;
- Query Store aggregation grain;
- canonical runtime/wait aggregation;
- reporting canonical regression and standalone reporting contract;
- partition safety guards;
- purge behavior; and
- complete RunID lifecycle, pin, merge, capacity, alignment, and SWITCH
  compatibility.

All 49 Grafana template-variable and panel queries also passed through the live
MSSQL backend with no errors and no empty required variables. Dashboard JSON,
provisioning, datasource UIDs, and the `qv_report`-only SQL boundary validate.

The SQL test files use Windows SQLCMD include separators and unconditional
table-create includes. On the already deployed Linux database, the same tests
were streamed with separators normalized and only redundant table-create
includes removed. All definitions, fixtures, and assertions ran unchanged and
rolled back.

## Backups and rollback

The guarded deployment created and checksum-verified:

`/var/opt/mssql/userlog/backups/voyager2/QueryVaultDB/FULL/voyager2_QueryVaultDB_FULL_20260903_133909_predeploy_copyonly.bak`

It also wrote the pre-deployment state baseline:

`/home/nasa/queryvault-production/baselines/QueryVaultDB_20260903T133908Z_65336e2c1588.json`

An additional checksum-verified pre-bootstrap copy-only backup is recorded in
the full validation document. The later current-`master` deployment created and
verified
`/var/opt/mssql/userlog/backups/voyager2/QueryVaultDB/FULL/voyager2_QueryVaultDB_FULL_20260903_204355_predeploy_copyonly.bak`.
Its pre/post checks passed, all 22 existing tables and archive data were
preserved, and no SQL Agent job was changed.

## Release conclusion

The validated candidate was integrated into `master` and its current commit was
deployed successfully through the guarded workflow. No RuntimeStats or
WaitStats storage conversion was performed, and this report is not
authorization for one.

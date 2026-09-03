# QueryVault Canonical Aggregation Validation Report

Validation date: 2026-09-03. Branch:
codex/queryvault-canonical-aggregation. Base:
e3a536d0ae90d326d0c8968a5964f1bcb7053c77 from
origin/codex/queryvault-grafana-v1.

No QueryVault database, SQL Agent job, login, Grafana instance, master branch,
or Voyager2 object was deployed or modified. Local database tests used explicit
outer transactions and rollback.

## Acceptance matrix

| Area | Result | Evidence |
| --- | --- | --- |
| Base commit verification | PASS | The integration remote ref resolved exactly to e3a536d0ae90d326d0c8968a5964f1bcb7053c77 before branch creation. |
| Repository contracts | PASS | TestRepositoryContracts.ps1: 38 SSDT build objects, 10 reporting assertions, 4 partition guards; project mirrors and deployment sources synchronized. |
| Visual Studio 2026 SSDT | PASS | MSBuild 18.9.1 rebuilt both SQL project manifests in Release; QueryVault.dacpac and QueryVault_Fixed.dacpac completed with zero warnings and zero errors. |
| Procedure compilation | PASS | Archive, canonical materializer, and partition procedures compiled/refreshed inside a rolled-back local transaction. |
| Canonical synthetic aggregation | PASS | All contributors retained; runtime/wait grains, sums, weighted values, extrema, last ambiguity, standard-deviation status, replica lineage, unique keys, and provisional rematerialization validated. |
| Query Store grain safety | PASS | Completed-interval cutoff, contributor targets, materializer call, canonical grains, uniqueness, and interval references validated. Legacy duplicate runtime groups in RunIDs 8 and 12 were reported rather than discarded. |
| Partition safety | PASS | Updated ten-table archive and maintenance lists compiled; shared overflow partition truncate was rejected without row loss. |
| qv_report regression | PASS | Period 16 reconciled to 752 executions, 3,655.069 ms CPU, 25,703.835 ms duration, 312,930 logical reads, and 112 ms wait. Top/query metrics, comparison to period 12, plan history, and native Showplan XML retrieval passed. |
| Reporting compatibility | PASS | Canonical-first views fall back to legacy rows per run. Temporary qv_report schema/view/procedure changes were rolled back. |
| Dashboard SQL | PASS / unchanged | No file below grafana/dashboards was modified. Existing dashboard SQL continues to use the same qv_report columns and objects. |
| Purge integration | NEEDS VALIDATION | The local QueryVaultDB has auto-delete disabled and does not have the current purge procedure deployed. The existing integration test cannot run there without deployment. No retention code was changed. |
| Voyager2 live validation | BLOCKED | A read-only connection attempt to the Voyager2 hostname failed with SQL network error 53/timeout. No alternative endpoint was present in the repository and no deployment was attempted. |
| SQL Server 2022+ replica capture | NEEDS VALIDATION | Static version-aware SQL and synthetic mixed-replica behavior pass; a live 2022+ source capture was unavailable. |

## Deterministic correctness coverage

TestCanonicalQueryStoreAggregation.sql covers at least these independent cases:

1. one runtime contributor;
2. repeated native runtime ID;
3. execution-count sum;
4. execution-weighted runtime mean;
5. combined runtime extrema;
6. chronological runtime last value and contributor lineage;
7. tied latest runtime timestamps and explicit ambiguity;
8. multi-contributor standard-deviation unavailability;
9. mixed runtime replica lineage;
10. isolation by runtime execution type;
11. isolation by interval;
12. isolation by plan;
13. repeated native wait ID and additive total;
14. wait average using matching runtime executions;
15. wait-category isolation;
16. wait extrema, last ambiguity, dispersion, and replica lineage;
17. canonical-key duplicate rejection; and
18. PROVISIONAL rematerialization.

The fixture deliberately uses contributors with execution counts 1 and 99 so
an arithmetic average cannot accidentally pass the weighted-mean assertion.
Wait contributors total 1,000 ms against 100 executions, asserting a 10 ms
canonical average.

## Commands run

- PowerShell TestRepositoryContracts.ps1
- SQLCMD TestCanonicalQueryStoreAggregation.sql
- SQLCMD TestQueryStoreAggregationGrain.sql
- SQLCMD TestProcedureCompilation.sql
- SQLCMD TestPartitionSafetyGuards.sql
- SQLCMD TestReportingCanonicalRegression.sql
- Visual Studio 2026 MSBuild Rebuild, Release, VisualStudioVersion 18.0

Expected SQL aggregate warnings about NULL elimination occurred where the test
intentionally supplies unavailable values. Every listed command returned exit
code zero.

## Release conclusion

The additive canonical aggregation change is internally consistent, builds
cleanly, retains all native statistic contributors, and preserves the existing
reporting contract. It is ready for review and integration from its feature
branch. It is not approval to deploy: Voyager2, live SQL Server 2022+ replica
capture, provisional reconciliation, and production-shaped retention remain
explicit follow-up validation.

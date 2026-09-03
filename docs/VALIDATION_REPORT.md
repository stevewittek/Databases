# QueryVault Run Partitioning Validation Report

Validation date: 2026-09-03. Branch:
`codex/queryvault-run-partitioning`. Base:
`cac2e5a4391647523b4a42d8b040f260bbd2dac5` from
`origin/codex/queryvault-canonical-aggregation`.

No QueryVault deployment, SQL Agent job, login, Grafana instance, master
branch, or Voyager2 object was modified. Local database tests loaded changed
definitions and synthetic rows inside explicit transactions and rolled them
back.

## Acceptance matrix

| Area | Result | Evidence |
| --- | --- | --- |
| Base and branch verification | PASS | Origin was fetched; the requested remote ref resolved exactly to `cac2e5a4391647523b4a42d8b040f260bbd2dac5` before creating the feature branch. |
| Repository contracts | PASS | `TestRepositoryContracts.ps1`: 40 SSDT build objects, 10 unchanged reporting-contract items, 10 partition safety assertions; procedure/function/view mirrors synchronized. |
| Visual Studio 2026 SSDT | PASS | Installed MSBuild/SSDT built both `QueryVault.sqlproj` and `QueryVault_Fixed.sqlproj` in Release with zero reported warnings/errors, producing both DACPACs. |
| Compilation | PASS | Capacity function, initialization, partition, archive, canonical materializer, purge, and storage advisory definitions refreshed inside a rolled-back transaction. |
| Run partition lifecycle | PASS | Exact mapping, future boundary, sparse allocation policy, real switch/truncate, pinned protection, purge, obsolete-boundary merge, limits, and index alignment passed transactionally. |
| Shared-overflow protection | PASS | Existing regression inserted two RunIDs into one maintenance overflow partition; truncate was rejected and both rows survived until rollback. |
| Legacy overflow split protection | PASS | Allocation code inspects the prospective split partition across all twenty run-owned/maintenance tables and fails with an explicit migration requirement when nonempty. Local RunID 1004 above boundary 120 provides observed legacy context; it was not moved. |
| Deterministic purge | PASS | Synthetic expired run was switched/truncated, its metadata deleted, and boundary merged. The configuration, data, definitions, and boundary were rolled back. |
| Canonical aggregation | PASS | Contributor retention, documented runtime/wait grains, weighted values, ambiguity/dispersion handling, replica lineage, uniqueness, and provisional rematerialization passed unchanged. |
| Query Store grain audit | PASS | Completed-interval cutoff, contributor targets, canonical grains, uniqueness, and interval references passed. Legacy duplicate runtime groups in RunIDs 8 and 12 were reported rather than discarded. |
| `qv_report` regression | PASS / unchanged | Self-contained transactional regression reconciled period 16 to 752 executions, 3,655.069 ms CPU, 25,703.835 ms duration, 312,930 logical reads, and 112 ms wait; period comparison and native Showplan passed. No `qv_report` source changed. |
| Grafana | PASS / unchanged | No file under `grafana/` changed. Existing dashboard queries continue using the stable `qv_report` interface. |
| Deployment verifier | PASS (static) | PowerShell parses; expected-object checks, config validation/hash, compilation, and smoke queries now include lifecycle columns, capacity function, and advisory view. It was not run in Post mode because this branch was not deployed. |
| Voyager2 | NOT RUN | Explicitly outside this task. No deployment or connection was attempted. |
| SQL Server 2022+ live capture | NEEDS VALIDATION | Version-aware static/synthetic behavior remains valid; live SQL Server 2022+ source validation was unavailable. |
| Production storage thresholds | NEEDS VALIDATION | Recommendation is deliberately advisory; rowstore/columnstore/archive benchmarks remain. |

The standalone `TestReportingContract.sql` expects the reporting package to be
deployed and therefore is not independently self-contained on this local
database. The self-contained `TestReportingCanonicalRegression.sql` loaded the
same reporting definitions inside a transaction, invoked that contract test,
passed, and rolled back. No deployment was performed to manufacture the
standalone prerequisite.

## Deterministic run-lifecycle coverage

`TestRunPartitionLifecycle.sql` covers at least these 17 independent cases:

1. default `MaxRetainedRuns = 1000`;
2. default `PartitionWarningPct = 80`;
3. default `StorageMode = AUTO`;
4. rejection below the retained-run minimum;
5. rejection above the retained-run maximum;
6. configured warning-threshold calculation;
7. configured retained-run maximum rejection;
8. 15,000 hard ceiling plus ten-partition headroom;
9. allocation independent of lifetime RunID magnitude;
10. first RunID maps to an isolated partition and empty future partition;
11. a second retained RunID maps to a different partition;
12. allocation consumes no more than two missing boundaries;
13. all archive/maintenance indexes remain partition-aligned;
14. real switch preserves run rows in maintenance storage;
15. truncate removes switched rows;
16. metadata deletion followed by exact obsolete-boundary merge; and
17. pinned protection plus full expired-run purge/merge and configured-max
    enforcement without physical allocation.

The separate shared-overflow test adds negative coverage for physical
partitions containing multiple RunID values. Repository contracts also assert
the nonempty legacy-overflow guard, serialized application lock, exact/sparse
archive call, merge path, pin checks, ceiling constants, and unchanged public
reporting sources.

## Commands run

- `QueryVault/Tests/TestRepositoryContracts.ps1`
- SQLCMD `TestRunPartitionLifecycle.sql`
- SQLCMD `TestPurgeExpiredArchives.sql`
- SQLCMD `TestPartitionSafetyGuards.sql`
- SQLCMD `TestProcedureCompilation.sql`
- SQLCMD `TestCanonicalQueryStoreAggregation.sql`
- SQLCMD `TestQueryStoreAggregationGrain.sql`
- SQLCMD `TestReportingCanonicalRegression.sql` (which invokes
  `TestReportingContract.sql` transactionally)
- Visual Studio 2026 MSBuild Release builds of both SQL project manifests with
  `/p:VisualStudioVersion=18.0`
- PowerShell parser validation for deployment/test scripts

Expected SQL warnings about NULL elimination occurred only in aggregation
fixtures that intentionally supply unavailable values.

## Schema and behavior reviewed

Persistent schema additions are three `DatabaseConfig` columns with
defaults/checks, one inline capacity-policy function, and one administrative
advisory view. The deployment path also runs the existing compatibility
migration that drops six specifically named tautological
`CHECK (RunID = RunID)` constraints when present; the real SWITCH test proved
those legacy constraints block semantic validation. Existing RunID,
RunMetadata counts, partition function/scheme, run-owned tables, indexes,
reporting objects, and Grafana contracts were otherwise reused. Capture changed
only its partition-allocation call. Purge gained exact boundary merge after
successful switch/truncate and metadata deletion.

The initial partition function's 1..100 boundaries remain to avoid an unsafe
declarative rewrite. Future growth is exact/sparse. Populated legacy overflow
is rejected with a migration message rather than automatically moved or split.

## Release conclusion

The change is a focused hardening of the existing RunID lifecycle, not a broad
redesign. It is ready for feature-branch review and Mac workstream integration.
This is not deployment approval: legacy-overflow migration, Voyager2 planning,
production storage benchmarks, and live SQL Server 2022+ capture remain
explicit follow-up work.

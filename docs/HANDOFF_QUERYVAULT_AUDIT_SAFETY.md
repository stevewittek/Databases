# QueryVault audit and safety handoff

Handoff date: 2026-09-03

## Git record

- Starting branch observed before handoff: `master`
- Starting HEAD: `db0d8e6edaf6710117b8f7496fb5aa28e6313e33`
- Local handoff branch created before commit: `codex/queryvault-audit-safety`
- No fetch, rebase, merge, push, force-push, or deployment was performed.
- A pre-existing `Databases.slnx` edit changed the portable project path to the machine-specific absolute path `D:/Dev/QueryVault/Databases/QueryVault/QueryVault.sqlproj`. It was recorded, excluded from this coherent cross-platform commit, and restored to the tracked portable form so the handoff branch could be clean.

## Functionality added

- Partition growth now covers `RunID` identity jumps instead of assuming ten new boundaries are always enough.
- Partition switch and truncate operations reject physical partitions containing more than one `RunID`.
- Direct switch/truncate operations own and safely roll back their transaction when no caller transaction exists.
- SSDT can build a complete DACPAC from declarative partition and procedure model sources while idempotent deployment wrappers remain available.
- Repository tests detect drift between deployment procedures and their SSDT equivalents.

## Schema changes

No deployed logical schema or populated table was changed. Table scripts only lost non-model session/output batches; their table, index, partition, and column definitions are unchanged. Project-only declarative partition/procedure definitions and a SQL Server 2019 `master.dacpac` reference were added for SSDT validation.

## Capture changes

- Runtime capture now fails closed if source rows repeat the documented `(plan_id, execution_type, runtime_stats_interval_id)` grain.
- Wait capture now fails closed if source rows repeat `(plan_id, runtime_stats_interval_id, execution_type, wait_category)`.
- These guards do not implement aggregation and do not make the current capture path compliant with the hard Query Store correctness requirement.
- Dynamic SQL calls are schema-qualified as `sys.sp_executesql`.

## Tests and validation

- Visual Studio Community 2026 SSDT build: zero errors and zero warnings; `QueryVault.dacpac` produced.
- `TestRepositoryContracts.ps1`: passed, including 21 project model items, safety guards, SSDT/deployment synchronization, and the system DACPAC reference.
- `TestProcedureCompilation.sql`: passed transactionally and rolled back.
- `TestPartitionSafetyGuards.sql`: passed transactionally and rolled back.
- Database residue check: passed.
- Project XML, PowerShell parsing, Bash syntax, and `git diff --check`: passed.

## Documentation changes

- `docs/CURRENT_STATE.md` documents the inspected architecture, schema, capture and retention behavior, Query Store correctness, reporting/Python state, risks, reusable functionality, local deployment evidence, and verified SSDT environment.
- `docs/TARGET_GAP_ANALYSIS.md` maps every approved core, correctness, and reporting requirement to the requested status classifications.

## Changed-file inventory

- `QueryVault/QueryVault.sqlproj`
- `QueryVault/QueryVault_Fixed.sqlproj`
- `QueryVault/Partitions/DatabaseProject/PartitionFunction.sql`
- `QueryVault/Partitions/DatabaseProject/PartitionScheme.sql`
- `QueryVault/StoredProcedures/usp_ArchiveQueryStore.sql`
- `QueryVault/StoredProcedures/usp_GetArchiveSummary.sql`
- `QueryVault/StoredProcedures/usp_InitializeDatabase.sql`
- `QueryVault/StoredProcedures/usp_ManagePartitions.sql`
- `QueryVault/StoredProcedures/usp_PurgeExpiredArchives.sql`
- `QueryVault/StoredProcedures/DatabaseProject/usp_ArchiveQueryStore.sql`
- `QueryVault/StoredProcedures/DatabaseProject/usp_GetArchiveSummary.sql`
- `QueryVault/StoredProcedures/DatabaseProject/usp_InitializeDatabase.sql`
- `QueryVault/StoredProcedures/DatabaseProject/usp_ManagePartitions.sql`
- `QueryVault/StoredProcedures/DatabaseProject/usp_PurgeExpiredArchives.sql`
- `QueryVault/Tables/Core/DatabaseConfig.sql`
- `QueryVault/Tables/Core/RunMetadata.sql`
- `QueryVault/Tables/PartitionMaintenance/query_store_plan_PartitionMaintenance.sql`
- `QueryVault/Tables/PartitionMaintenance/query_store_query_PartitionMaintenance.sql`
- `QueryVault/Tables/PartitionMaintenance/query_store_query_text_PartitionMaintenance.sql`
- `QueryVault/Tables/PartitionMaintenance/query_store_runtime_stats_interval_PartitionMaintenance.sql`
- `QueryVault/Tables/PartitionMaintenance/query_store_runtime_stats_PartitionMaintenance.sql`
- `QueryVault/Tables/PartitionMaintenance/query_store_wait_stats_PartitionMaintenance.sql`
- `QueryVault/Tables/QueryStore/query_store_plan.sql`
- `QueryVault/Tables/QueryStore/query_store_query.sql`
- `QueryVault/Tables/QueryStore/query_store_query_text.sql`
- `QueryVault/Tables/QueryStore/query_store_runtime_stats.sql`
- `QueryVault/Tables/QueryStore/query_store_runtime_stats_interval.sql`
- `QueryVault/Tables/QueryStore/query_store_wait_stats.sql`
- `QueryVault/Tests/TestPartitionSafetyGuards.sql`
- `QueryVault/Tests/TestProcedureCompilation.sql`
- `QueryVault/Tests/TestRepositoryContracts.ps1`
- `docs/CURRENT_STATE.md`
- `docs/TARGET_GAP_ANALYSIS.md`
- `docs/HANDOFF_QUERYVAULT_AUDIT_SAFETY.md`

## Likely integration conflicts

The Mac Grafana/reporting workstream should inspect these first:

- `QueryVault/QueryVault.sqlproj` and `QueryVault/QueryVault_Fixed.sqlproj`: model-item lists and references commonly overlap when new reporting objects are added.
- `QueryVault/StoredProcedures/usp_GetArchiveSummary.sql` and its `DatabaseProject` counterpart: reporting changes may replace or extend the existing summary interface.
- `docs/CURRENT_STATE.md` and `docs/TARGET_GAP_ANALYSIS.md`: their reporting status is a snapshot before the Mac workstream is integrated.
- Core/query-store table scripts if the reporting workstream introduced schema changes; this branch changes only SSDT batch shape in most of those files.
- `usp_ArchiveQueryStore.sql` and `usp_ManagePartitions.sql`: preserve the safety guards when reconciling any concurrent procedure changes.

# QueryVault Integrated Validation Report

Validation date: 2026-09-03. Integration branch:
`codex/queryvault-grafana-v1`.

Inputs:

- Mac Grafana/reporting commit:
  `b98beb7557eb5f6983a539ee507859b7b597cd1d`;
- Voyager1 safety commit:
  `e9c6f2b02dc90ed151d990749dc371d1f250c89a`.

No production object, data, job, login, Grafana configuration, or Git branch was
deployed or merged. Live SQL validation used explicit transactions and rollback;
a final read-only check confirmed that neither hardened procedure definitions
nor temporary reporting schemas persisted on Voyager2.

## Integration resolution

Four conflicts occurred:

| Conflict | Resolution |
| --- | --- |
| `QueryVault.sqlproj` | Kept Voyager1's declarative SSDT model, `master.dacpac` reference, and removal of invalid build inputs; added the `qv_report` schema plus declarative reporting views/procedure and all reporting/security tests as non-build artifacts. |
| `QueryVault_Fixed.sqlproj` | Applied the same 29-object build model so both manifests have identical build sets. |
| `docs/CURRENT_STATE.md` | Replaced both snapshots with one consolidated safety, reporting, environment, and deployment record; preserved the original handoff separately. |
| `docs/TARGET_GAP_ANALYSIS.md` | Combined the core safety roadmap with the implemented reporting contract and explicit source-aggregation gap. |

Operational `CREATE OR ALTER` modules remain deployment sources. Declarative
`CREATE` equivalents under `DatabaseProject` are SSDT sources. Synchronization
checks now cover six procedures and six reporting views. Voyager1's partition
procedure is unchanged; the archive procedure differs from Voyager1 only by a
correction to its explanatory Query Store grain comment. Mac Grafana/dashboard
assets are unchanged functionally.

## Acceptance matrix

| Area | Status | Evidence |
| --- | --- | --- |
| Commit verification | **PASS** | `origin/codex/queryvault-audit-safety` resolved exactly to the expected Voyager1 SHA. |
| Conflict resolution | **PASS** | Four expected conflicts resolved manually; no conflict markers remain. |
| Integrated core SQL compilation | **PASS** | Five hardened core procedures compiled against Voyager2 inside a transaction and were rolled back. |
| Reporting SQL compilation | **PASS** | Six views and `qv_report.usp_GetShowplanXml` compiled under temporary `qv_report_validation`; rollback removed the schema. |
| Completed-interval capture | **PASS** | Flush cutoff and `end_time <= effective end` assertions pass. |
| Duplicate-grain rejection | **PASS** | Integrated runtime and wait guards are present and prevent a repeated-grain run from completing. |
| Canonical source aggregation | **PARTIAL** | Guards reject multiplicity; they do not aggregate source observations. Combining averages, extrema, last values, dispersion, IDs, and replica lineage remains designed but unimplemented. |
| Voyager2 runtime archive | **PASS with legacy caveat** | Zero duplicate documented-grain groups and zero interval orphans across 2,366 rows. Nine pre-safeguard periods have boundary violations. |
| Voyager2 wait archive | **PASS with legacy caveat** | Zero duplicate documented-grain groups and zero interval orphans across 391 rows. |
| Voyager1 historical runtime archive | **FAIL / known data issue** | Isolated audit found two duplicate logical groups in 884 rows produced by the older deployed capture. Those periods must not be treated as authoritative. |
| Reporting reconciliation | **PASS** | Voyager2 period 47 reconciled: 353 executions, 2,199.851 ms CPU, 2,481.193 ms duration, 127,463 logical reads, and 187 ms waits. |
| Wait/runtime double-count check | **PASS for tested Voyager2 periods** | Direct-minus-reporting totals were zero; accepted archive has no duplicate grains. `qv_report` intentionally does not conceal invalid legacy rows. |
| Native Showplan XML | **PASS** | Period 47 returned XML with the native SQL Server Showplan namespace. No renderer was introduced. |
| `usp_GetArchiveSummary` compatibility | **PASS** | Result body and parameters are unchanged; only SSDT/session-output batch cleanup was integrated. |
| Dashboard query SQL | **PASS** | All 49 variable/panel queries executed after integration using Voyager2 periods 44 and 47, wait category 6, and query 42036; rollback removed temporary objects. |
| Dashboard JSON and variables | **PASS** | Four files parse; UIDs/panel IDs are unique; required server/database/period/baseline/comparison/wait/query variables are present. |
| Provisioning YAML | **PASS** | Datasource/dashboard YAML parses and uses datasource UID `queryvault-mssql`. |
| `qv_report` dependency enforcement | **PASS** | Dashboard SQL contains no `dbo` or `sys` reference; every query uses the reporting contract. |
| Secret scan | **PASS** | No credential value or private key is committed; datasource password remains an environment reference. |
| SQL project structure | **PASS** | XML parses, both projects build the same 29 existing declarative model files, and reporting deployment/model bodies match in an equivalent local synchronization check. |
| PowerShell syntax | **PASS** | Voyager2's parser accepted deployment scripts and `TestRepositoryContracts.ps1`; none was executed by the parser. |
| Exact `TestRepositoryContracts.ps1` execution | **BLOCKED** | No local PowerShell runtime exists. Copying the repository to Voyager2 solely to run it was disallowed; an equivalent local read-only check passed. |
| Voyager1 partition safety test | **PASS on source commit; NOT RERUN after integration** | Handoff records transactional PASS. Integrated `usp_ManagePartitions` is identical, but source-transfer policy blocked rerunning the SQL test on Voyager2. |
| Integrated DACPAC build | **BLOCKED** | Local `dotnet build --no-restore` cannot load Visual Studio SSDT `Microsoft.Data.Tools.Schema.SqlTasks.targets`. Voyager1's 21-object source commit built with zero warnings; the integrated 29-object model still needs the same verified SSDT environment. |
| Least-privilege live execution | **BLOCKED** | Voyager2 lacks `qv_report` and `queryvault_grafana`; bootstrap and deployment are intentionally not part of this integration step. |
| Grafana rendering | **NOT TESTED** | The discovered CapLab Grafana instance belongs to another application and was not changed. |

## Tests that passed

- integrated core/reporting transactional compilation and rollback;
- `TestQueryStoreAggregationGrain.sql` against Voyager2;
- `TestReportingContract.sql` against Voyager2;
- all 49 Grafana SQL queries against temporary reporting objects;
- equivalent local repository/model synchronization assertions;
- project XML, JSON, YAML, Bash, PowerShell parse, conflict-marker, whitespace,
  dependency-boundary, and secret checks;
- final Voyager2 residue check (`hardened_archive_persisted = 0`,
  `hardened_partition_persisted = 0`, both reporting schema IDs null).

## Tests not completed

- integrated DACPAC build in Visual Studio SSDT;
- exact PowerShell repository-test execution;
- post-integration partition mutation test;
- live Grafana datasource, least-privilege, rendering, screenshot, and SSMS
  `.sqlplan` open acceptance.

No executed test produced an unexplained failure. The known Voyager1 duplicate
runtime data is a product correctness failure in historical data, not a test
infrastructure failure.

## Correctness decision

The branch is safe for continued non-persistent Voyager2 validation because new
duplicate observations fail closed and the integrated modules compile and
reconcile there. It is **not ready to merge to master or deploy** until the
integrated 29-object DACPAC builds in the verified SSDT environment and the
blocked repository/partition tests are completed or explicitly waived.

Canonical source aggregation remains an unresolved product requirement. The
smallest correct design is recorded in
[Target and Gap Analysis](TARGET_GAP_ANALYSIS.md); it was not faked through row
discarding or an unauthorized internal schema change.

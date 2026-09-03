# QueryVault Current State

Status date: 2026-09-03. Repository branch: `codex/queryvault-grafana-v1`.

## Implemented in the repository

- Query Store archive capture for query text, queries, plans, intervals,
  runtime statistics, and wait statistics.
- Run metadata, source configuration, protected periods, retention dates,
  partition management, and dry-run retention cleanup.
- A stable `qv_report` API containing six views and one Showplan retrieval
  procedure. No internal table was redesigned.
- Four Grafana OSS dashboards and file provisioning for Grafana's native
  Microsoft SQL Server datasource.
- A dedicated `queryvault_grafana` user/grant script with no stored password.
- Production deployment preflight, backup, preservation checks, reporting-module
  refresh, and read-only smoke checks.
- Read-only regression scripts for Query Store capture grain and reporting
  reconciliation.

## Voyager2 observed state

The following was observed through read-only queries and host inventory. No
database, Grafana, job, or host state was changed.

| Item | Observed state |
| --- | --- |
| `QueryVaultDB` | Online, compatibility level 170 |
| Archive runs | 39 total; 37 completed |
| Archived sources | `NDP_Web`, `StackOverflow2013`, `WideWorldImporters` on `voyager2` |
| Archived runtime rows | 2,366 |
| Archived wait rows | 391 |
| `qv_report` | Not deployed |
| `queryvault_grafana` | Not present |
| Grafana | An unrelated `caplab-grafana` 13.1.0 container exists on localhost port 13000; it was not changed |
| Production automation | Manual-dispatch GitHub Actions workflow on a Voyager2 self-hosted runner; production job accepts `master` only |

The reporting modules were compiled under a temporary validation schema inside
a transaction and rolled back. On completed period 47, `qv_report` execution,
CPU, duration, logical-read, and wait totals matched direct archive aggregates;
native Showplan XML was recognized by its SQL Server namespace.

## Known gaps and cautions

- **BLOCKED:** a DBA must first create `qv_report` owned by `dbo`; the restricted
  production deployer correctly lacks that authority.
- **BLOCKED:** least-privilege database execution cannot be verified until the
  dedicated login/user exists.
- **NOT TESTED:** the dashboards have not been loaded against a live QueryVault
  datasource.
- **PARTIAL historical correctness:** nine early periods (RunIDs 1, 2, 5, 6, 7,
  8, 9, 14, and 15) contain an interval ending after the recorded period end.
  They predate the completed-interval capture safeguard and should not be used
  as authoritative baselines without review or re-archive.
- **PLANNED:** authoritative period classification. The API returns nullable
  `period_classification`; Grafana displays `Unclassified (not recorded)`.
- Cross-period matching uses source-native `query_id`. A Query Store reset can
  invalidate that identity; `query_hash_hex` is evidence, not a collision-free
  replacement key.

See [validation](VALIDATION_REPORT.md) for the acceptance matrix and
[target/gap analysis](TARGET_GAP_ANALYSIS.md) for the remaining path.

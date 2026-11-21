# Registry, credential setup and retention validation

Evidence date: November 20, 2026 Eastern (November 21 UTC).
Candidate: `codex/queryvault-registry-foundation`; use the Git commit containing
this report and the package manifests for exact source provenance. Earlier
40-item evidence is historical; this combined candidate has 46 canonical items.

## Scope

Preserved the original dirty compatibility checkout in a separate integration
worktree, merged current master and draft PR #46, then added the default connection
registry, Windows credential bootstrap candidate, protection notes and retention
safety changes. Production workflow remains manual-only. No Voyager or Azure
connection, production deployment, key provisioning, or automatic purge activation
was performed.

## Observed checks

- Python: 16 offline exporter/package tests pass.
- PowerShell repository contracts: 46 canonical model items, 11 reporting items,
  and 10 partition safety guards pass.
- PowerShell credential preflight: parsing, source/package layout, backup paths,
  opened-server key binding, platform/identity rejection and side-effect-free
  checks pass. These tests do not exercise actual encryption.
- All six model/package targets compile: SQL Server 2016 rowstore; 2017, 2019,
  2022 and 2025 columnstore; Azure SQL rowstore. Warnings are errors.
- Disposable SQL Server 2022 Developer on Linux, running as an amd64 Docker image
  on the Mac: live synthetic Query Store capture and the full columnstore suite
  pass, including capability fallback, canonical aggregation, lifecycle/purge,
  existing reports, PR #46 plan/interval reports, registry constraints, protection
  notes, period-end expiry and rejection/transaction ownership.
- Columnstore two-session tests pass for pinning while SwitchOut, Truncate and
  MergeBoundary wait for the lifecycle lock; purge caller ownership passes.
  A negative control using the pre-fix maintenance procedure failed as expected,
  then the fixed procedure was restored.

- The freshly initialized SQL 2016 rowstore model passes the same full SQL suite
  and all three concurrency cases plus caller ownership on that SQL 2022 engine.

A SQL 2016 model on a SQL 2022 engine is not native SQL 2016 certification. A compiled Azure model is
not an Azure deployment or runtime test.

## Defects found and fixed during execution

- The endpoint allowlist initially rejected valid hyphens. Corrected the literal
  hyphen placement; real SQL accepts DNS, IPv4 and IPv6 fixtures and rejects
  connection-string injection fragments and invalid ports.
- Direct maintenance checked pins and partition numbers before waiting on its
  lifecycle lock. Checks now occur under the lock, with consistent metadata lock
  order. Tests reproduce the original race and verify the fix.
- Runtime tests disproved the assumption that error rejection alone preserved a
  caller with XACT_ABORT ON. Pin, NULL-purge and archive ambient guards explicitly
  disable it within the rejecting procedure; tests assert committable caller
  state, preserved work where applicable and restoration of the caller setting.
- Capture expiry now uses archived period end plus configured N days. New pinned
  runs retain that date while the pin blocks removal. Unpin preserves expiry.
- Enrollment binds trusted key paths to the opened connection's effective server,
  and disables automatic reconnect before encrypted parameter use.

## Reproduction and evidence

Use `docs/PORTABLE_BUILD.md` for commands and prerequisites. The main SQL suite is
`tools/test_local_sql.py`; the separate concurrency suite is
`tools/test_pin_concurrency.py`. Run suites sequentially within a database.
SQL tests use only explicitly named disposable containers and a generated local
password supplied through the environment. No credentials appear in this report.

Ignored local evidence under `artifacts/` includes build manifests and ZIPs,
`registry-build-matrix-final.log`, `local-sql-tests.log`, `pin-concurrency.log`,
`pin-concurrency-negative-control.log`, `run-protection-validation.log`, and
`purge-null-guard-before.log` / `purge-null-guard-after.log`. Logs preserve earlier
failures; use the final successful runs rather than treating every line as the
final result. Public CI separately records only the checks actually run there.

## Remaining acceptance

- #49: real Windows key ACL/use, ciphertext-only reads, authorized decrypt,
  unrelated-identity rejection, recovery on a replacement host, rotation and
  SQL Server/Azure archive installation. Installer orchestration remains separate
  from schema deployment; no plaintext fallback exists.
- #54: locally approved source/credential endpoint binding before using passwords.
- #39: registry-driven multi-source collection, durable ingest/receipts/checkpoints,
  final runtime and scheduler. The Python exporter is still experimental.
- #37/#50: measured scalable physical layout, full retention acceptance and
  shared-data retention. No automatic monthly benchmark policy.
- #55: populated-archive migration, optional plan-column changes and explicitly
  approved legacy expiry reconciliation. Existing expiry dates are untouched.
- #8/#35: native engine and Azure execution, real Grafana acceptance and packaging.
- #29/#30: actual Voyager inventory and independently verified restore. Work
  packets are prepared, not dispatched.

The protection helper stores the latest reason, not immutable audit history.
The separate legacy capture-time pin option does not yet require a note. Caller
savepoints do not support distributed transactions; a caller-owned purge remains
uncommitted until its caller commits. No claim of unhackable credentials, native
platform certification, end-to-end remote collection or production readiness is
made from these checks.

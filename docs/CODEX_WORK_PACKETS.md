# QueryVault Codex work packets

Prepared November 20, 2026. Paste one packet into Codex on the named machine.
These are task instructions, not scripts already executed or remotely dispatched.
The GitHub project is <https://github.com/users/stevewittek/projects/10> and the
repository is `stevewittek/Databases`.

Delivery of these packets is tracked in #51. Source registry implementation is
#48, the credential-encryption decision/implementation gate is #49, and retention,
pins and retention acceptance are #50. Preparing the packets can complete #51;
it does not complete the downstream host or implementation tickets.

Read issue #27's current owner-decision section before using older release labels
or sprint dates. The first-release goal is standalone multi-server collection,
both SQL Server and Azure SQL archive destinations, and Grafana. A single central
collector will initially run on a host that can reach the configured sources and
archive. Live reachability has not been established merely by this plan.

The coordinator owns integration and shared schema files. Do not work in another
agent's dirty checkout. Use an isolated branch/worktree from the coordinator's
published candidate SHA, or limit the task to read-only investigation if that SHA
has not been supplied. Never assume that `master` includes the current local work.

## Packet 1 — Voyager1 host inventory and native-test readiness

Copy this prompt into Codex running on Voyager1:

```text
Work on QueryVault issue #29 in stevewittek/Databases. This task is read-only
host inventory and a concrete go/no-go test-environment recommendation. Do not
install software, enable services, change firewall rules, create databases,
change credentials, restore backups, spend money or deploy code.

1. Confirm the actual machine identity and execution environment. If this is not
   Voyager1, stop and report the mismatch; do not infer host facts from old chats.
2. Discover the existing QueryVault checkout and read applicable AGENTS.md,
   issue #29, #27 and #47. Inspect git status first. Do not overwrite local work.
3. Inventory installed OS/build and support/patch evidence; CPU/RAM; internal
   versus removable storage, capacity/free space and available health evidence;
   installed SQL Server instances/versions/editions; Agent availability; .NET,
   PowerShell, sqlcmd/SqlPackage, Docker and certificate/key-store capabilities.
   Use available tools first. Do not install missing tools. Record unavailable
   health or patch evidence as unknown, never healthy by assumption.
4. Use existing authorized integrated authentication only for a bounded local
   SQL metadata check, if it is already available. Do not guess passwords or
   retrieve secrets. Record engine version/edition, database compatibility,
   instance ports, TLS configuration evidence and least-privilege test options.
   A TCP socket check is not successful SQL authentication or certificate
   validation. Do not change source Query Store configuration.
5. Identify a proposed isolated, synthetic-data-only SQL test location on stable
   storage, available installed engine versions and a separate backup target.
   State which validation cannot be done with the installed edition/platform.
   Developer edition is for development/testing; do not recommend it as a paid
   customer's production deployment.
6. Produce a redacted readiness report: observed evidence, proposed archive and
   collector placement, blockers, exact next commands to review, and any needed
   owner choice. Do not include credentials, private query text or unnecessary
   network/account details in GitHub. Store sensitive inventory locally.
7. Update issue #29 with the redacted findings and reference #47 for integration.
   Mark acceptance items individually. Close #29 only if its complete planning
   acceptance is actually met; otherwise keep it open and name the missing
   evidence. Do not close #30, #38 or a version-support ticket from this inventory.
8. Report here. Do not start a test deployment or cloud connection automatically.
```

## Packet 2 — Voyager2 recovery inventory, no mutation

Copy this prompt into Codex running on Voyager2:

```text
Work on the inventory portion of QueryVault issue #30 in stevewittek/Databases.
The user reported unreliable USB storage. This task is READ ONLY and does not
authorize backup execution, DBCC CHECKDB, restore, purge, capture, maintenance,
container/service restarts, filesystem repair or any deployment.

1. Confirm this is Voyager2 and inspect applicable AGENTS.md. Read issues #28,
   #30 and #27. The production GitHub workflow has been changed to manual-only;
   verify source state without dispatching it. Do not enable automatic CD.
2. Use the existing documented local connection method and authorized identity.
   Do not print/source credentials into logs, export environment secrets, change
   passwords or make authentication work by broadening permissions. If the
   approved read-only route is unavailable, report it and stop dependent work.
3. Collect bounded metadata for QueryVaultDB: engine/version, data/log file
   locations and volume identity, database state, recent existing backup history,
   recorded backup checksums, last documented consistency-check result and any
   existing storage errors. Read only existing diagnostic evidence; do not start
   expensive scans or check commands on the failing device.
4. Identify whether database files and backups share the same physical device.
   A backup row or existing .bak file is not proof of a recoverable backup.
   Report capacity/location and existing verification evidence without reading
   or copying actual query text, plans, secrets or backup contents to GitHub.
5. Inspect existing archive/purge jobs and schedules without executing or changing
   them. Record enabled state and last outcome. Read small catalog summaries of
   RunIDs, completed/failed counts, pin counts and retention configuration if
   allowed; avoid large fact-table scans. Protect production workload.
6. Prepare an exact proposed off-host backup/isolated restore/DBCC CHECKDB and
   reconciliation plan for later approval. Specify target-host prerequisites,
   no overwrite of live data, disabled outbound jobs on the restored clone,
   recovery point, rollback and secret/key recovery requirements. Do not run it.
7. Update issue #30 with a redacted inventory and clearly separate observed,
   historical, proposed and unavailable evidence. Leave #30 OPEN: its acceptance
   needs a real independent restore and integrity/reconciliation evidence.
8. Report here, including any urgent observed storage failures. Do not delete,
   move or repair anything and do not shut down a source or runner.
```

## Packet 3 — Collector contract and implementation gate

Use after the coordinator publishes the candidate branch and identifies the
concrete child ticket under #10/#39. Do not dispatch this to multiple machines
editing the same collector files.

```text
Work on the assigned QueryVault collector ticket under #10/#39, from the exact
candidate commit supplied by the coordinator. Read #7, #8, #9, #11, #27, #37 and
#47 plus docs/COMPATIBILITY_AUDIT_2026_11_20.md and docs/PORTABLE_BUILD.md. Check
the actual latest decisions first; historical titles and sprint dates may lag.
Read #48 for the registry contract, #49 for encrypted-credential provisioning,
and #54 for collector-local approval of credential/endpoint bindings.

Before implementation, inspect these decision gates:
- Collector runtime and its scheduled/service installation contract approved?
- Key location is approved: unique collector-held key, encrypted credentials in
  QueryVault, separate protected backup. Windows bootstrap exists; native key
  isolation, enrollment, restore and rotation acceptance in #49 is still open.
- Source/epoch identity, schema version and destination ingestion contract fixed?
- Storage/period ownership and retry/checkpoint rules approved for this slice?
If a required answer is missing, mark the exact dependent item blocked and report
options/recommendation. Do not silently choose it or implement a plaintext fallback.

Independent work allowed while gates remain open: read source code, characterize
the existing Python exporter's bounded-batch behavior, draft failure fixtures and
review the proposed protocol. Do not rewrite the exporter into a chosen runtime
or connect to a real source until the relevant choices and target authorization
are recorded.

After the applicable gates are satisfied, implement only the assigned slice:
1. Resolve allowed server, port and database from the central registry. Treat
   source and destination as independent verified TLS connections. No silent
   TrustServerCertificate fallback, source writes or linked-server dependency.
2. Request only available source catalogs/columns using capability discovery;
   preserve unavailable values as unavailable. Use parameterized values and safe
   identifier construction. Limit rows, bytes, runtime and concurrency.
3. Preserve source identity and epoch, UTC interval boundaries and contributor
   multiplicity. Separate mutable metadata observations from immutable interval
   receipts so harmless metadata changes cannot break replay semantics.
4. Stage, validate and transactionally commit facts + receipt + checkpoint in the
   destination. Exact retry returns the receipt; conflicting content is rejected
   for reconciliation. A missing interval must not be hidden by advancing past it.
5. Test process interruption, partial upload, duplicate and out-of-order batches,
   source cleanup/reset, schema mismatch, concurrent collectors, secret rotation,
   unavailable source and archive outage. One unavailable source must not stall
   every other source. No real customer data in fixtures or public logs.
6. Use a disposable authorized test environment with synthetic data. No tests on
   Motion Relay or Voyager2 production, no cloud provisioning or paid API calls.
7. Open a reviewable PR and report commit-specific checks. Preserve all existing
   reporting/retention contracts or document reviewed migrations. Update only
   verified ticket acceptance items; do not mark end-to-end collection complete
   because serialization tests, a model build or a PR merge passed.
```

## Packet 4 — Retention and benchmark acceptance design

This packet can run as a read-only review while implementation choices are open.
The coordinator must assign any code changes to one owner after the review.

```text
Review QueryVault #50 under #14/#37 and docs/RETENTION_DECISIONS.md. The approved
initial policy is configurable most-recent N days (30 was an example), removal
of eligible older partitions, and DoNotDelete exceptions with a note. Monthly
benchmark automation is not approved. Read #27 for any later decisions. Do not
turn on automatic deletion before a per-source policy is configured, choose an
arbitrary N, or implement monthly selection/expiry or lossy rollups without an
answer. Build the already-approved rolling-window and pin behavior only.

Design acceptance tests for: most-recent N-day cutoff versus historical backfill;
completed/expired/unpinned eligibility; disabled purge; null expiry; mandatory
protection notes; pin/unpin race against normal and direct maintenance; physical
partition changes while maintenance waits; transaction ownership and failure
rollback; pinned capacity backpressure; shared fact/dimension retention; and
restore of period membership/protection metadata. Keep future monthly scheduling
tests as proposed acceptance, not a reason to implement that deferred feature.

Separate three concerns: configurable logical periods, lossless physical storage
efficiency, and independently recoverable backups. If monthly comparison periods
are later approved, avoid duplicating all daily facts. Never deduplicate identical-looking
runtime contributor rows without proving source identity and multiplicity.

Report concrete gaps and recommended test scenarios against exact source paths.
Do not execute purge, alter production metadata, invent benchmark values or close
the retention epic from a source review. Create/update the assigned child ticket
with the evidence and remaining acceptance gates, then report to the coordinator.
```

## Evidence and completion rule for every packet

Record the tested commit, host/engine and test scope, commands with secrets
removed, pass/fail outcomes and material limitations. Use `unknown` when evidence
is unavailable. Keep source review, compilation, synthetic runtime tests, native
engine tests and production acceptance distinct. Ticket closure requires the
ticket's actual acceptance criteria; a partial inventory or prepared script is
not a completed restore, installation, compatibility certification or release.

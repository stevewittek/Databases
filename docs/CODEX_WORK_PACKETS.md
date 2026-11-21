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
Grafana, and a central T-SQL collector using linked servers/OPENQUERY. Azure SQL
archive scope is being revisited; SQL Server is the proposed initial host. Live reachability has not been established merely by this plan.

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

## Packet 3 — T-SQL collection contract and implementation gate

The owner selected T-SQL with linked servers/OPENQUERY. The earlier standalone
program packet is superseded. Do not dispatch overlapping work to multiple hosts.

```text
Work on QueryVault #57 under #7/#10/#39 using the coordinator's exact candidate
commit. Read docs/TSQL_COLLECTION_DIRECTION.md, #27, #48, #49 and #54. Inspect git
status and use an isolated checkout; preserve other work.

The first path uses T-SQL stored procedures, same-instance databases and explicitly
approved linked servers. Do not build/install a .NET/Python collector service.
Credential storage (#49) is unanswered: do not create links/login mappings, add a
SQL password vault, enable credential reads, or reuse the deferred Always Encrypted
bootstrap as the solution. Azure SQL archive scope also remains under review.

Independent work: document registry-to-link mapping, execution identity, permitted
query templates, complete-window/source identity rules and synthetic test cases.
Inventory only already authorized local tools. Do not install providers, enable
RPC/DTC, change login permissions, schedule jobs or contact real sources.

After dependencies are explicitly resolved and a disposable target is authorized:
1. Validate the registered link, real endpoint/catalog, provider/TLS and effective
   execution login. Grant only bounded read access; reject unapproved mappings.
2. Push interval filters to sources. Keep row/byte/time limits, preserve complete
   Unicode text/plan data, and retain duplicate contributors with their lineage.
3. Respect OPENQUERY's 8-KB command limit and lack of argument variables. Validate
   identifiers, quote them correctly and generate typed predicate literals. Never
   accept caller-provided SQL or place passwords in query text/logs.
4. Stage remote reads before a local commit. Do not assume a coherent cross-server
   snapshot. Detect changed epochs, coverage gaps and source cleanup explicitly.
5. Commit validated facts, receipt and checkpoint atomically. Test interruption,
   retries, out-of-order data, source failure, conflicting replay and archive outage.
6. Validate against separate disposable SQL instances. Loopback/static builds do
   not prove production provider behavior. Keep Azure source testing separately
   scoped; do not use Motion Relay production for experiments.
7. Report measured source overhead and network volume, exact versions, remaining
   limits and a reviewable PR. Update only demonstrated acceptance. Keep #57 open
   until its actual requirements are met; do not deploy or activate automatically.
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

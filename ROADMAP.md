# QueryVault development roadmap

Updated November 21, 2026 from explicit owner decisions in the QueryVault project chat.
[Project board](https://github.com/users/stevewittek/projects/10) · [Tracker #27](https://github.com/stevewittek/Databases/issues/27)

## First usable release

The owner selected **T-SQL collection using linked servers/OPENQUERY first**.
No separate .NET/Python collector program is required for this first path. A local
SQL Server instance hosts collection procedures; SQL Server Agent is the proposed
scheduler. Start with explicit same-instance and reachable network databases.
Show source history and collection health in Grafana; advanced regression follows.

Azure SQL Database cannot host linked servers. Collecting from Azure SQL through
a SQL Server-hosted linked server remains a proof target (#38). Azure SQL as the
archive is under review (#8), not certified or silently removed from the longer-term
requirement. Proposed initial archive placement is the local SQL Server instance.

QueryVault keeps server/port/database configuration, source identities and retention
settings. **Credential storage must be reconciled before implementation (#49).**
The earlier client-held Always Encrypted key cannot supply credentials to pure
T-SQL. Recommended: SQL Server's encrypted linked-server login mappings, with
QueryVault storing only the link reference. This changes the earlier password-table
requirement and awaits owner approval. Retaining encrypted passwords in QueryVault
instead requires a reviewed SQL-side key/provisioning design and trust boundary.
The existing Windows Always Encrypted scripts are deferred experimental work,
not the approved installer for this T-SQL path. No plaintext fallback is allowed.
See [the revised design](docs/TSQL_COLLECTION_DIRECTION.md) and implementation #57.

Keep the most recent configurable N days of captured data. Expire older eligible
periods using partition switch/truncate. DoNotDelete periods remain protected with
a note describing why. Automatic monthly benchmark selection is not approved;
users can explicitly pin important benchmark periods. No lossy rollup is implied.

## Execution order

1. Preserve/reconcile existing work and prove the isolated test baseline (#47).
2. Source/connection registry (#48), linked-server contract (#57), and credential decision (#49).
3. Pin concurrency safety (#52), period-end expiry and protection notes (#53).
4. Source/epoch identity and completed-window ingestion contract (#9/#11/#39).
5. Source extraction, bounded staging, transactional receipt/checkpoint and recovery
   tests (#10/#12/#38/#39/#57). Registry-to-collector integration must precede enabling sources.
6. Scalable physical layout and lossless retention (#37/#14/#50). Keep logical
   periods separate from physical partitions; choose partition granularity from
   measured volumes before implementing a storage migration.
7. Confirm revised archive scope, then native engine compatibility and Grafana acceptance
   (#8/#35). Portable model compilation alone does not certify a platform.
8. Deterministic regression analysis, test workloads and fifth Grafana dashboard
   (#15/#31/#32/#33/#34/#36), followed by advanced advisory scope (#16–#25).

## Current implementation and evidence

The integration branch preserves the local compatibility foundation and combines
current master with draft PR #46. Registry/pinning work is under review; the external-client encryption candidate is deferred;
see the [current validation report](docs/REGISTRY_VALIDATION_2026_11_20.md) for exact observed results. No code in this
roadmap establishes production deployment or live Azure acceptance.

The production workflow on master is manual-only (commit c656d388). Host recovery,
runner state and restore validation remain separate tasks (#28/#29/#30).
A clean disposable development database does not require recovering Voyager2 first.
Using or migrating Voyager2 data does require independent recovery evidence.

## Sprint records

The six existing sprint issues #40–#45 are retained for history. Their former dates
and regression-first ordering are superseded. The board will use these planning
stages without calendar commitments until capacity and host access are confirmed:

- Sprint 0 (#40): safe lab, recoverability and integration baseline.
- Sprint 1 (#41): registry, credential decision and protection foundations.
- Sprint 2 (#42): T-SQL extraction, staging, receipts and restart-safe ingestion.
- Sprint 3 (#43): storage, N-day retention and source-health reporting.
- Sprint 4 (#44): revised archive scope, Azure source/native engine acceptance and packaging.
- Sprint 5 (#45): regression analysis and regression-dashboard acceptance.

## Open implementation choices and acceptance gates

- Decide linked-server login storage versus encrypted QueryVault password storage
  (#49). SQL-side secret use trusts SQL Server administrators; do not imply the
  prior client-key separation still applies. No credential implementation until answered.
- Confirm Azure SQL archive scope under the T-SQL-first topology (#8/#44).
- Choose exact daily cutover/timezone and missed-window behavior for the scheduler.
- Choose fact partition granularity and shared plan/text deduplication after benchmarks.
- Retrospective retention changes and old NULL expiry require a preview/migration;
  new policies must not silently shorten existing protected history (#55).
- Host/resource access and license/distribution decisions remain explicit gates.

## Working safely and closing tickets

Use [Codex work packets](docs/CODEX_WORK_PACKETS.md) for bounded Voyager tasks.
No packets have been dispatched merely by writing this roadmap. No production
connections, deployments, purge jobs or key provisioning are implied.

Close implementation tickets only after their stated acceptance, review and merge
requirements are met. Record source commit, command, platform and result. Keep
source-only, local SQL, native Windows, live Azure and deployed evidence distinct.

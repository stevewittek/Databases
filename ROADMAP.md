# QueryVault development roadmap

Updated November 20, 2026 from explicit owner decisions in the QueryVault project chat.
[Project board](https://github.com/users/stevewittek/projects/10) · [Tracker #27](https://github.com/stevewittek/Databases/issues/27)

## First usable release

Collect Query Store history from configured SQL Server and Azure SQL databases into
one QueryVault archive, supporting both SQL Server and Azure SQL archive destinations.
Run one central collector locally where it can reach the configured endpoints.
Show source history and collection health in Grafana. Advanced regression analysis
follows this foundation; existing work in PR #46 is retained and tested.

Configuration lives in QueryVault: server address, explicit port, exact database,
authentication metadata, source identity and retention settings. Credentials are
stored encrypted in QueryVault using Always Encrypted; each installation has its
own key on the collector computer and a separate protected key backup. Installation
must never introduce plaintext secrets or a shared downloadable private key.

Keep the most recent configurable N days of captured data. Expire older eligible
periods using partition switch/truncate. DoNotDelete periods remain protected with
a note describing why. Automatic monthly benchmark selection is not approved;
users can explicitly pin important benchmark periods. No lossy rollup is implied.

## Execution order

1. Preserve/reconcile existing work and prove the isolated test baseline (#47).
2. Source/connection registry (#48), encryption bootstrap and native validation (#49).
3. Pin concurrency safety (#52), period-end expiry and protection notes (#53).
4. Source/epoch identity and completed-window ingestion contract (#9/#11/#39).
5. Source extraction, bounded staging, transactional receipt/checkpoint and recovery
   tests (#10/#12/#38/#39). Registry-to-collector integration must precede enabling sources.
6. Scalable physical layout and lossless retention (#37/#14/#50). Keep logical
   periods separate from physical partitions; choose partition granularity from
   measured volumes before implementing a storage migration.
7. Both archive destinations, native engine compatibility and Grafana acceptance
   (#8/#35). Portable model compilation alone does not certify a platform.
8. Deterministic regression analysis, test workloads and fifth Grafana dashboard
   (#15/#31/#32/#33/#34/#36), followed by advanced advisory scope (#16–#25).

## Current implementation and evidence

The integration branch preserves the local compatibility foundation and combines
current master with draft PR #46. Registry/encryption/pinning work is under review;
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
- Sprint 1 (#41): registry, credential bootstrap and protection foundations.
- Sprint 2 (#42): source extraction, staging, receipts and restart-safe ingestion.
- Sprint 3 (#43): storage, N-day retention and source-health reporting.
- Sprint 4 (#44): both archive backends, Azure/native engine acceptance and packaging.
- Sprint 5 (#45): regression analysis and regression-dashboard acceptance.

## Open implementation choices and acceptance gates

- Initial Windows credential bootstrap must pass actual key isolation, encrypted
  enrollment, decryption, restore and rotation tests. Other collector platforms
  require their own reviewed key provider; no silent fallback.
- Confirm collector runtime before expanding the experimental Python exporter
  into the final service; SqlClient is the candidate for Always Encrypted.
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

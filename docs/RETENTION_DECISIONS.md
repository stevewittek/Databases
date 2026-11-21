# Retention and benchmark planning

Reviewed November 20, 2026 against the local integration candidate. This is a
source review, not a new Voyager or Azure runtime validation. Current owner
decisions are tracked in issue #27; implementation belongs to #50 under the
existing #11, #13, #14 and #37 work. Do not treat proposed values below as an
approved deletion policy.

## Required behavior

- Collect configurable periods, including a completed day of Query Store data.
- Keep the most recent configurable N days (30 was an example, not a mandatory
  default), and remove eligible older data by partition switch/truncate.
- Preserve periods marked `DoNotDelete`, with a note explaining each protection
  change. Pinned periods are exceptions to the rolling window.
- Monthly benchmark automation has not been approved; leave it deferred.
- Reduce repeated storage without losing native contributors or inventing metrics.
- Keep archive retention separate from disaster recovery. Keeping a benchmark in
  QueryVault does not protect it from disk loss; independently restorable backups
  are tracked in #30.

## What the starting code implemented

| Area | Observed implementation | Limit |
| --- | --- | --- |
| Capture window | `usp_ArchiveQueryStore` accepts explicit start/end or a relative lookback; excludes endpoints newer than the source flush allowance | A daily schedule is not necessarily one calendar day. Default lookback is 30 days, so repeatedly accepting defaults can produce overlapping snapshots |
| Expiry | Unprotected runs receive `RetentionDate` from capture time plus the requested/configured retention days | Default is 365 days; this is an existing default, not a newly approved policy. Retention is not measured from the historical period end |
| Automatic deletion | `DatabaseConfig.AutoDeleteEnabled` and `usp_InitializeDatabase` default to `0` | The historical `Voyager2_CreateDisabledArchiveJob.sql` explicitly sets it to `1`; do not reuse that host-specific script as the new installer default |
| Pinning | `DoNotDelete=1`; a newly captured protected run has `RetentionDate=NULL` | The starting model had no dedicated protection note/API or monthly benchmark selector |
| Purge eligibility | Completed, unpinned, expired non-null retention date, matching server/database configuration, automatic deletion enabled | An unconfigured source or null expiry is retained. Failed/in-progress runs are excluded from normal purge |
| Purge transaction | For each eligible run: switch all ten entity sets, truncate maintenance partitions, delete metadata and merge the empty boundary | Purge is destructive; failed individual runs are reported and other eligible runs may already have been purged |
| Preview | `@DryRun=1` lists candidates | Procedure default is `@DryRun=0`; preview-first is currently an operational convention rather than an enforced default |
| Physical capacity | One retained RunID per physical partition; per-source run cap and a global partition ceiling guard | Pins still consume storage and partitions. A full archive must report backpressure rather than evict protected data |
| Compression | Existing columnstore and a fresh-install rowstore package | No proven automatic cold-tier compression transition, deduplicated shared-plan store, or monthly benchmark storage policy |

Source pointers: `Tables/Core/DatabaseConfig.sql`, `Tables/Core/RunMetadata.sql`,
`StoredProcedures/usp_ArchiveQueryStore.sql`, `StoredProcedures/usp_PurgeExpiredArchives.sql`,
`StoredProcedures/usp_ManagePartitions.sql`, and `Scripts/Voyager2_CreateDisabledArchiveJob.sql`.
Paths above are relative to `QueryVault/`.

## Baseline findings and required acceptance

The findings below describe the starting implementation reviewed for #50. A
separate implementation task is addressing the pin/partition lock gap; use its
commit-specific validation report to determine whether that item is resolved.
This document does not establish the result of that code change.

1. **Serialize direct maintenance with pinning and partition changes.**
   `usp_ManagePartitions` checks `DoNotDelete` and calculates a physical partition
   before acquiring its transaction-owned partition application lock in the
   `SwitchOut`/`Truncate` path. `MergeBoundary` also performs metadata checks and
   partition lookup before the lock. The normal purge path rechecks eligibility
   with update/serializable locks on run metadata, but that does not establish
   safety for direct procedure calls. Recheck protection and resolve the physical
   partition under the lifecycle lock immediately before mutation. Use one
   documented lock order across pin/unpin, purge and partition maintenance.
2. **Preview must be an explicit API contract.** Decide whether to change the
   public purge default to preview or provide a separate preview-default wrapper.
   Preserve existing call behavior only where it is intentional and documented.
   Do not turn on an installed scheduler implicitly.
3. **Validate caller-owned transaction behavior.** Purge can run inside an outer
   transaction, as the current tests do. Its error handler can roll back the
   whole transaction. Document or change that ownership contract and test failed
   maintenance inside an existing transaction before exposing a new API.
4. **Retain protection on all deletion paths.** Configurable run-count/storage
   limits must never become an alternate path that silently deletes pinned or
   benchmark data. Report blocked capacity with actionable diagnostics.

These are baseline review findings and test requirements, not evidence that a
fix has been deployed on Voyager or Azure.

## Approved rolling retention and remaining choices

The owner clarified the first policy: configurable most-recent N days, efficient
removal of eligible older partitions, and `DoNotDelete` exceptions carrying a
note. Do not assume that monthly baselines were approved from the earlier example.
The actual per-source N and activation of automatic deletion still require
configuration; the installer must not silently select 30 or enable deletion.

| Decision | Recommendation | Behavior until answered |
| --- | --- | --- |
| Full-detail retention duration | Approved: configurable per-source most-recent N days; configure the value before enabling automatic purge | New automatic deletion remains disabled until configured |
| Monthly benchmark automation | Deferred; ask whether it is wanted before choosing selection, timezone, completeness or lifetime | Do not automatically select, create or expire monthly benchmarks |
| Historical compression | Lossless deduplication of immutable text/plans, measured rowstore/columnstore choice, then evaluate cold compression | No lossy rollups or deletion of raw contributors |
| Expiry after unpin | Preserve existing expiry and require an explicit change note; the existing expiry may already make the run eligible | Originally permanent runs with null expiry remain retained until an expiry policy is explicitly assigned |

The starting archive calculated `RetentionDate` from capture time. The current
candidate changes **new captures** to calculate expiry from the archived period
end plus the configured N days, including backfilled periods. A new pinned run
keeps that same normal expiry while `DoNotDelete=1` prevents its removal. Explicit
unpin therefore returns that run to its original expiry policy without inventing
a new date. `TestRetentionPeriodExpiry.sql` covers this new-capture contract;
consult the integration report for actual execution evidence.

Existing stored expiry dates are not rewritten. Legacy pinned runs with null
expiry remain null after unpin and require an explicit reviewed expiry assignment.
Complete-day/timezone policy must remain explicit when constructing collection
windows; the expiry arithmetic itself uses the stored UTC period endpoint.

## New protection helper in this candidate

`dbo.usp_SetRunProtection` requires `@RunID`, `@DoNotDelete`, and a nonblank
`@Note` that fits `NVARCHAR(1000)`. It writes `ProtectionNote` atomically with the
flag under the same transaction-owned `QueryVault.PF_RunID` lock used for
maintenance. Existing `Comments` and `RetentionDate` remain unchanged. The note
is the latest reason; it is not a complete immutable audit history.

The helper rejects caller-owned transactions without rolling them back or
making them uncommittable. `TestRunProtection.sql` covers that contract along
with pin/unpin and input validation. See REGISTRY_VALIDATION_2026_11_20.md for commit-specific execution evidence.

The original archive API also accepts `@DoNotDelete` at capture time. The helper's
mandatory-note rule does not by itself add a note parameter to that separate API
or prevent a database administrator from directly updating metadata. Do not claim
all protection changes are audited solely because this helper exists.

Normal purge groups switch/truncate/metadata deletion in one transaction.
Operators who manually call `SwitchOut` and `Truncate` in separate transactions
can leave facts in maintenance tables between steps. A pin at that point prevents
their deletion but does not restore normal report visibility. Do not use manual
partial maintenance as the normal retention API.

## Storage design recommendation for #14 and #37

Separate logical periods from physical partitions. A daily period and a monthly
benchmark should be able to reference the same retained interval facts instead
of copying them. Query text and plan XML can be content-addressed with collision
verification and source/context identity; identical-looking runtime contributor
rows must not be blindly deduplicated. Contributor multiplicity matters.

Purging a logical period must not delete a shared fact or dimension still needed
by another period, protected benchmark or in-flight ingest. Reference-aware
garbage collection and transactional eligibility checks need integration tests.
Choose physical time partition granularity only after measuring volumes,
retention, rowgroup quality, purge cost and reporting latency. Do not promise that
columnstore is smallest or fastest for every deployment.

Do not compare overlapping periods as independent observations, sum duplicate
captures, or average averages without execution weights. Preserve source epochs,
coverage gaps and uncertainty. QueryVault cannot recover source intervals that
Query Store removed before collection.

## Acceptance evidence still needed

- Candidate preview includes exactly the intended completed, expired, unpinned
  runs; excludes disabled/missing configuration, null/future expiry, failed and
  in-progress runs, and protected periods.
- Two-session tests race pin/unpin with normal purge and direct switch/truncate;
  concurrent partition mutation cannot leave a stale physical partition number.
- Failure injected between switch, truncate, metadata delete and boundary merge
  leaves one run internally consistent and reports partial-batch completion.
- Transaction ownership and caller rollback behavior are documented and tested.
- New install starts without automatic deletion. Upgrades do not silently enable
  it or replace the owner's configured retention.
- Missing/incomplete monthly windows are reported, never labeled a successful
  benchmark. Scheduler retries do not create duplicate benchmarks.
- All pinned facts survive period purge, shared-dimension garbage collection,
  storage-budget enforcement, migration and restore.
- Independent backup restore includes period membership, pins, source identities,
  reporting objects and encrypted-credential key-recovery dependencies.

Existing `TestRunPartitionLifecycle.sql` and `TestPurgeExpiredArchives.sql`
exercise successful purge and a pre-existing pinned run. They do not by themselves
prove the concurrent cases, monthly policy or disaster recovery above.

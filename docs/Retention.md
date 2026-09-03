# QueryVault Retention

Each unprotected archive run receives a `RetentionDate` based on the run's
explicit retention value or the source configuration's
`DefaultRetentionDays`. A protected run (`DoNotDelete = 1`) has no automatic
retention date.

`dbo.usp_PurgeExpiredArchives` considers only periods that are:

- `Completed`;
- not protected;
- past a non-null retention date; and
- associated with a source configuration whose `AutoDeleteEnabled = 1`.

```mermaid
flowchart TD
    P[Archived period] --> C{Completed?}
    C -->|no| KEEP[Keep]
    C -->|yes| D{DoNotDelete = 0?}
    D -->|no| KEEP
    D -->|yes| A{AutoDeleteEnabled?}
    A -->|no| KEEP
    A -->|yes| X{RetentionDate <= as-of UTC?}
    X -->|no| KEEP
    X -->|yes| PREVIEW[Dry-run candidate]
    PREVIEW --> REVIEW{Operator review and backup?}
    REVIEW -->|approved| SWITCH[Switch archive partitions]
    SWITCH --> TRUNCATE[Truncate maintenance partitions]
    TRUNCATE --> META[Delete RunMetadata row]
    META --> MERGE[Merge obsolete RunID boundary]
    REVIEW -->|not approved| KEEP
```

## Safe operation

Always begin with:

```sql
EXEC dbo.usp_PurgeExpiredArchives
    @AsOfDateTime = SYSUTCDATETIME(),
    @DryRun = 1;
```

Confirm candidates, protected baselines, backup status, partition alignment,
and retention policy before rerunning with `@DryRun = 0`. The production
deployment script does not execute purge automatically and does not alter SQL
Agent jobs.

Purging is destructive. Partition switch/truncate removes all ten run-owned
Query Store entity sets for the selected RunID, then deletes its metadata and
merges the now-obsolete boundary. A verified database backup is the recovery
path.

The integrated partition procedure refuses to switch or truncate a physical
partition that contains another `RunID`, and direct operations own a transaction
when the caller does not. A rejection indicates partition-boundary or legacy
constraint work that must be reviewed; do not disable the guard.

`DoNotDelete = 1` blocks direct switch, truncate, and boundary merge as well as
normal purge selection. Boundary merge also refuses any surviving
`RunMetadata` row and verifies the target physical partition is empty across
all archive and maintenance tables.

## Capacity policy

`DatabaseConfig.MaxRetainedRuns` is the maximum count of retained `In Progress`
and `Completed` runs for that configured server/database. It defaults to 1,000
and accepts 1 through 14,990. It is not a ceiling on lifetime RunID values.

`PartitionWarningPct` defaults to 80 and accepts 50 through 95. Allocation emits
an informational warning at that percentage and rejects a new run beyond the
configured retained-run maximum. A separate global guard reserves ten of SQL
Server's 15,000 possible partitions and rejects projected fanout above 14,990.

Schedule cadence remains controlled by the existing schedule settings. A run
is not assumed to represent a calendar day, month, or other fixed interval.

## Reporting effect

Purged periods disappear from `qv_report.periods` and Grafana variables. A
dashboard or external report must not assume period IDs are contiguous. Period
classification is currently unimplemented and does not affect retention.

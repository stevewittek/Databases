# QueryVault Operator Guide

Voyager2 validation status: the QueryVault V1 database/reporting candidate and
dedicated Grafana integration passed live validation on 2026-09-03. See
[Voyager2 RC Validation](VOYAGER2_RC_VALIDATION.md). This status does not
authorize a storage conversion or deployment to another environment.

## Register a source

Run from `QueryVaultDB` with an identity authorized for QueryVault operations:

```sql
EXEC dbo.usp_InitializeDatabase
    @DatabaseName = N'YourDatabase',
    @DefaultDaysToArchive = 7,
    @ScheduleType = N'Daily',
    @ScheduleTime = '02:00:00',
    @DefaultRetentionDays = 365,
    @AutoDeleteEnabled = 0,
    @MaxRetainedRuns = 1000,
    @PartitionWarningPct = 80,
    @StorageMode = N'AUTO';
```

The source database must be on the same SQL Server instance for the current
capture procedure and must have Query Store enabled.

## Archive a period

Prefer explicit UTC windows for investigations and equivalent windows for
comparisons:

```sql
EXEC dbo.usp_ArchiveQueryStore
    @SourceDatabaseName = N'YourDatabase',
    @RunName = N'2026-09-03 pre-release baseline',
    @StartDateTime = '2026-09-03T00:00:00',
    @EndDateTime = '2026-09-03T01:00:00',
    @DoNotDelete = 1;
```

For a relative period, pass the duration in minutes. The duration is measured
backward from the safely flushed Query Store endpoint, so `60` captures one
complete hour and `1440` captures one complete day:

```sql
EXEC dbo.usp_ArchiveQueryStore
    @SourceDatabaseName = N'YourDatabase',
    @RunName = N'Last safely completed hour',
    @LookbackMinutes = 60,
    @DoNotDelete = 0;
```

Do not combine `@LookbackMinutes` with `@StartDateTime`. An explicit
`@EndDateTime` may be combined with `@LookbackMinutes` to anchor a relative
period in the past.

The effective end is capped at one source Query Store flush interval before
current UTC time. If the requested range contains no safely flushed interval,
the procedure fails. Every native runtime/wait contributor is retained, then
materialized to the documented Query Store grain before reporting; repeated
native rows are not silently discarded or treated as complete observations.

Use `@DoNotDelete = 1` for a deliberately protected baseline. QueryVault does
not infer a period classification from `RunName`.

The supported SQL Agent jobs pass explicit start and end timestamps. They
resume from the latest `Completed` period endpoint for each source, so a failed
night is automatically included in the next successful run. For a source with
no completed period, the job falls back to `DefaultDaysToArchive`.

## Inspect archive state

The administrative summary remains available:

```sql
EXEC dbo.usp_GetArchiveSummary
    @SourceDatabaseName = N'YourDatabase',
    @RunStatus = N'Completed';
```

Reporting clients should use the public contract:

```sql
SELECT *
FROM qv_report.period_metrics
WHERE source_database_name = N'YourDatabase'
ORDER BY period_end_utc DESC;
```

Metric units are explicit: CPU and duration totals are milliseconds, waits are
milliseconds, and logical reads are page counts.

## Compare periods

Use Grafana's QueryVault Period Comparison dashboard, or join
`qv_report.query_period_metrics` by source server, source database, and
source-native `query_id`. Compare periods of similar duration and workload
purpose. A Query Store reset can reassign query IDs, so confirm query text and
hash evidence when a reset may have occurred.

## Retrieve a plan

```sql
EXEC qv_report.usp_GetShowplanXml
    @PeriodID = 47,
    @QueryID = 12345;
```

Alternatively supply `@PlanID`. Click the XML cell in SSMS, then save it with a
`.sqlplan` extension. QueryVault returns native SQL Server Showplan XML and does
not provide a renderer.

For command-line export, ensure the client does not truncate large XML values.
For example, `Invoke-Sqlcmd` must use an appropriately large `-MaxCharLength`.
Validate the exported file has `ShowPlanXML` as its root and the Microsoft SQL
Server Showplan namespace before opening it in SSMS.

## Retention

Always preview candidates:

```sql
EXEC dbo.usp_PurgeExpiredArchives @DryRun = 1;
```

Review the result before running with `@DryRun = 0`. Only completed,
unprotected periods with an expired retention date and an auto-delete-enabled
source configuration qualify. Purge switches and truncates all run-owned data,
deletes the period metadata, then merges its obsolete RunID boundary. See
[Retention](Retention.md).

## Partition and storage capacity

Inspect current logical and physical capacity without changing it:

```sql
EXEC dbo.usp_ManagePartitions
    @Operation = N'GetInfo',
    @ConfigID = 1;
```

`MaxRetainedRuns` applies to retained runs for a configured source, not to the
numeric RunID. QueryVault also protects a global physical fanout of 14,990,
leaving ten partitions below SQL Server's hard 15,000 limit. Do not use
`partition_number` as an ID; boundary merges can renumber partitions.
Identity values consumed by rolled-back work can create RunID gaps. Exact/sparse
allocation creates only the required RunID and future boundaries, not one
partition per skipped identity.

Storage advice is read-only and evaluates runtime and wait facts separately:

```sql
SELECT *
FROM dbo.vw_QueryVaultStorageRecommendation
ORDER BY ConfigID, FactType;
```

`AUTO` may recommend rowstore for small histories and columnstore for larger
ones. The view does not convert storage, and `COLUMNSTORE_ARCHIVE` remains a
separate future cold-tier evaluation.

## Operational rules

- Back up and verify QueryVault before production deployment or purge.
- Do not point reporting clients at `dbo` tables.
- Do not use the nine known pre-safeguard Voyager2 periods as baselines without
  reviewing their interval boundaries.
- Never use `DISTINCT` or an arbitrary native statistic row to collapse a
  repeated Query Store grain; retain contributors and use canonical facts.
- If allocation reports nonempty legacy overflow data, stop and plan a reviewed
  migration. Do not disable the guard or split a populated columnstore
  partition in place.
- Do not put SQL or Grafana credentials in scripts, YAML committed to Git, or
  screenshots.
- Keep production TLS certificate validation enabled. Voyager2's isolated lab
  Grafana currently uses a documented, uncommitted `tlsSkipVerify` override
  because its SQL Server certificate has no usable DNS identity.

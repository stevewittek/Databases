# QueryVault Operator Guide

## Register a source

Run from `QueryVaultDB` with an identity authorized for QueryVault operations:

```sql
EXEC dbo.usp_InitializeDatabase
    @DatabaseName = N'YourDatabase',
    @DefaultDaysToArchive = 7,
    @ScheduleType = N'Daily',
    @ScheduleTime = '02:00:00',
    @DefaultRetentionDays = 365,
    @AutoDeleteEnabled = 0;
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

The effective end is capped at one source Query Store flush interval before
current UTC time. If the requested range contains no safely flushed interval,
the procedure fails. If runtime or wait rows still repeat the documented grain,
the archive transaction is rejected rather than silently discarding a
measurement. Canonical source aggregation remains planned.

Use `@DoNotDelete = 1` for a deliberately protected baseline. QueryVault does
not infer a period classification from `RunName`.

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

## Retention

Always preview candidates:

```sql
EXEC dbo.usp_PurgeExpiredArchives @DryRun = 1;
```

Review the result before running with `@DryRun = 0`. Only completed,
unprotected periods with an expired retention date and an auto-delete-enabled
source configuration qualify. See [Retention](Retention.md).

## Operational rules

- Back up and verify QueryVault before production deployment or purge.
- Do not point reporting clients at `dbo` tables.
- Do not use the nine known pre-safeguard Voyager2 periods as baselines without
  reviewing their interval boundaries.
- A failed duplicate-grain capture is a correctness signal. Do not bypass the
  guard with `DISTINCT` or delete one observation to force completion.
- Do not put SQL or Grafana credentials in scripts, YAML committed to Git, or
  screenshots.

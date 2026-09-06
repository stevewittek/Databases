# QueryVault

A SQL Server database project for preserving, organizing, and analyzing historical Query Store data.

QueryVault copies Query Store information from one or more source databases into a centralized archive. It is designed to support longer-term performance analysis when the source database's built-in Query Store retention window is not enough. The project combines T-SQL, SQL Server Data Tools project structure, PowerShell deployment helpers, table partitioning, clustered columnstore indexes, and SQL Server Agent automation.

> **Project status:** Active. Core archiving and retention are implemented. The
> version-controlled Grafana V1 package and `qv_report` API are implemented and
> validated against a production-shaped archive on Voyager2. The guarded
> production workflow has deployed the current `master`; review
> [current state](docs/CURRENT_STATE.md) before subsequent changes.

## Why I built this

SQL Server Query Store is extremely useful for investigating regressions and understanding workload behavior, but its data can age out or be removed as storage limits are reached. QueryVault explores a practical solution: periodically archive that performance history into a purpose-built database where it can be retained, protected, queried, and maintained independently.

The project demonstrates database design and administration skills including:

- SQL Server Query Store internals
- T-SQL stored procedure development
- Partition functions, partition schemes, and partition switching
- Clustered columnstore storage for historical analytics
- Metadata-driven configuration and retention
- Dynamic SQL and cross-database operations
- SQL Server Agent job automation
- PowerShell-assisted deployment
- SQL Server Data Tools project organization
- Operational documentation and troubleshooting

## Key capabilities

- **Centralized Query Store archive** — preserves queries, query text, plans, runtime statistics, runtime intervals, and wait statistics.
- **Partitioned storage** — organizes archive data by run identifier for efficient maintenance.
- **Columnstore compression** — supports compact storage and analytical query patterns.
- **Metadata tracking** — records archive windows, source databases, status, row counts, retention dates, and protected runs.
- **Configurable retention** — supports per-database scheduling and retention settings.
- **Protected archives** — a `DoNotDelete` flag can preserve important investigation snapshots.
- **Automated execution** — includes SQL Server Agent job templates for individual or multiple databases.
- **Deployment options** — supports SSDT/database-project deployment, SQLCMD, PowerShell, or ordered manual execution.
- **Operational reporting** — includes procedures and sample queries for archive summaries, storage monitoring, and troubleshooting.
- **Stable reporting API** — exposes supported analytics through `qv_report` without coupling clients to internal tables.
- **Grafana OSS dashboards** — provisions the native Microsoft SQL Server datasource and four V1 dashboards; no custom plugin or plan renderer.

## Architecture

A typical workflow is:

1. Register a source database in QueryVault.
2. Select an archive time window.
3. Copy Query Store entities into archive tables under a shared `RunID`.
4. Record counts, execution status, retention, and protection metadata.
5. Query the retained history for performance investigations.
6. Switch and truncate eligible partitions when old runs reach their retention date.

The archive covers these major Query Store entities:

- `query_store_query_text`
- `query_store_query`
- `query_store_plan`
- `query_store_runtime_stats_interval`
- `query_store_runtime_stats`
- `query_store_wait_stats`

## Repository layout

`QueryVault/` contains the SQL database project and detailed technical documentation.

| Path | Purpose |
| --- | --- |
| `QueryVault/Tables/Core/` | Configuration and archive-run metadata |
| `QueryVault/Tables/QueryStore/` | Partitioned archive tables |
| `QueryVault/Tables/PartitionMaintenance/` | Matching tables used for partition-switch maintenance |
| `QueryVault/StoredProcedures/` | Initialization, archiving, reporting, and partition-management logic |
| `QueryVault/Partitions/` | Partition function and partition scheme definitions |
| `QueryVault/Jobs/` | SQL Server Agent job templates |
| `QueryVault/Scripts/` | Deployment, compatibility, and Query Store setup utilities |
| `QueryVault/Views/` and `QueryVault/Schemas/` | Stable `qv_report` reporting contract |
| `QueryVault/Security/` | DBA bootstrap and least-privilege Grafana user grants |
| `QueryVault/Tests/` | Read-only correctness and reporting reconciliation checks |
| `grafana/` | Version-controlled datasource and dashboard provisioning |
| `docs/` | Architecture, operations, reporting, validation, and screenshot plans |
| `QueryVault/README.md` | Full installation, usage, maintenance, and troubleshooting guide |

Start with the [detailed QueryVault documentation](QueryVault/README.md) for commands and examples.

For the supported Grafana OSS reporting integration, see the [reporting plan](docs/GRAFANA_REPORTING_PLAN.md) and [Grafana setup guide](docs/Grafana-Setup.md). Visualization queries use the stable `qv_report` schema rather than QueryVault's internal tables. The [architecture](docs/Architecture.md), [installation guide](docs/Installation.md), [operator guide](docs/QueryVault-Guide.md), and [validation report](docs/VALIDATION_REPORT.md) describe the complete path.

## Requirements

- SQL Server 2016 or later
- Query Store enabled on each source database
- SQL Server Agent for scheduled jobs (optional)
- SQLCMD or PowerShell for the assisted deployment paths (optional)
- Appropriate permissions for deploying the archive database and reading Query Store data
- Sufficient storage for the chosen retention period

SQL Server behavior and permissions vary by version and environment. Validate the deployment scripts, database names, filegroup strategy, job ownership, and retention settings before production use.

## Getting started

1. Clone or download the repository.
2. Review [QueryVault/README.md](QueryVault/README.md).
3. Deploy to an isolated development or test SQL Server instance.
4. Enable Query Store on a test source database if needed.
5. Register the source database with `usp_InitializeDatabase`.
6. Run a small manual archive with `usp_ArchiveQueryStore`.
7. Validate row counts and results with `usp_GetArchiveSummary`.
8. Configure automation only after the manual workflow succeeds.

Example initialization:

```sql
EXEC QueryVaultDB.dbo.usp_InitializeDatabase
    @DatabaseName = N'YourDatabase',
    @DefaultDaysToArchive = 30,
    @ScheduleType = N'Daily',
    @ScheduleTime = '02:00:00',
    @DefaultRetentionDays = 365;
```

Example manual archive:

```sql
EXEC QueryVaultDB.dbo.usp_ArchiveQueryStore
    @SourceDatabaseName = N'YourDatabase',
    @RunName = N'Initial test archive',
    @DoNotDelete = 1;
```

`usp_ArchiveQueryStore` accepts either an exact UTC window through
`@StartDateTime` and `@EndDateTime`, or a relative safely completed duration
through `@LookbackMinutes` (`60` for one hour, `1440` for one day). Supported
SQL Agent jobs resume from the latest completed endpoint so a failed run does
not leave an uncollected gap.

## Safety notes

- Test restores and deployments outside production first.
- Use least-privilege accounts for deployment and scheduled execution.
- Review SQL Agent job owners and proxy requirements.
- Size the archive using realistic Query Store volumes.
- Monitor partition availability before the configured range is exhausted.
- Confirm retention requirements before deleting archive runs.
- Do not commit credentials, connection strings, production server names, or customer data.

## What this project showcases

For reviewers and prospective employers, this repository is intended to show how I approach a database engineering problem end to end: identifying an operational gap, designing a metadata-driven schema, implementing automation and maintenance paths, documenting usage, and accounting for deployment and support concerns.

Areas of focus include SQL Server performance engineering, database reliability, maintainable T-SQL, automation, and clear technical documentation.

## Roadmap

Potential future enhancements include:

- Automated integration tests against disposable SQL Server instances
- CI validation for the SQL database project
- More configurable filegroup placement and partition growth
- Retention cleanup orchestration with dry-run reporting
- Authoritative period classification behind the existing nullable reporting column
- Release packaging and versioned upgrade scripts

## Contributing

Issues and pull requests are welcome. If proposing a change, please describe the SQL Server version used, the deployment path tested, and any compatibility considerations.

## License

No open-source license has been selected yet. The source is publicly visible for review and portfolio purposes; reuse rights are not granted unless a license is added later.

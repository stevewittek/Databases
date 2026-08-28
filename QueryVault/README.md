# QueryVault - SQL Server Query Store Archiving Solution

A comprehensive database solution for archiving SQL Server Query Store data with partition-based storage, automated maintenance, and SQL Agent job integration.

## Features

- **Partitioned Storage**: Each archive run stored in separate partitions for efficient management
- **Clustered Columnstore Indexes**: Optimal compression and query performance
- **Partition Maintenance**: Mirror tables for efficient partition switching and cleanup
- **Automated Archiving**: SQL Agent jobs for scheduled archiving
- **Flexible Configuration**: Per-database settings for retention, compression, and schedules
- **Data Protection**: "Do Not Delete" flags for critical archives
- **Complete Query Store Coverage**: Archives all Query Store tables (query, query_text, plan, runtime_stats, wait_stats)

## Architecture

### Core Components

1. **Metadata Tables**
   - `RunMetadata`: Tracks each archive run with statistics and protection flags
   - `DatabaseConfig`: Per-database configuration and scheduling

2. **Partition Infrastructure**
   - `PF_RunID`: Partition function based on RunID (supports 100 initial partitions)
   - `PS_RunID`: Partition scheme mapping partitions to filegroups

3. **Archive Tables** (Partitioned by RunID)
   - `query_store_query`
   - `query_store_query_text`
   - `query_store_plan`
   - `query_store_runtime_stats`
   - `query_store_runtime_stats_interval`
   - `query_store_wait_stats`

4. **Partition Maintenance Tables**
   - Mirror schema tables with `_PartitionMaintenance` suffix
   - Enable efficient partition switching and truncation

5. **Stored Procedures**
   - `usp_InitializeDatabase`: Register databases for archiving
   - `usp_ArchiveQueryStore`: Main archiving procedure
   - `usp_ManagePartitions`: Partition management operations
   - `usp_PurgeExpiredArchives`: Retention-aware purge of completed, unprotected runs
   - `usp_GetArchiveSummary`: Reporting and analysis

## Installation

### Option 1: PowerShell Deployment (Recommended)

```powershell
.\Scripts\DeployQueryVault.ps1 -ServerInstance "YourServer" -Verbose
```

### Option 2: SQLCMD Deployment

```cmd
sqlcmd -S YourServer -i Scripts\Deploy.sql -v ProjectDir="C:\Path\To\QueryVault\"
```

### Option 3: Manual Deployment

Execute scripts in this order:
1. `Partitions\PartitionFunction.sql`
2. `Partitions\PartitionScheme.sql`
3. `Tables\Core\*.sql`
4. `Tables\QueryStore\*.sql`
5. `Tables\PartitionMaintenance\*.sql`
6. `StoredProcedures\*.sql`

## Quick Start

### 1. Register a Database for Archiving

```sql
EXEC QueryVaultDB.dbo.usp_InitializeDatabase
	@DatabaseName = 'YourProductionDB',
	@DefaultDaysToArchive = 30,
	@ScheduleType = 'Daily',
	@ScheduleTime = '02:00:00',
	@CompressionDelayMinutes = 0,
	@DefaultRetentionDays = 365,
	@Comments = 'Production database - critical queries';
```

### 2. Run Manual Archive

```sql
EXEC QueryVaultDB.dbo.usp_ArchiveQueryStore
	@SourceDatabaseName = 'YourProductionDB',
	@RunName = 'Manual Archive - Performance Investigation',
	@DoNotDelete = 1;  -- Protect this archive from auto-deletion
```

### 3. Create SQL Agent Job

Run one of the job creation scripts:
- `Jobs\CreateArchiveJob_Template.sql` - Single database
- `Jobs\CreateArchiveJob_AllDatabases.sql` - All enabled databases

### 4. View Archive Summary

```sql
-- View all archives
EXEC QueryVaultDB.dbo.usp_GetArchiveSummary;

-- View archives for specific database
EXEC QueryVaultDB.dbo.usp_GetArchiveSummary 
	@SourceDatabaseName = 'YourProductionDB';
```

## Usage Examples

### Archive Last 7 Days of Query Store Data

```sql
DECLARE @StartDate DATETIME2(7) = DATEADD(DAY, -7, SYSUTCDATETIME());
DECLARE @EndDate DATETIME2(7) = SYSUTCDATETIME();

EXEC QueryVaultDB.dbo.usp_ArchiveQueryStore
	@SourceDatabaseName = 'MyDatabase',
	@RunName = 'Weekly Archive',
	@StartDateTime = @StartDate,
	@EndDateTime = @EndDate,
	@DoNotDelete = 0,
	@RetentionDays = 90;
```

### Query Archived Data

```sql
-- Find slow queries in a specific archive run
SELECT 
	q.query_id,
	qt.query_sql_text,
	rs.avg_duration / 1000000.0 AS avg_duration_seconds,
	rs.count_executions,
	rs.avg_cpu_time / 1000000.0 AS avg_cpu_seconds
FROM QueryVaultDB.dbo.query_store_runtime_stats rs
INNER JOIN QueryVaultDB.dbo.query_store_plan p ON p.plan_id = rs.plan_id AND p.RunID = rs.RunID
INNER JOIN QueryVaultDB.dbo.query_store_query q ON q.query_id = p.query_id AND q.RunID = p.RunID
INNER JOIN QueryVaultDB.dbo.query_store_query_text qt ON qt.query_text_id = q.query_text_id AND qt.RunID = q.RunID
WHERE rs.RunID = 1  -- Specific archive run
  AND rs.avg_duration > 1000000  -- > 1 second average
ORDER BY rs.avg_duration DESC;
```

### Partition Management

```sql
-- View partition information
EXEC QueryVaultDB.dbo.usp_ManagePartitions 
	@Operation = 'GetInfo';

-- Add 10 more partitions when approaching limit
EXEC QueryVaultDB.dbo.usp_ManagePartitions 
	@Operation = 'AddPartition',
	@NewPartitionCount = 10;

-- Switch out old partition to maintenance table
EXEC QueryVaultDB.dbo.usp_ManagePartitions 
	@Operation = 'SwitchOut',
	@RunID = 5;

-- Truncate maintenance table partition
EXEC QueryVaultDB.dbo.usp_ManagePartitions 
	@Operation = 'Truncate',
	@RunID = 5;
```

### Delete Old Archives

```sql
-- Preview completed, expired, unprotected runs whose source configuration has
-- AutoDeleteEnabled = 1.
EXEC QueryVaultDB.dbo.usp_PurgeExpiredArchives @DryRun = 1;

-- Purge all eligible runs. Each run's partition switch, truncate, and metadata
-- delete are atomic. Failures are reported after other eligible runs are tried.
EXEC QueryVaultDB.dbo.usp_PurgeExpiredArchives;
```

`DoNotDelete = 1` always protects a run. Failed and in-progress runs are also
excluded from automated retention cleanup.

Existing deployments created before automated purge support must run
`Scripts\FixPartitionMaintenanceSwitchConstraints.sql` once. Fresh deployments
do not create the legacy constraints.

### Voyager 2 Scheduled Deployment

`Scripts\Voyager2_CreateDisabledArchiveJob.sql` creates a dedicated
`queryvault_agent` login, grants read-only Query Store access to enabled source
databases, and configures a two-step daily SQL Agent job at 02:30 UTC. The
historical filename is retained for compatibility; the resulting job is enabled.

## Configuration Options

### DatabaseConfig Table Fields

- **DefaultDaysToArchive**: Lookback period for archiving (default: 30)
- **ScheduleType**: Daily, Weekly, Monthly, OnDemand
- **ScheduleTime**: Time to run scheduled archives
- **CompressionDelayMinutes**: Columnstore compression delay (0 = immediate)
- **DefaultRetentionDays**: How long to keep archives (default: 365)
- **AutoDeleteEnabled**: Enable automatic deletion based on retention
- **MaxRowsPerBatch**: Batch size for archiving operations

### RunMetadata Fields

- **DoNotDelete**: Protection flag for critical archives
- **RetentionDate**: When archive can be deleted (if DoNotDelete = 0)
- **RunStatus**: In Progress, Completed, Failed
- **RowsArchived_***: Row counts for each table

## Maintenance

### Monitor Partition Usage

```sql
SELECT 
	pf.name AS PartitionFunction,
	pf.fanout AS TotalPartitions,
	COUNT(DISTINCT rm.RunID) AS PartitionsInUse,
	pf.fanout - COUNT(DISTINCT rm.RunID) AS PartitionsAvailable
FROM sys.partition_functions pf
LEFT JOIN QueryVaultDB.dbo.RunMetadata rm ON 1=1
WHERE pf.name = 'PF_RunID'
GROUP BY pf.name, pf.fanout;
```

### Monitor Storage Usage

```sql
SELECT 
	t.name AS TableName,
	SUM(p.rows) AS TotalRows,
	SUM(a.total_pages) * 8 / 1024 AS TotalSizeMB,
	SUM(a.used_pages) * 8 / 1024 AS UsedSizeMB
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name LIKE 'query_store_%'
  AND t.name NOT LIKE '%PartitionMaintenance'
GROUP BY t.name
ORDER BY SUM(a.total_pages) DESC;
```

## Requirements

- SQL Server 2016 or higher (for Query Store and columnstore support)
- Source databases must have Query Store enabled
- Sufficient disk space for archived data
- Appropriate permissions:
  - db_owner on QueryVaultDB
  - db_datareader on source databases
  - SQLAgentOperatorRole for job management (optional)

## Best Practices

1. **Start Small**: Test with a single database before enabling multiple databases
2. **Monitor Partition Count**: Extend partitions before running out
3. **Use DoNotDelete**: Flag critical archives for investigation or compliance
4. **Regular Cleanup**: Archive old data but clean up non-critical runs
5. **Compression Delay**: Use 0 minutes for archival data (already historical)
6. **Schedule Wisely**: Run jobs during maintenance windows
7. **Retention Policies**: Align with your organization's data retention requirements

## Troubleshooting

### Archive Job Fails

```sql
-- Check failed runs
SELECT * FROM QueryVaultDB.dbo.RunMetadata 
WHERE RunStatus = 'Failed' 
ORDER BY RunStartTime DESC;

-- Check SQL Agent job history
SELECT TOP 10
	j.name AS JobName,
	h.step_name,
	h.run_status,
	h.message
FROM msdb.dbo.sysjobhistory h
INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE j.name LIKE 'QueryVault%'
ORDER BY h.run_date DESC, h.run_time DESC;
```

### Out of Partitions

```sql
-- Check current limit
EXEC QueryVaultDB.dbo.usp_ManagePartitions @Operation = 'GetInfo';

-- Add more partitions
EXEC QueryVaultDB.dbo.usp_ManagePartitions 
	@Operation = 'AddPartition',
	@NewPartitionCount = 50;
```

## License

This project is provided as-is for use in archiving SQL Server Query Store data.

## Support

For issues, questions, or contributions, please refer to your organization's support channels.

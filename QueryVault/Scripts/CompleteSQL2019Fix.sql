/*
	Complete SQL Server 2019 Compatibility Fix
	This script updates all tables and procedures to work with SQL Server 2019
*/

USE QueryVaultDB;
GO

PRINT '========================================';
PRINT 'Applying SQL Server 2019 Compatibility';
PRINT '========================================';
PRINT '';

-- Fix query_store_runtime_stats table (remove SQL 2022 columns)
PRINT 'Recreating query_store_runtime_stats...';

IF OBJECT_ID('dbo.query_store_runtime_stats', 'U') IS NOT NULL
	DROP TABLE dbo.query_store_runtime_stats;
GO

CREATE TABLE dbo.query_store_runtime_stats
(
	RunID INT NOT NULL,
	runtime_stats_id BIGINT NOT NULL,
	plan_id BIGINT NOT NULL,
	runtime_stats_interval_id BIGINT NOT NULL,
	execution_type TINYINT NOT NULL,
	execution_type_desc NVARCHAR(128) NULL,
	first_execution_time DATETIMEOFFSET(7) NOT NULL,
	last_execution_time DATETIMEOFFSET(7) NOT NULL,
	count_executions BIGINT NOT NULL,
	avg_duration FLOAT NOT NULL,
	last_duration BIGINT NOT NULL,
	min_duration BIGINT NOT NULL,
	max_duration BIGINT NOT NULL,
	stdev_duration FLOAT NOT NULL,
	avg_cpu_time FLOAT NOT NULL,
	last_cpu_time BIGINT NOT NULL,
	min_cpu_time BIGINT NOT NULL,
	max_cpu_time BIGINT NOT NULL,
	stdev_cpu_time FLOAT NOT NULL,
	avg_logical_io_reads FLOAT NOT NULL,
	last_logical_io_reads BIGINT NOT NULL,
	min_logical_io_reads BIGINT NOT NULL,
	max_logical_io_reads BIGINT NOT NULL,
	stdev_logical_io_reads FLOAT NOT NULL,
	avg_logical_io_writes FLOAT NOT NULL,
	last_logical_io_writes BIGINT NOT NULL,
	min_logical_io_writes BIGINT NOT NULL,
	max_logical_io_writes BIGINT NOT NULL,
	stdev_logical_io_writes FLOAT NOT NULL,
	avg_physical_io_reads FLOAT NOT NULL,
	last_physical_io_reads BIGINT NOT NULL,
	min_physical_io_reads BIGINT NOT NULL,
	max_physical_io_reads BIGINT NOT NULL,
	stdev_physical_io_reads FLOAT NOT NULL,
	avg_clr_time FLOAT NOT NULL,
	last_clr_time BIGINT NOT NULL,
	min_clr_time BIGINT NOT NULL,
	max_clr_time BIGINT NOT NULL,
	stdev_clr_time FLOAT NOT NULL,
	avg_dop FLOAT NOT NULL,
	last_dop BIGINT NOT NULL,
	min_dop BIGINT NOT NULL,
	max_dop BIGINT NOT NULL,
	stdev_dop FLOAT NOT NULL,
	avg_query_max_used_memory FLOAT NOT NULL,
	last_query_max_used_memory BIGINT NOT NULL,
	min_query_max_used_memory BIGINT NOT NULL,
	max_query_max_used_memory BIGINT NOT NULL,
	stdev_query_max_used_memory FLOAT NOT NULL,
	avg_rowcount FLOAT NOT NULL,
	last_rowcount BIGINT NOT NULL,
	min_rowcount BIGINT NOT NULL,
	max_rowcount BIGINT NOT NULL,
	stdev_rowcount FLOAT NOT NULL,
	avg_num_physical_io_reads FLOAT NULL,
	last_num_physical_io_reads BIGINT NULL,
	min_num_physical_io_reads BIGINT NULL,
	max_num_physical_io_reads BIGINT NULL,
	stdev_num_physical_io_reads FLOAT NULL,
	avg_log_bytes_used FLOAT NULL,
	last_log_bytes_used BIGINT NULL,
	min_log_bytes_used BIGINT NULL,
	max_log_bytes_used BIGINT NULL,
	stdev_log_bytes_used FLOAT NULL,
	avg_tempdb_space_used FLOAT NULL,
	last_tempdb_space_used BIGINT NULL,
	min_tempdb_space_used BIGINT NULL,
	max_tempdb_space_used BIGINT NULL,
	stdev_tempdb_space_used FLOAT NULL,
	-- Removed SQL 2022/Azure columns:
	-- avg_page_server_io_reads, last_page_server_io_reads, min_page_server_io_reads,
	-- max_page_server_io_reads, stdev_page_server_io_reads

	CONSTRAINT PK_query_store_runtime_stats PRIMARY KEY NONCLUSTERED (RunID, runtime_stats_id)
) ON PS_RunID(RunID);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_runtime_stats 
	ON dbo.query_store_runtime_stats
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

-- Fix maintenance table too
IF OBJECT_ID('dbo.query_store_runtime_stats_PartitionMaintenance', 'U') IS NOT NULL
	DROP TABLE dbo.query_store_runtime_stats_PartitionMaintenance;
GO

CREATE TABLE dbo.query_store_runtime_stats_PartitionMaintenance
(
	RunID INT NOT NULL,
	runtime_stats_id BIGINT NOT NULL,
	plan_id BIGINT NOT NULL,
	runtime_stats_interval_id BIGINT NOT NULL,
	execution_type TINYINT NOT NULL,
	execution_type_desc NVARCHAR(128) NULL,
	first_execution_time DATETIMEOFFSET(7) NOT NULL,
	last_execution_time DATETIMEOFFSET(7) NOT NULL,
	count_executions BIGINT NOT NULL,
	avg_duration FLOAT NOT NULL,
	last_duration BIGINT NOT NULL,
	min_duration BIGINT NOT NULL,
	max_duration BIGINT NOT NULL,
	stdev_duration FLOAT NOT NULL,
	avg_cpu_time FLOAT NOT NULL,
	last_cpu_time BIGINT NOT NULL,
	min_cpu_time BIGINT NOT NULL,
	max_cpu_time BIGINT NOT NULL,
	stdev_cpu_time FLOAT NOT NULL,
	avg_logical_io_reads FLOAT NOT NULL,
	last_logical_io_reads BIGINT NOT NULL,
	min_logical_io_reads BIGINT NOT NULL,
	max_logical_io_reads BIGINT NOT NULL,
	stdev_logical_io_reads FLOAT NOT NULL,
	avg_logical_io_writes FLOAT NOT NULL,
	last_logical_io_writes BIGINT NOT NULL,
	min_logical_io_writes BIGINT NOT NULL,
	max_logical_io_writes BIGINT NOT NULL,
	stdev_logical_io_writes FLOAT NOT NULL,
	avg_physical_io_reads FLOAT NOT NULL,
	last_physical_io_reads BIGINT NOT NULL,
	min_physical_io_reads BIGINT NOT NULL,
	max_physical_io_reads BIGINT NOT NULL,
	stdev_physical_io_reads FLOAT NOT NULL,
	avg_clr_time FLOAT NOT NULL,
	last_clr_time BIGINT NOT NULL,
	min_clr_time BIGINT NOT NULL,
	max_clr_time BIGINT NOT NULL,
	stdev_clr_time FLOAT NOT NULL,
	avg_dop FLOAT NOT NULL,
	last_dop BIGINT NOT NULL,
	min_dop BIGINT NOT NULL,
	max_dop BIGINT NOT NULL,
	stdev_dop FLOAT NOT NULL,
	avg_query_max_used_memory FLOAT NOT NULL,
	last_query_max_used_memory BIGINT NOT NULL,
	min_query_max_used_memory BIGINT NOT NULL,
	max_query_max_used_memory BIGINT NOT NULL,
	stdev_query_max_used_memory FLOAT NOT NULL,
	avg_rowcount FLOAT NOT NULL,
	last_rowcount BIGINT NOT NULL,
	min_rowcount BIGINT NOT NULL,
	max_rowcount BIGINT NOT NULL,
	stdev_rowcount FLOAT NOT NULL,
	avg_num_physical_io_reads FLOAT NULL,
	last_num_physical_io_reads BIGINT NULL,
	min_num_physical_io_reads BIGINT NULL,
	max_num_physical_io_reads BIGINT NULL,
	stdev_num_physical_io_reads FLOAT NULL,
	avg_log_bytes_used FLOAT NULL,
	last_log_bytes_used BIGINT NULL,
	min_log_bytes_used BIGINT NULL,
	max_log_bytes_used BIGINT NULL,
	stdev_log_bytes_used FLOAT NULL,
	avg_tempdb_space_used FLOAT NULL,
	last_tempdb_space_used BIGINT NULL,
	min_tempdb_space_used BIGINT NULL,
	max_tempdb_space_used BIGINT NULL,
	stdev_tempdb_space_used FLOAT NULL,

	CONSTRAINT PK_query_store_runtime_stats_PartitionMaintenance PRIMARY KEY NONCLUSTERED (RunID, runtime_stats_id),
	CONSTRAINT CK_query_store_runtime_stats_PartitionMaintenance CHECK (RunID = RunID)
) ON PS_RunID(RunID);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_runtime_stats_PartitionMaintenance 
	ON dbo.query_store_runtime_stats_PartitionMaintenance
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

PRINT '✓ Tables recreated for SQL Server 2019';
GO

/*
	Partition Maintenance table for query_store_query
	Mirror schema for partition switching - allows efficient partition swap and truncate
*/

CREATE TABLE dbo.query_store_query_PartitionMaintenance
(
	RunID INT NOT NULL,
	query_id BIGINT NOT NULL,
	query_text_id BIGINT NOT NULL,
	context_settings_id BIGINT NOT NULL,
	object_id BIGINT NOT NULL,
	batch_sql_handle VARBINARY(64) NULL,
	query_hash BINARY(8) NULL,
	is_internal_query BIT NOT NULL,
	query_parameterization_type TINYINT NOT NULL,
	query_parameterization_type_desc NVARCHAR(60) NULL,
	initial_compile_start_time DATETIMEOFFSET(7) NOT NULL,
	last_compile_start_time DATETIMEOFFSET(7) NOT NULL,
	last_execution_time DATETIMEOFFSET(7) NOT NULL,
	last_compile_batch_sql_handle VARBINARY(64) NULL,
	last_compile_batch_offset_start BIGINT NULL,
	last_compile_batch_offset_end BIGINT NULL,
	count_compiles BIGINT NOT NULL,
	avg_compile_duration FLOAT NOT NULL,
	last_compile_duration BIGINT NOT NULL,
	avg_bind_duration FLOAT NOT NULL,
	last_bind_duration BIGINT NOT NULL,
	avg_bind_cpu_time FLOAT NOT NULL,
	last_bind_cpu_time BIGINT NOT NULL,
	avg_optimize_duration FLOAT NOT NULL,
	last_optimize_duration BIGINT NOT NULL,
	avg_optimize_cpu_time FLOAT NOT NULL,
	last_optimize_cpu_time BIGINT NOT NULL,
	avg_compile_memory_kb FLOAT NOT NULL,
	last_compile_memory_kb BIGINT NOT NULL,
	max_compile_memory_kb BIGINT NOT NULL,
	is_clouddb_internal_query BIT NOT NULL,

	CONSTRAINT PK_query_store_query_PartitionMaintenance PRIMARY KEY NONCLUSTERED (RunID, query_id),
	CONSTRAINT CK_query_store_query_PartitionMaintenance CHECK (RunID = RunID)
) ON PS_RunID(RunID);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_query_PartitionMaintenance 
	ON dbo.query_store_query_PartitionMaintenance
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

PRINT 'Table dbo.query_store_query_PartitionMaintenance created';
GO

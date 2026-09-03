/*
	Archive table for sys.query_store_query
	Partitioned by RunID with clustered columnstore index
*/

CREATE TABLE dbo.query_store_query
(
	RunID INT NOT NULL,
	query_id BIGINT NOT NULL,
	query_text_id BIGINT NOT NULL,
	context_settings_id BIGINT NOT NULL,
	object_id BIGINT NULL,
	batch_sql_handle VARBINARY(64) NULL,
	query_hash BINARY(8) NULL,
	is_internal_query BIT NOT NULL,
	query_parameterization_type TINYINT NOT NULL,
	query_parameterization_type_desc NVARCHAR(60) NULL,
	initial_compile_start_time DATETIMEOFFSET(7) NOT NULL,
	last_compile_start_time DATETIMEOFFSET(7) NULL,
	last_execution_time DATETIMEOFFSET(7) NULL,
	last_compile_batch_sql_handle VARBINARY(64) NULL,
	last_compile_batch_offset_start BIGINT NULL,
	last_compile_batch_offset_end BIGINT NULL,
	count_compiles BIGINT NULL,
	avg_compile_duration FLOAT NULL,
	last_compile_duration BIGINT NULL,
	avg_bind_duration FLOAT NULL,
	last_bind_duration BIGINT NULL,
	avg_bind_cpu_time FLOAT NULL,
	last_bind_cpu_time BIGINT NULL,
	avg_optimize_duration FLOAT NULL,
	last_optimize_duration BIGINT NULL,
	avg_optimize_cpu_time FLOAT NULL,
	last_optimize_cpu_time BIGINT NULL,
	avg_compile_memory_kb FLOAT NULL,
	last_compile_memory_kb BIGINT NULL,
	max_compile_memory_kb BIGINT NULL,
	is_clouddb_internal_query BIT NULL,

	CONSTRAINT PK_query_store_query PRIMARY KEY NONCLUSTERED (RunID, query_id)
) ON PS_RunID(RunID);
GO
-- Clustered columnstore index with configurable compression delay
CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_query 
	ON dbo.query_store_query
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

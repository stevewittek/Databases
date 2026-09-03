/*
	Partition Maintenance table for query_store_plan
	Mirror schema for partition switching
*/

CREATE TABLE dbo.query_store_plan_PartitionMaintenance
(
	RunID INT NOT NULL,
	plan_id BIGINT NOT NULL,
	query_id BIGINT NOT NULL,
	plan_group_id BIGINT NULL,
	engine_version NVARCHAR(32) NULL,
	compatibility_level SMALLINT NOT NULL,
	query_plan_hash BINARY(8) NOT NULL,
	query_plan NVARCHAR(MAX) NULL,
	is_online_index_plan BIT NOT NULL,
	is_trivial_plan BIT NOT NULL,
	is_parallel_plan BIT NOT NULL,
	is_forced_plan BIT NOT NULL,
	is_natively_compiled BIT NOT NULL,
	force_failure_count BIGINT NOT NULL,
	last_force_failure_reason INT NOT NULL,
	last_force_failure_reason_desc NVARCHAR(128) NULL,
	count_compiles BIGINT NULL,
	initial_compile_start_time DATETIMEOFFSET(7) NOT NULL,
	last_compile_start_time DATETIMEOFFSET(7) NULL,
	last_execution_time DATETIMEOFFSET(7) NULL,
	avg_compile_duration FLOAT NULL,
	last_compile_duration BIGINT NULL,
	plan_forcing_type INT NOT NULL,
	plan_forcing_type_desc NVARCHAR(60) NULL,
	has_compile_replay_script BIT NOT NULL,
	is_optimized_plan_forcing_disabled BIT NOT NULL,
	plan_type INT NOT NULL,
	plan_type_desc NVARCHAR(60) NULL,

	CONSTRAINT PK_query_store_plan_PartitionMaintenance PRIMARY KEY NONCLUSTERED (RunID, plan_id)
) ON PS_RunID(RunID);
GO
CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_plan_PartitionMaintenance 
	ON dbo.query_store_plan_PartitionMaintenance
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

/*
	Partition Maintenance table for query_store_wait_stats
	Mirror schema for partition switching
*/

CREATE TABLE dbo.query_store_wait_stats_PartitionMaintenance
(
	RunID INT NOT NULL,
	wait_stats_id BIGINT NOT NULL,
	plan_id BIGINT NOT NULL,
	runtime_stats_interval_id BIGINT NOT NULL,
	wait_category SMALLINT NOT NULL,
	wait_category_desc NVARCHAR(128) NULL,
	execution_type TINYINT NOT NULL,
	execution_type_desc NVARCHAR(128) NULL,
	total_query_wait_time_ms BIGINT NOT NULL,
	avg_query_wait_time_ms FLOAT NULL,
	last_query_wait_time_ms BIGINT NOT NULL,
	min_query_wait_time_ms BIGINT NOT NULL,
	max_query_wait_time_ms BIGINT NOT NULL,
	stdev_query_wait_time_ms FLOAT NULL,
	replica_group_id BIGINT NOT NULL,

	CONSTRAINT PK_query_store_wait_stats_PartitionMaintenance PRIMARY KEY NONCLUSTERED (RunID, wait_stats_id)
) ON PS_RunID(RunID);
GO
CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_wait_stats_PartitionMaintenance 
	ON dbo.query_store_wait_stats_PartitionMaintenance
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

/*
	Archive table for sys.query_store_wait_stats
	Partitioned by RunID with clustered columnstore index
*/

CREATE TABLE dbo.query_store_wait_stats
(
	RunID INT NOT NULL,
	wait_stats_id BIGINT NOT NULL,
	plan_id BIGINT NOT NULL,
	runtime_stats_interval_id BIGINT NOT NULL,
	wait_category TINYINT NOT NULL,
	wait_category_desc NVARCHAR(128) NULL,
	execution_type TINYINT NOT NULL,
	execution_type_desc NVARCHAR(128) NULL,
	total_query_wait_time_ms BIGINT NOT NULL,
	avg_query_wait_time_ms FLOAT NOT NULL,
	last_query_wait_time_ms BIGINT NOT NULL,
	min_query_wait_time_ms BIGINT NOT NULL,
	max_query_wait_time_ms BIGINT NOT NULL,
	stdev_query_wait_time_ms FLOAT NOT NULL,

	CONSTRAINT PK_query_store_wait_stats PRIMARY KEY NONCLUSTERED (RunID, wait_stats_id)
) ON PS_RunID(RunID);
GO

-- Clustered columnstore index
CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_wait_stats 
	ON dbo.query_store_wait_stats
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

PRINT 'Table dbo.query_store_wait_stats created with partitioning and clustered columnstore index';
GO

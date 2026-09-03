/* One complete archived wait observation at Microsoft's documented grain. */

CREATE TABLE dbo.query_store_wait_stats_canonical
(
	RunID INT NOT NULL,
	plan_id BIGINT NOT NULL,
	runtime_stats_interval_id BIGINT NOT NULL,
	execution_type TINYINT NOT NULL,
	execution_type_desc NVARCHAR(128) NULL,
	wait_category SMALLINT NOT NULL,
	wait_category_desc NVARCHAR(128) NULL,
	contributor_count BIGINT NOT NULL,
	replica_group_id BIGINT NULL,
	replica_count INT NOT NULL,
	total_query_wait_time_ms DECIMAL(38,0) NOT NULL,
	avg_query_wait_time_ms FLOAT NULL,
	last_query_wait_time_ms BIGINT NULL,
	min_query_wait_time_ms BIGINT NULL,
	max_query_wait_time_ms BIGINT NULL,
	stdev_query_wait_time_ms FLOAT NULL,
	last_wait_stats_contributor_id BIGINT NULL,
	last_value_ambiguous BIT NOT NULL,
	stdev_aggregation_status NVARCHAR(64) NOT NULL,
	observation_state NVARCHAR(20) NOT NULL,

	CONSTRAINT PK_query_store_wait_stats_canonical
		PRIMARY KEY NONCLUSTERED
		(RunID, plan_id, runtime_stats_interval_id, execution_type, wait_category),
	CONSTRAINT CK_query_store_wait_stats_canonical_stdev
		CHECK (stdev_aggregation_status IN
			(N'NATIVE_SINGLE_CONTRIBUTOR', N'UNAVAILABLE_MULTIPLE_CONTRIBUTORS')),
	CONSTRAINT CK_query_store_wait_stats_canonical_state
		CHECK (observation_state IN (N'COMPLETED', N'PROVISIONAL'))
) ON PS_RunID(RunID);
GO
CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_wait_stats_canonical
	ON dbo.query_store_wait_stats_canonical
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

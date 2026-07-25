/*
	Partition Maintenance table for query_store_runtime_stats_interval
	Mirror schema for partition switching
*/

CREATE TABLE dbo.query_store_runtime_stats_interval_PartitionMaintenance
(
	RunID INT NOT NULL,
	runtime_stats_interval_id BIGINT NOT NULL,
	start_time DATETIMEOFFSET(7) NOT NULL,
	end_time DATETIMEOFFSET(7) NOT NULL,
	comment NVARCHAR(32) NULL,

	CONSTRAINT PK_query_store_runtime_stats_interval_PartitionMaintenance PRIMARY KEY NONCLUSTERED (RunID, runtime_stats_interval_id),
	CONSTRAINT CK_query_store_runtime_stats_interval_PartitionMaintenance CHECK (RunID = RunID)
) ON PS_RunID(RunID);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_runtime_stats_interval_PartitionMaintenance 
	ON dbo.query_store_runtime_stats_interval_PartitionMaintenance
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

PRINT 'Table dbo.query_store_runtime_stats_interval_PartitionMaintenance created';
GO

/*
	Archive table for sys.query_store_runtime_stats_interval
	Partitioned by RunID with clustered columnstore index
*/

CREATE TABLE dbo.query_store_runtime_stats_interval
(
	RunID INT NOT NULL,
	runtime_stats_interval_id BIGINT NOT NULL,
	start_time DATETIMEOFFSET(7) NOT NULL,
	end_time DATETIMEOFFSET(7) NOT NULL,
	comment NVARCHAR(32) NULL,

	CONSTRAINT PK_query_store_runtime_stats_interval PRIMARY KEY NONCLUSTERED (RunID, runtime_stats_interval_id)
) ON PS_RunID(RunID);
GO

-- Clustered columnstore index
CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_runtime_stats_interval 
	ON dbo.query_store_runtime_stats_interval
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

PRINT 'Table dbo.query_store_runtime_stats_interval created with partitioning and clustered columnstore index';
GO

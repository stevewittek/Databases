/*
	Partition Maintenance table for query_store_query_text
	Mirror schema for partition switching
*/

CREATE TABLE dbo.query_store_query_text_PartitionMaintenance
(
	RunID INT NOT NULL,
	query_text_id BIGINT NOT NULL,
	query_sql_text NVARCHAR(MAX) NULL,
	statement_sql_handle VARBINARY(64) NULL,
	is_part_of_encrypted_module BIT NOT NULL,
	has_restricted_text BIT NOT NULL,

	CONSTRAINT PK_query_store_query_text_PartitionMaintenance PRIMARY KEY NONCLUSTERED (RunID, query_text_id),
	CONSTRAINT CK_query_store_query_text_PartitionMaintenance CHECK (RunID = RunID)
) ON PS_RunID(RunID);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_query_text_PartitionMaintenance 
	ON dbo.query_store_query_text_PartitionMaintenance
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

PRINT 'Table dbo.query_store_query_text_PartitionMaintenance created';
GO

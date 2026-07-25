/*
	Archive table for sys.query_store_query_text
	Partitioned by RunID with clustered columnstore index
*/

CREATE TABLE dbo.query_store_query_text
(
	RunID INT NOT NULL,
	query_text_id BIGINT NOT NULL,
	query_sql_text NVARCHAR(MAX) NULL,
	statement_sql_handle VARBINARY(64) NULL,
	is_part_of_encrypted_module BIT NOT NULL,
	has_restricted_text BIT NOT NULL,

	CONSTRAINT PK_query_store_query_text PRIMARY KEY NONCLUSTERED (RunID, query_text_id)
) ON PS_RunID(RunID);
GO

-- Clustered columnstore index
CREATE CLUSTERED COLUMNSTORE INDEX CCI_query_store_query_text 
	ON dbo.query_store_query_text
	WITH (COMPRESSION_DELAY = 0 MINUTES)
	ON PS_RunID(RunID);
GO

PRINT 'Table dbo.query_store_query_text created with partitioning and clustered columnstore index';
GO

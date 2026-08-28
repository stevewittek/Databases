/*
	RunMetadata Table
	Tracks each QueryStore archive run with metadata and protection flags
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE dbo.RunMetadata
(
	RunID INT IDENTITY(1,1) NOT NULL,
	RunName NVARCHAR(255) NOT NULL,
	SourceDatabaseName NVARCHAR(128) NOT NULL,
	SourceServerName NVARCHAR(128) NOT NULL DEFAULT @@SERVERNAME,

	-- Date range for the archived data
	StartDateTime DATETIME2(7) NOT NULL,
	EndDateTime DATETIME2(7) NOT NULL,

	-- Run execution tracking
	RunStartTime DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
	RunEndTime DATETIME2(7) NULL,
	RunStatus NVARCHAR(50) NOT NULL DEFAULT 'In Progress', -- In Progress, Completed, Failed

	-- Protection and retention
	DoNotDelete BIT NOT NULL DEFAULT 0,
	RetentionDate DATETIME2(7) NULL, -- When this run can be deleted (if DoNotDelete = 0)

	-- Statistics
	RowsArchived_Query BIGINT NULL,
	RowsArchived_QueryText BIGINT NULL,
	RowsArchived_Plan BIGINT NULL,
	RowsArchived_RuntimeStats BIGINT NULL,
	RowsArchived_RuntimeStatsInterval BIGINT NULL,
	RowsArchived_WaitStats BIGINT NULL,

	-- Additional metadata
	Comments NVARCHAR(MAX) NULL,
	CreatedBy NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),

	CONSTRAINT PK_RunMetadata PRIMARY KEY CLUSTERED (RunID),
	CONSTRAINT CK_RunMetadata_DateRange CHECK (EndDateTime >= StartDateTime),
	CONSTRAINT CK_RunMetadata_RunStatus CHECK (RunStatus IN ('In Progress', 'Completed', 'Failed'))
);
GO

CREATE NONCLUSTERED INDEX IX_RunMetadata_SourceDatabase 
	ON dbo.RunMetadata(SourceDatabaseName, SourceServerName, StartDateTime, EndDateTime);
GO

CREATE NONCLUSTERED INDEX IX_RunMetadata_DateRange 
	ON dbo.RunMetadata(StartDateTime, EndDateTime) 
	INCLUDE (RunID, SourceDatabaseName);
GO

CREATE NONCLUSTERED INDEX IX_RunMetadata_DoNotDelete 
	ON dbo.RunMetadata(DoNotDelete, RetentionDate) 
	WHERE DoNotDelete = 0;
GO

PRINT 'Table dbo.RunMetadata created successfully';
GO

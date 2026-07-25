/*
	DatabaseConfig Table
	Stores configuration for each database with QueryStore enabled
*/

CREATE TABLE dbo.DatabaseConfig
(
	ConfigID INT IDENTITY(1,1) NOT NULL,
	DatabaseName NVARCHAR(128) NOT NULL,
	ServerName NVARCHAR(128) NOT NULL DEFAULT @@SERVERNAME,

	-- Archive settings
	IsEnabled BIT NOT NULL DEFAULT 1,
	DefaultDaysToArchive INT NOT NULL DEFAULT 30, -- Default lookback period

	-- Schedule settings
	ScheduleType NVARCHAR(50) NOT NULL DEFAULT 'Daily', -- Daily, Weekly, Monthly, OnDemand
	ScheduleTime TIME(7) NULL DEFAULT '02:00:00', -- Default 2 AM
	LastRunDateTime DATETIME2(7) NULL,
	NextRunDateTime DATETIME2(7) NULL,

	-- Columnstore configuration
	CompressionDelayMinutes INT NOT NULL DEFAULT 0, -- 0 = immediate compression

	-- Retention policy
	DefaultRetentionDays INT NOT NULL DEFAULT 365, -- How long to keep archived data
	AutoDeleteEnabled BIT NOT NULL DEFAULT 0, -- Auto-delete based on retention

	-- Additional settings
	MaxRowsPerBatch INT NOT NULL DEFAULT 100000, -- Batch size for archiving
	EnableParallelCopy BIT NOT NULL DEFAULT 1,

	-- Metadata
	CreatedDate DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
	ModifiedDate DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
	CreatedBy NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
	ModifiedBy NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
	Comments NVARCHAR(MAX) NULL,

	CONSTRAINT PK_DatabaseConfig PRIMARY KEY CLUSTERED (ConfigID),
	CONSTRAINT UQ_DatabaseConfig_Database UNIQUE (DatabaseName, ServerName),
	CONSTRAINT CK_DatabaseConfig_ScheduleType CHECK (ScheduleType IN ('Daily', 'Weekly', 'Monthly', 'OnDemand')),
	CONSTRAINT CK_DatabaseConfig_CompressionDelay CHECK (CompressionDelayMinutes >= 0),
	CONSTRAINT CK_DatabaseConfig_DaysToArchive CHECK (DefaultDaysToArchive > 0),
	CONSTRAINT CK_DatabaseConfig_RetentionDays CHECK (DefaultRetentionDays > 0)
);
GO

CREATE NONCLUSTERED INDEX IX_DatabaseConfig_Enabled 
	ON dbo.DatabaseConfig(IsEnabled, NextRunDateTime) 
	WHERE IsEnabled = 1;
GO

PRINT 'Table dbo.DatabaseConfig created successfully';
GO

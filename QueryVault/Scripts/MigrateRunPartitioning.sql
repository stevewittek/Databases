/*
	Additive, idempotent configuration migration for RunID lifecycle controls.
	No archive facts, partition boundaries, or existing settings are rewritten.
*/

SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'dbo.DatabaseConfig', N'MaxRetainedRuns') IS NULL
BEGIN
	ALTER TABLE dbo.DatabaseConfig
		ADD MaxRetainedRuns INT NOT NULL
			CONSTRAINT DF_DatabaseConfig_MaxRetainedRuns DEFAULT (1000) WITH VALUES;
END;
GO

IF COL_LENGTH(N'dbo.DatabaseConfig', N'PartitionWarningPct') IS NULL
BEGIN
	ALTER TABLE dbo.DatabaseConfig
		ADD PartitionWarningPct TINYINT NOT NULL
			CONSTRAINT DF_DatabaseConfig_PartitionWarningPct DEFAULT (80) WITH VALUES;
END;
GO

IF COL_LENGTH(N'dbo.DatabaseConfig', N'StorageMode') IS NULL
BEGIN
	ALTER TABLE dbo.DatabaseConfig
		ADD StorageMode NVARCHAR(20) NOT NULL
			CONSTRAINT DF_DatabaseConfig_StorageMode DEFAULT (N'AUTO') WITH VALUES;
END;
GO

IF OBJECT_ID(N'dbo.CK_DatabaseConfig_MaxRetainedRuns', N'C') IS NULL
	ALTER TABLE dbo.DatabaseConfig WITH CHECK
		ADD CONSTRAINT CK_DatabaseConfig_MaxRetainedRuns
			CHECK (MaxRetainedRuns BETWEEN 1 AND 14990);
GO

IF OBJECT_ID(N'dbo.CK_DatabaseConfig_PartitionWarningPct', N'C') IS NULL
	ALTER TABLE dbo.DatabaseConfig WITH CHECK
		ADD CONSTRAINT CK_DatabaseConfig_PartitionWarningPct
			CHECK (PartitionWarningPct BETWEEN 50 AND 95);
GO

IF OBJECT_ID(N'dbo.CK_DatabaseConfig_StorageMode', N'C') IS NULL
	ALTER TABLE dbo.DatabaseConfig WITH CHECK
		ADD CONSTRAINT CK_DatabaseConfig_StorageMode
			CHECK (StorageMode IN (N'AUTO', N'ROWSTORE', N'COLUMNSTORE'));
GO

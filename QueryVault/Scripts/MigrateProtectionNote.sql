/* Additive only. Does not change pins, dates, partition boundaries or stored facts. */
IF OBJECT_ID(N'dbo.RunMetadata', N'U') IS NULL
    THROW 51610, 'RunMetadata must exist before installing protection notes.', 1;
IF COL_LENGTH(N'dbo.RunMetadata', N'ProtectionNote') IS NULL
    ALTER TABLE dbo.RunMetadata ADD ProtectionNote NVARCHAR(1000) NULL;
ELSE IF EXISTS
(
    SELECT 1 FROM sys.columns
    WHERE object_id=OBJECT_ID(N'dbo.RunMetadata') AND name=N'ProtectionNote'
      AND (system_type_id<>231 OR max_length<>2000 OR is_nullable<>1)
)
    THROW 51611, 'Existing ProtectionNote has an incompatible definition; review migration.', 1;
GO

/*
    Transactional integration test for QueryVault retention cleanup.
    The test exercises partition switch/truncate and rolls back all changes.
*/

USE [QueryVaultDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @RunID INT;
DECLARE @SourceDatabaseName SYSNAME;

SELECT TOP (1) @SourceDatabaseName = DatabaseName
FROM dbo.DatabaseConfig
WHERE IsEnabled = 1
  AND AutoDeleteEnabled = 1
  AND ServerName = @@SERVERNAME
ORDER BY ConfigID;

IF @SourceDatabaseName IS NULL
    THROW 51100, 'The purge test requires an enabled auto-delete configuration.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT dbo.RunMetadata
    (
        RunName,
        SourceDatabaseName,
        StartDateTime,
        EndDateTime,
        RunEndTime,
        RunStatus,
        DoNotDelete,
        RetentionDate,
        Comments
    )
    VALUES
    (
        N'Transactional retention integration test',
        @SourceDatabaseName,
        CAST(N'1999-12-31T00:00:00' AS DATETIME2),
        CAST(N'1999-12-31T00:01:00' AS DATETIME2),
        CAST(N'1999-12-31T00:02:00' AS DATETIME2),
        N'Completed',
        0,
        CAST(N'2000-01-01T00:00:00' AS DATETIME2),
        N'Test row; outer transaction must roll it back.'
    );

    SET @RunID = SCOPE_IDENTITY();

    EXEC dbo.usp_PurgeExpiredArchives
        @AsOfDateTime = '2000-01-02T00:00:00',
        @DryRun = 0;

    IF EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID = @RunID)
        THROW 51101, 'Purge test failed: eligible metadata remains.', 1;

    ROLLBACK TRANSACTION;

    SELECT N'PASS' AS TestResult, @RunID AS RolledBackTestRunID;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

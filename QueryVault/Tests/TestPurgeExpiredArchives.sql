/*
    Deterministic transactional integration test for retention cleanup.
    It uses an unused preallocated RunID boundary so legacy overflow data in a
    developer database cannot make the test nondeterministic.
*/

:on error exit

USE [QueryVaultDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

BEGIN TRANSACTION;
GO

:r ..\Scripts\MigrateRunPartitioning.sql
:r ..\Scripts\FixPartitionMaintenanceSwitchConstraints.sql
:r ..\Functions\ufn_EvaluatePartitionCapacity.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_canonical.sql
:r ..\Tables\QueryStore\query_store_wait_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_wait_stats_canonical.sql
:r ..\Tables\PartitionMaintenance\query_store_runtime_stats_contributor_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_runtime_stats_canonical_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_wait_stats_contributor_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_wait_stats_canonical_PartitionMaintenance.sql
:r ..\StoredProcedures\usp_ManagePartitions.sql
:r ..\StoredProcedures\usp_PurgeExpiredArchives.sql
GO

BEGIN TRY
    DECLARE @RunID INT;
    DECLARE @SourceDatabaseName SYSNAME = CONCAT(N'__QueryVaultPurgeTest_', @@SPID);

    INSERT dbo.DatabaseConfig
        (DatabaseName, ServerName, AutoDeleteEnabled, DefaultRetentionDays)
    VALUES
        (@SourceDatabaseName, @@SERVERNAME, 1, 1);

    SELECT TOP (1) @RunID = CONVERT(INT, prv.value)
    FROM sys.partition_range_values AS prv
    INNER JOIN sys.partition_functions AS pf
        ON pf.function_id = prv.function_id
    WHERE pf.name = N'PF_RunID'
        AND CONVERT(INT, prv.value) BETWEEN 20 AND 2147483646
        AND EXISTS
        (
            SELECT 1
            FROM sys.partition_range_values AS next_boundary
            WHERE next_boundary.function_id = prv.function_id
                AND CONVERT(INT, next_boundary.value) = CONVERT(INT, prv.value) + 1
        )
        AND NOT EXISTS
        (
            SELECT 1 FROM dbo.RunMetadata
            WHERE RunID = CONVERT(INT, prv.value)
        )
    ORDER BY CONVERT(INT, prv.value) DESC;

    IF @RunID IS NULL
        THROW 51100, 'The purge test requires one unused preallocated RunID boundary.', 1;

    SET IDENTITY_INSERT dbo.RunMetadata ON;
    INSERT dbo.RunMetadata
    (
        RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime,
        RunEndTime, RunStatus, DoNotDelete, RetentionDate, Comments
    )
    VALUES
    (
        @RunID, N'Transactional retention integration test', @SourceDatabaseName,
        '1999-12-31T00:00:00', '1999-12-31T00:01:00', '1999-12-31T00:02:00',
        N'Completed', 0, '2000-01-01T00:00:00',
        N'Test row; outer transaction must roll it back.'
    );
    SET IDENTITY_INSERT dbo.RunMetadata OFF;

    EXEC dbo.usp_PurgeExpiredArchives
        @AsOfDateTime = '2000-01-02T00:00:00',
        @DryRun = 0;

    IF EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID = @RunID)
        THROW 51101, 'Purge test failed: eligible metadata remains.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM sys.partition_range_values AS prv
        INNER JOIN sys.partition_functions AS pf
            ON pf.function_id = prv.function_id
        WHERE pf.name = N'PF_RunID'
            AND CONVERT(INT, prv.value) = @RunID
    )
        THROW 51102, 'Purge test failed: obsolete RunID boundary remains.', 1;

    ROLLBACK TRANSACTION;

    SELECT N'PASS' AS TestResult, @RunID AS RolledBackTestRunID;
END TRY
BEGIN CATCH
    IF OBJECTPROPERTY(OBJECT_ID(N'dbo.RunMetadata'), 'TableHasIdentity') = 1
        BEGIN TRY SET IDENTITY_INSERT dbo.RunMetadata OFF; END TRY BEGIN CATCH END CATCH;

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

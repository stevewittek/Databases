/*
    Transactional integration test for shared-overflow partition protection.

    Run from this directory with SQLCMD mode enabled so the canonical procedure
    is loaded inside the transaction. The final rollback restores both data and
    the previously deployed procedure definition.
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

:r ..\StoredProcedures\usp_ManagePartitions.sql
GO

BEGIN TRY
    DECLARE @MaxBoundary INT;
    DECLARE @RunID1 INT;
    DECLARE @RunID2 INT;
    DECLARE @Rejected BIT = 0;

    SELECT @MaxBoundary = MAX(CONVERT(INT, prv.value))
    FROM sys.partition_range_values AS prv
    JOIN sys.partition_functions AS pf
        ON pf.function_id = prv.function_id
    WHERE pf.name = N'PF_RunID';

    IF @MaxBoundary IS NULL OR @MaxBoundary > 2147482647
        THROW 51110, 'The partition test cannot allocate safe overflow RunID values.', 1;

    SET @RunID1 = @MaxBoundary + 999;
    SET @RunID2 = @MaxBoundary + 1000;

    IF $PARTITION.PF_RunID(@RunID1) <> $PARTITION.PF_RunID(@RunID2)
        THROW 51111, 'The test values do not share the overflow partition.', 1;

    INSERT dbo.query_store_runtime_stats_interval_PartitionMaintenance
        (RunID, runtime_stats_interval_id, start_time, end_time, comment)
    VALUES
        (@RunID1, -900000000001, '2000-01-01T00:00:00+00:00', '2000-01-01T00:01:00+00:00', N'safety test'),
        (@RunID2, -900000000002, '2000-01-01T00:00:00+00:00', '2000-01-01T00:01:00+00:00', N'safety test');

    BEGIN TRY
        EXEC dbo.usp_ManagePartitions
            @Operation = N'Truncate',
            @RunID = @RunID1;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%contains multiple RunID values%'
            SET @Rejected = 1;
        ELSE
            THROW;
    END CATCH;

    IF @Rejected = 0
        THROW 51112, 'A shared maintenance partition was not rejected.', 1;

    IF
    (
        SELECT COUNT_BIG(*)
        FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance
        WHERE RunID IN (@RunID1, @RunID2)
    ) <> 2
        THROW 51113, 'The rejected truncate removed test rows.', 1;

    ROLLBACK TRANSACTION;

    SELECT N'PASS' AS TestResult;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

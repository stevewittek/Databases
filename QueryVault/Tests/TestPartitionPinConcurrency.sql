/*
    Disposable-lab-only, two-session test for a pin committed while partition
    maintenance is waiting for its application lock. Requires the new procedures
    already installed and a sysadmin lab identity for DMV synchronization.

    Use SQLCMD variables Phase and Operation. For each Operation (SwitchOut,
    Truncate, MergeBoundary): run SETUP; start HOLDER in session A; after its
    "lifecycle lock held" message start WORKER in session B; wait for both;
    run VERIFY and CLEANUP. All commands must use the same isolated lab database.
    HOLDER waits for WORKER's actual application-lock wait, not a fixed sleep.
    CLEANUP is also safe after a failed test. Phase OWNERSHIP runs a separate
    rollback-only failed-purge/caller-transaction assertion (any Operation).
    Never run against a real archive.
*/
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
-- Publish context in a completed batch: dm_exec_sessions.context_info does not
-- expose a new SET CONTEXT_INFO value until the request finishes. The holder
-- also checks dm_exec_requests so synchronization reflects the active request.
IF N'$(Phase)' = N'WORKER' SET CONTEXT_INFO 0x515650494E;
IF N'$(Phase)' = N'HOLDER' SET CONTEXT_INFO 0x5156484F4C444552;
GO

DECLARE @Phase nvarchar(20) = N'$(Phase)';
DECLARE @Operation nvarchar(20) = N'$(Operation)';
DECLARE @RunID int;
DECLARE @LockResult int;
DECLARE @ExpectedError int = CASE WHEN @Operation = N'MergeBoundary' THEN 51069 ELSE 51064 END;

IF @Operation NOT IN (N'SwitchOut', N'Truncate', N'MergeBoundary')
    THROW 51500, 'Unsupported concurrency-test operation.', 1;
IF @Phase NOT IN (N'SETUP', N'HOLDER', N'WORKER', N'VERIFY', N'CLEANUP', N'OWNERSHIP')
    THROW 51501, 'Unsupported concurrency-test phase.', 1;

IF @Phase = N'OWNERSHIP'
BEGIN
    CREATE TABLE #CallerWork (ID int NOT NULL);
    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT #CallerWork VALUES (1);
        DECLARE @SourceName sysname = CONCAT(N'__QueryVaultPurgeOwnership_', @@SPID);
        DECLARE @PurgeFailed bit = 0;
        SELECT TOP (1) @RunID = CONVERT(int, prv.value)
        FROM sys.partition_range_values AS prv
        JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id
        WHERE pf.name = N'PF_RunID'
          AND CONVERT(int, prv.value) BETWEEN 20 AND 2147483645
          AND EXISTS (SELECT 1 FROM sys.partition_range_values AS nx
                      WHERE nx.function_id=prv.function_id
                        AND CONVERT(int,nx.value)=CONVERT(int,prv.value)+1)
          AND NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=CONVERT(int,prv.value))
        ORDER BY CONVERT(int,prv.value) DESC;
        IF @RunID IS NULL THROW 51515, 'No unused ownership-test boundary.', 1;

        INSERT dbo.DatabaseConfig (DatabaseName, ServerName, AutoDeleteEnabled, DefaultRetentionDays)
        VALUES (@SourceName, @@SERVERNAME, 1, 1);
        SET IDENTITY_INSERT dbo.RunMetadata ON;
        INSERT dbo.RunMetadata
            (RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime,
             RunStatus, DoNotDelete, RetentionDate)
        VALUES (@RunID, N'__QueryVaultPurgeOwnership', @SourceName,
                '1899-01-01', '1899-01-02', N'Completed', 0, '1900-01-01');
        SET IDENTITY_INSERT dbo.RunMetadata OFF;

        -- Deliberately occupied maintenance partition makes SwitchOut reject
        -- the purge before any facts can be destroyed.
        INSERT dbo.query_store_runtime_stats_interval_PartitionMaintenance
            (RunID, runtime_stats_interval_id, start_time, end_time, comment)
        VALUES (@RunID, -915000002, '1899-01-01T00:00:00+00:00',
                '1899-01-02T00:00:00+00:00', N'__QueryVaultPurgeOwnership');
        SET XACT_ABORT ON;
        BEGIN TRY
            EXEC dbo.usp_PurgeExpiredArchives @AsOfDateTime='1900-01-02', @DryRun=0;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() <> 51001 THROW;
            SET @PurgeFailed=1;
        END CATCH;

        IF @PurgeFailed=0 THROW 51516, 'Expected purge failure was not raised.', 1;
        IF @@TRANCOUNT<>1 OR XACT_STATE()<>1
            THROW 51517, 'Failed purge damaged the caller transaction.', 1;
        IF (@@OPTIONS & 16384)=0
            THROW 51520, 'Purge did not restore the caller XACT_ABORT option.', 1;
        IF NOT EXISTS (SELECT 1 FROM #CallerWork WHERE ID=1)
            THROW 51518, 'Failed purge rolled back earlier caller work.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID)
            THROW 51519, 'Failed purge lost its run metadata.', 1;
        ROLLBACK;
        SELECT N'OWNERSHIP PASS' AS TestResult;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        BEGIN TRY SET IDENTITY_INSERT dbo.RunMetadata OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH;
    RETURN;
END;

IF @Phase = N'SETUP'
BEGIN
    IF OBJECT_ID(N'dbo.__QueryVaultPinConcurrencyFixture') IS NOT NULL
        THROW 51502, 'A concurrency fixture already exists; clean it up explicitly.', 1;

    -- Use an existing empty, isolated partition so the test changes no boundaries.
    SELECT TOP (1) @RunID = CONVERT(int, prv.value)
    FROM sys.partition_range_values AS prv
    JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id
    WHERE pf.name = N'PF_RunID'
      AND CONVERT(int, prv.value) BETWEEN 20 AND 2147483645
      AND EXISTS (SELECT 1 FROM sys.partition_range_values AS nx
                  WHERE nx.function_id = prv.function_id
                    AND CONVERT(int, nx.value) = CONVERT(int, prv.value) + 1)
      AND NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID = CONVERT(int, prv.value))
      AND NOT EXISTS (SELECT 1 FROM dbo.query_store_runtime_stats_interval
                      WHERE RunID = CONVERT(int, prv.value))
      AND NOT EXISTS (SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance
                      WHERE RunID = CONVERT(int, prv.value))
    ORDER BY CONVERT(int, prv.value) DESC;
    IF @RunID IS NULL THROW 51503, 'No unused preallocated test partition.', 1;

    BEGIN TRANSACTION;
    CREATE TABLE dbo.__QueryVaultPinConcurrencyFixture
    (
        RunID int NOT NULL PRIMARY KEY,
        Operation nvarchar(20) NOT NULL,
        WorkerPassed bit NOT NULL DEFAULT 0
    );
    INSERT dbo.__QueryVaultPinConcurrencyFixture (RunID, Operation) VALUES (@RunID, @Operation);

    IF @Operation <> N'MergeBoundary'
    BEGIN
        SET IDENTITY_INSERT dbo.RunMetadata ON;
        INSERT dbo.RunMetadata
            (RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime, RunStatus, DoNotDelete)
        VALUES (@RunID, N'__QueryVaultPinConcurrency', N'__QueryVaultPinConcurrency',
                '2026-01-01', '2026-01-02', N'Completed', 0);
        SET IDENTITY_INSERT dbo.RunMetadata OFF;
    END;

    IF @Operation = N'SwitchOut'
        INSERT dbo.query_store_runtime_stats_interval
            (RunID, runtime_stats_interval_id, start_time, end_time, comment)
        VALUES (@RunID, -915000001, '2026-01-01T00:00:00+00:00',
                '2026-01-02T00:00:00+00:00', N'__QueryVaultPinConcurrency');
    IF @Operation = N'Truncate'
        INSERT dbo.query_store_runtime_stats_interval_PartitionMaintenance
            (RunID, runtime_stats_interval_id, start_time, end_time, comment)
        VALUES (@RunID, -915000001, '2026-01-01T00:00:00+00:00',
                '2026-01-02T00:00:00+00:00', N'__QueryVaultPinConcurrency');
    COMMIT;
    SELECT N'SETUP PASS' AS TestResult, @RunID AS RunID;
    RETURN;
END;

IF OBJECT_ID(N'dbo.__QueryVaultPinConcurrencyFixture') IS NULL
    THROW 51504, 'Run SETUP first.', 1;
SELECT @RunID = RunID FROM dbo.__QueryVaultPinConcurrencyFixture WHERE Operation = @Operation;
IF @RunID IS NULL THROW 51505, 'Operation differs from the prepared fixture.', 1;

IF @Phase = N'HOLDER'
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @LockResult = sys.sp_getapplock @Resource=N'QueryVault.PF_RunID',
            @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=10000;
        IF @LockResult < 0 THROW 51506, 'Could not obtain test lifecycle lock.', 1;
        RAISERROR ('lifecycle lock held', 10, 1) WITH NOWAIT;

        DECLARE @Deadline datetime2 = DATEADD(SECOND, 20, SYSUTCDATETIME());
        WHILE NOT EXISTS
        (
            SELECT 1 FROM sys.dm_tran_locks AS locks
            JOIN sys.dm_exec_requests AS requests ON requests.session_id = locks.request_session_id
            WHERE requests.context_info = 0x515650494E
              AND locks.resource_type = N'APPLICATION'
              AND locks.resource_database_id = DB_ID()
              AND locks.request_status = N'WAIT'
        )
        BEGIN
            IF SYSUTCDATETIME() >= @Deadline
                THROW 51507, 'WORKER never waited for the lifecycle lock.', 1;
            WAITFOR DELAY '00:00:00.100';
        END;

        IF @Operation = N'MergeBoundary'
        BEGIN
            SET IDENTITY_INSERT dbo.RunMetadata ON;
            INSERT dbo.RunMetadata
                (RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime, RunStatus, DoNotDelete)
            VALUES (@RunID, N'__QueryVaultPinConcurrency', N'__QueryVaultPinConcurrency',
                    '2026-01-01', '2026-01-02', N'Completed', 1);
            SET IDENTITY_INSERT dbo.RunMetadata OFF;
        END
        ELSE
            UPDATE dbo.RunMetadata SET DoNotDelete = 1 WHERE RunID = @RunID;
        COMMIT;
        SELECT N'Pin committed before worker acquired lifecycle lock' AS TestResult;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
    RETURN;
END;

IF @Phase = N'WORKER'
BEGIN
    SET CONTEXT_INFO 0x515650494E;
    DECLARE @Rejected bit = 0;
    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC dbo.usp_ManagePartitions @Operation=@Operation, @RunID=@RunID;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> @ExpectedError
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
            THROW;
        END;
        SET @Rejected = 1;
    END CATCH;
    IF @Rejected = 0
    BEGIN
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW 51508, 'Maintenance accepted a pin committed while it waited.', 1;
    END;
    IF @@TRANCOUNT <> 1 OR XACT_STATE() <> 1
    BEGIN
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW 51509, 'Rejected maintenance damaged its caller transaction.', 1;
    END;
    ROLLBACK;
    UPDATE dbo.__QueryVaultPinConcurrencyFixture SET WorkerPassed=1 WHERE RunID=@RunID;
    SELECT N'WORKER PASS' AS TestResult;
    RETURN;
END;

IF @Phase = N'VERIFY'
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.__QueryVaultPinConcurrencyFixture WHERE WorkerPassed=1)
        THROW 51510, 'Worker did not prove rejection.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID AND DoNotDelete=1)
        THROW 51511, 'Pinned metadata was not preserved.', 1;
    IF @Operation=N'SwitchOut' AND NOT EXISTS
       (SELECT 1 FROM dbo.query_store_runtime_stats_interval WHERE RunID=@RunID AND runtime_stats_interval_id=-915000001)
        THROW 51512, 'Pinned source facts were switched.', 1;
    IF @Operation=N'Truncate' AND NOT EXISTS
       (SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance WHERE RunID=@RunID AND runtime_stats_interval_id=-915000001)
        THROW 51513, 'Pinned maintenance facts were truncated.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.partition_range_values AS prv
                   JOIN sys.partition_functions AS pf ON pf.function_id=prv.function_id
                   WHERE pf.name=N'PF_RunID' AND CONVERT(int,prv.value)=@RunID)
        THROW 51514, 'Pinned boundary was removed.', 1;
    SELECT N'VERIFY PASS' AS TestResult, @Operation AS Operation;
    RETURN;
END;

IF @Phase = N'CLEANUP'
BEGIN
    BEGIN TRANSACTION;
    DELETE dbo.query_store_runtime_stats_interval
    WHERE RunID=@RunID AND runtime_stats_interval_id=-915000001 AND comment=N'__QueryVaultPinConcurrency';
    DELETE dbo.query_store_runtime_stats_interval_PartitionMaintenance
    WHERE RunID=@RunID AND runtime_stats_interval_id=-915000001 AND comment=N'__QueryVaultPinConcurrency';
    DELETE dbo.RunMetadata WHERE RunID=@RunID AND RunName=N'__QueryVaultPinConcurrency';
    DROP TABLE dbo.__QueryVaultPinConcurrencyFixture;
    COMMIT;
    SELECT N'CLEANUP PASS' AS TestResult;
END;

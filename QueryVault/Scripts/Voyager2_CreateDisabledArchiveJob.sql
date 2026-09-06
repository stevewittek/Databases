/*
    Voyager 2 QueryVault SQL Agent job and least-privilege execution identity.

    Despite the historical file name, the hardened job is enabled and runs
    daily. The login password is generated inside SQL Server and is never
    returned or persisted in this repository.
*/

USE [master];
GO

SET NOCOUNT ON;

IF SUSER_ID(N'queryvault_agent') IS NULL
BEGIN
    DECLARE @GeneratedPassword NVARCHAR(128) =
        N'Qv!' + CONVERT(NVARCHAR(64), CRYPT_GEN_RANDOM(32), 2) + N'a9Z';
    DECLARE @CreateLoginSql NVARCHAR(MAX) =
        N'CREATE LOGIN [queryvault_agent] WITH PASSWORD = N'''
        + REPLACE(@GeneratedPassword, N'''', N'''''')
        + N''', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;';

    EXEC sys.sp_executesql @CreateLoginSql;
END;
ELSE
BEGIN
    ALTER LOGIN [queryvault_agent] ENABLE;
    ALTER LOGIN [queryvault_agent] WITH CHECK_POLICY = ON;
END;
GO

USE [QueryVaultDB];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF USER_ID(N'queryvault_agent') IS NULL
    CREATE USER [queryvault_agent] FOR LOGIN [queryvault_agent];
GO

IF DATABASE_PRINCIPAL_ID(N'queryvault_executor') IS NULL
    CREATE ROLE [queryvault_executor] AUTHORIZATION [dbo];
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members
    WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'queryvault_executor')
      AND member_principal_id = USER_ID(N'queryvault_agent')
)
    ALTER ROLE [queryvault_executor] ADD MEMBER [queryvault_agent];
GO

GRANT EXECUTE ON dbo.usp_ArchiveQueryStore TO [queryvault_agent];
GRANT EXECUTE ON dbo.usp_PurgeExpiredArchives TO [queryvault_agent];

GRANT SELECT, UPDATE ON dbo.DatabaseConfig TO [queryvault_executor];
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.RunMetadata TO [queryvault_executor];

GRANT INSERT, ALTER ON dbo.query_store_query TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_query_text TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_plan TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_runtime_stats TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_runtime_stats_interval TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_wait_stats TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_runtime_stats_contributor TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_runtime_stats_canonical TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_wait_stats_contributor TO [queryvault_executor];
GRANT INSERT, ALTER ON dbo.query_store_wait_stats_canonical TO [queryvault_executor];

GRANT ALTER ON dbo.query_store_query_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_query_text_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_plan_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_runtime_stats_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_runtime_stats_interval_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_wait_stats_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_runtime_stats_contributor_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_runtime_stats_canonical_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_wait_stats_contributor_PartitionMaintenance TO [queryvault_executor];
GRANT ALTER ON dbo.query_store_wait_stats_canonical_PartitionMaintenance TO [queryvault_executor];

-- Required only when usp_ArchiveQueryStore extends PF_RunID/PS_RunID.
GRANT ALTER ANY DATASPACE TO [queryvault_executor];
GO

UPDATE dbo.DatabaseConfig
SET DefaultDaysToArchive = 1,
    ScheduleType = N'Daily',
    ScheduleTime = CAST(N'02:30:00' AS TIME),
    DefaultRetentionDays = 90,
    AutoDeleteEnabled = 1,
    ModifiedDate = SYSUTCDATETIME(),
    ModifiedBy = SUSER_SNAME()
WHERE IsEnabled = 1
  AND ServerName = @@SERVERNAME;
GO

DECLARE @DatabaseName SYSNAME;
DECLARE @GrantSql NVARCHAR(MAX);

DECLARE source_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT DatabaseName
FROM dbo.DatabaseConfig
WHERE IsEnabled = 1
  AND ServerName = @@SERVERNAME
ORDER BY DatabaseName;

OPEN source_cursor;
FETCH NEXT FROM source_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF DB_ID(@DatabaseName) IS NULL
        THROW 51002, 'An enabled QueryVault source database does not exist.', 1;

    SET @GrantSql = N'USE ' + QUOTENAME(@DatabaseName) + N';
        IF USER_ID(N''queryvault_agent'') IS NULL
            CREATE USER [queryvault_agent] FOR LOGIN [queryvault_agent];
        GRANT VIEW DATABASE PERFORMANCE STATE TO [queryvault_agent];
        GRANT VIEW DATABASE STATE TO [queryvault_agent];';

    EXEC sys.sp_executesql @GrantSql;
    FETCH NEXT FROM source_cursor INTO @DatabaseName;
END;

CLOSE source_cursor;
DEALLOCATE source_cursor;
GO

USE [msdb];
GO

DECLARE @JobName SYSNAME = N'QueryVault - Archive Voyager 2 Lab Databases';
DECLARE @JobID UNIQUEIDENTIFIER;

SELECT @JobID = job_id
FROM dbo.sysjobs
WHERE name = @JobName;

IF @JobID IS NULL
BEGIN
    EXEC dbo.sp_add_job
        @job_name = @JobName,
        @enabled = 1,
        @description = N'Daily QueryVault archive and retention purge for enabled Voyager 2 sources.',
        @category_name = N'Database Maintenance',
        @owner_login_name = N'queryvault_agent',
        @job_id = @JobID OUTPUT;
END;

DECLARE @ArchiveCommand NVARCHAR(MAX) = N'
SET NOCOUNT ON;

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @RunName NVARCHAR(255);
DECLARE @StartDateTime DATETIME2(7);
DECLARE @EndDateTime DATETIME2(7);
DECLARE @DefaultDaysToArchive INT;
DECLARE @FailureCount INT = 0;

DECLARE database_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT DatabaseName, DefaultDaysToArchive
FROM dbo.DatabaseConfig
WHERE IsEnabled = 1
  AND ServerName = @@SERVERNAME
ORDER BY DatabaseName;

OPEN database_cursor;
FETCH NEXT FROM database_cursor INTO @DatabaseName, @DefaultDaysToArchive;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @EndDateTime = SYSUTCDATETIME();

        SELECT @StartDateTime = MAX(EndDateTime)
        FROM dbo.RunMetadata
        WHERE SourceDatabaseName = @DatabaseName
          AND SourceServerName = @@SERVERNAME
          AND RunStatus = N''Completed'';

        SET @StartDateTime = ISNULL(
            @StartDateTime,
            DATEADD(DAY, -@DefaultDaysToArchive, @EndDateTime)
        );
        SET @RunName = N''SQL Agent archive - ''
            + CONVERT(NVARCHAR(30), @StartDateTime, 126)
            + N'' through ''
            + CONVERT(NVARCHAR(30), @EndDateTime, 126);

        EXEC dbo.usp_ArchiveQueryStore
            @SourceDatabaseName = @DatabaseName,
            @RunName = @RunName,
            @StartDateTime = @StartDateTime,
            @EndDateTime = @EndDateTime,
            @DoNotDelete = 0;
    END TRY
    BEGIN CATCH
        SET @FailureCount += 1;
        PRINT N''QueryVault archive failed for '' + QUOTENAME(@DatabaseName) + N'': '' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM database_cursor INTO @DatabaseName, @DefaultDaysToArchive;
END;

CLOSE database_cursor;
DEALLOCATE database_cursor;

IF @FailureCount > 0
    THROW 51000, ''One or more QueryVault archives failed. Review job history and RunMetadata.'', 1;
';

IF NOT EXISTS
(
    SELECT 1 FROM dbo.sysjobsteps
    WHERE job_id = @JobID AND step_id = 1
)
BEGIN
    EXEC dbo.sp_add_jobstep
        @job_id = @JobID,
        @step_name = N'Archive enabled databases',
        @step_id = 1,
        @subsystem = N'TSQL',
        @database_name = N'QueryVaultDB',
        @command = @ArchiveCommand,
        @on_success_action = 3,
        @on_fail_action = 2;
END
ELSE
BEGIN
    EXEC dbo.sp_update_jobstep
        @job_id = @JobID,
        @step_id = 1,
        @step_name = N'Archive enabled databases',
        @subsystem = N'TSQL',
        @database_name = N'QueryVaultDB',
        @command = @ArchiveCommand,
        @on_success_action = 3,
        @on_fail_action = 2;
END;

IF NOT EXISTS
(
    SELECT 1 FROM dbo.sysjobsteps
    WHERE job_id = @JobID AND step_name = N'Purge expired unprotected runs'
)
BEGIN
    EXEC dbo.sp_add_jobstep
        @job_id = @JobID,
        @step_name = N'Purge expired unprotected runs',
        @step_id = 2,
        @subsystem = N'TSQL',
        @database_name = N'QueryVaultDB',
        @command = N'EXEC dbo.usp_PurgeExpiredArchives;',
        @on_success_action = 1,
        @on_fail_action = 2;
END
ELSE
BEGIN
    EXEC dbo.sp_update_jobstep
        @job_id = @JobID,
        @step_id = 2,
        @step_name = N'Purge expired unprotected runs',
        @subsystem = N'TSQL',
        @database_name = N'QueryVaultDB',
        @command = N'EXEC dbo.usp_PurgeExpiredArchives;',
        @on_success_action = 1,
        @on_fail_action = 2;
END;

IF NOT EXISTS
(
    SELECT 1 FROM dbo.sysjobservers
    WHERE job_id = @JobID
)
BEGIN
    EXEC dbo.sp_add_jobserver
        @job_id = @JobID,
        @server_name = N'(LOCAL)';
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.sysjobschedules AS js
    JOIN dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
    WHERE js.job_id = @JobID
      AND s.name = N'Voyager2 - Daily 0230 UTC'
)
BEGIN
    EXEC dbo.sp_add_jobschedule
        @job_id = @JobID,
        @name = N'Voyager2 - Daily 0230 UTC',
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @active_start_time = 023000;
END;

EXEC dbo.sp_update_job
    @job_id = @JobID,
    @enabled = 1,
    @description = N'Daily QueryVault archive and retention purge for enabled Voyager 2 sources.',
    @owner_login_name = N'queryvault_agent';

SELECT
    j.name AS JobName,
    j.enabled AS IsEnabled,
    SUSER_SNAME(j.owner_sid) AS OwnerName,
    COUNT(DISTINCT s.step_id) AS StepCount,
    COUNT(DISTINCT sc.schedule_id) AS ScheduleCount
FROM dbo.sysjobs AS j
LEFT JOIN dbo.sysjobsteps AS s ON s.job_id = j.job_id
LEFT JOIN dbo.sysjobschedules AS sc ON sc.job_id = j.job_id
WHERE j.job_id = @JobID
GROUP BY j.name, j.enabled, j.owner_sid;
GO

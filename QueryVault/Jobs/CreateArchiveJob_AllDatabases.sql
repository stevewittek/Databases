/*
	SQL Agent Job: Automated QueryStore Archiving for All Enabled Databases

	This job runs on a schedule and archives QueryStore data for all enabled databases
	in the DatabaseConfig table. It uses the configured schedule and date ranges.
*/

USE msdb;
GO

DECLARE @JobName NVARCHAR(128) = N'QueryVault - Archive All Enabled Databases';
DECLARE @JobDescription NVARCHAR(512) = N'Archives QueryStore data from all enabled databases to QueryVaultDB';
DECLARE @ScheduleName NVARCHAR(128) = N'Daily at 2 AM - All Databases';

-- Check if job already exists, delete if it does
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
	PRINT 'Job "' + @JobName + '" already exists. Deleting...';
	EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

-- Create the job
EXEC msdb.dbo.sp_add_job
	@job_name = @JobName,
	@enabled = 1,
	@description = @JobDescription,
	@category_name = N'Database Maintenance',
	@owner_login_name = N'sa'; -- Change to appropriate owner

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
	@job_name = @JobName,
	@step_name = N'Archive All Enabled Databases',
	@subsystem = N'TSQL',
	@database_name = N'QueryVaultDB',
	@command = N'
SET NOCOUNT ON;

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @RunName NVARCHAR(255);
DECLARE @StartDateTime DATETIME2(7);
DECLARE @EndDateTime DATETIME2(7);
DECLARE @DaysToArchive INT;
DECLARE @ErrorMessage NVARCHAR(4000);
DECLARE @TotalDatabases INT = 0;
DECLARE @SuccessCount INT = 0;
DECLARE @FailCount INT = 0;

-- Cursor for all enabled databases
DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT 
	DatabaseName,
	DefaultDaysToArchive
FROM dbo.DatabaseConfig
WHERE IsEnabled = 1
ORDER BY DatabaseName;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName, @DaysToArchive;

WHILE @@FETCH_STATUS = 0
BEGIN
	SET @TotalDatabases = @TotalDatabases + 1;

	BEGIN TRY
		PRINT ''Processing database: '' + @DatabaseName;

		-- Resume from the last successfully archived endpoint. This closes any
		-- gap left by a failed scheduled run. Use the configured lookback only
		-- when this source has no completed archive yet.
		SET @EndDateTime = SYSUTCDATETIME();
		SELECT @StartDateTime = MAX(EndDateTime)
		FROM dbo.RunMetadata
		WHERE SourceDatabaseName = @DatabaseName
		  AND SourceServerName = @@SERVERNAME
		  AND RunStatus = N''Completed'';

		SET @StartDateTime = ISNULL(
			@StartDateTime,
			DATEADD(DAY, -@DaysToArchive, @EndDateTime)
		);
		SET @RunName = ''Scheduled Archive - ''
			+ CONVERT(VARCHAR(30), @StartDateTime, 126)
			+ '' through ''
			+ CONVERT(VARCHAR(30), @EndDateTime, 126);

		-- Execute archive procedure
		EXEC dbo.usp_ArchiveQueryStore
			@SourceDatabaseName = @DatabaseName,
			@RunName = @RunName,
			@StartDateTime = @StartDateTime,
			@EndDateTime = @EndDateTime,
			@DoNotDelete = 0;

		SET @SuccessCount = @SuccessCount + 1;
		PRINT ''Successfully archived: '' + @DatabaseName;
	END TRY
	BEGIN CATCH
		SET @FailCount = @FailCount + 1;
		SET @ErrorMessage = ''Error archiving '' + @DatabaseName + '': '' + ERROR_MESSAGE();
		PRINT @ErrorMessage;
		-- Continue with next database instead of failing entire job
	END CATCH

	FETCH NEXT FROM db_cursor INTO @DatabaseName, @DaysToArchive;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Summary
PRINT '''';
PRINT ''Archive Job Summary:'';
PRINT ''Total Databases: '' + CAST(@TotalDatabases AS VARCHAR(10));
PRINT ''Successful: '' + CAST(@SuccessCount AS VARCHAR(10));
PRINT ''Failed: '' + CAST(@FailCount AS VARCHAR(10));

-- If any database failed, raise error to mark job as failed
IF @FailCount > 0
BEGIN
	RAISERROR(''One or more databases failed to archive. Check job history for details.'', 16, 1);
END
',
	@on_success_action = 1, -- Quit with success
	@on_fail_action = 2, -- Quit with failure
	@retry_attempts = 0,
	@retry_interval = 0;

-- Set job to start at step 1
EXEC msdb.dbo.sp_update_job
	@job_name = @JobName,
	@start_step_id = 1;

-- Add schedule (Daily at 2 AM)
EXEC msdb.dbo.sp_add_jobschedule
	@job_name = @JobName,
	@name = @ScheduleName,
	@enabled = 1,
	@freq_type = 4, -- Daily
	@freq_interval = 1, -- Every 1 day
	@active_start_time = 020000; -- 2:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
	@job_name = @JobName,
	@server_name = N'(LOCAL)';

PRINT 'SQL Agent job "' + @JobName + '" created successfully';
GO

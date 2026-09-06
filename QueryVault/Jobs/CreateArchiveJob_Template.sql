/*
	SQL Agent Job Template: QueryStore Archiving Job

	This script creates a SQL Agent job that archives QueryStore data on a schedule.
	You can customize this template for each database you want to archive.

	INSTRUCTIONS:
	1. Replace @DatabaseName with the name of the database to archive
	2. Replace @JobSchedule with your desired schedule (defaults to daily at 2 AM)
	3. Adjust @DaysToArchive if you want a different lookback period
	4. Run this script to create the job
*/

USE msdb;
GO

-- Configuration variables
DECLARE @DatabaseName NVARCHAR(128) = 'YourDatabaseName'; -- CHANGE THIS
DECLARE @JobName NVARCHAR(128);
DECLARE @JobDescription NVARCHAR(512);
DECLARE @ScheduleName NVARCHAR(128);

SET @JobName = N'QueryVault - Archive ' + @DatabaseName;
SET @JobDescription = N'Archives QueryStore data from ' + @DatabaseName + N' to QueryVaultDB';
SET @ScheduleName = N'Daily at 2 AM - ' + @DatabaseName;

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
	@step_name = N'Archive QueryStore Data',
	@subsystem = N'TSQL',
	@database_name = N'QueryVaultDB',
	@command = N'
DECLARE @RunName NVARCHAR(255);
DECLARE @StartDateTime DATETIME2(7);
DECLARE @EndDateTime DATETIME2(7);
DECLARE @DaysToArchive INT;

-- Get configuration for the database
SELECT 
	@DaysToArchive = DefaultDaysToArchive
FROM dbo.DatabaseConfig
WHERE DatabaseName = ''@DatabaseName''
  AND IsEnabled = 1;

-- If database not configured, fail the job
IF @DaysToArchive IS NULL
BEGIN
	RAISERROR(''Database not found or not enabled in configuration'', 16, 1);
	RETURN;
END

-- Resume from the last successfully archived endpoint. This closes any gap
-- left by a failed scheduled run. Use the configured lookback only when this
-- source has no completed archive yet.
SET @EndDateTime = SYSUTCDATETIME();
SELECT @StartDateTime = MAX(EndDateTime)
FROM dbo.RunMetadata
WHERE SourceDatabaseName = ''@DatabaseName''
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
	@SourceDatabaseName = ''@DatabaseName'',
	@RunName = @RunName,
	@StartDateTime = @StartDateTime,
	@EndDateTime = @EndDateTime,
	@DoNotDelete = 0;
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
PRINT 'Remember to replace @DatabaseName placeholder in the job step command with the actual database name';
GO

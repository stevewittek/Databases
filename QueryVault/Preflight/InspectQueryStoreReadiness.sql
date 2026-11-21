/* Read-only source inspection. Supply @ExpectedDatabase nvarchar(128) and
   @RequireAzureSqlDatabase bit as parameters (or DECLARE them in the same batch).
   No capture, query text, plans, application rows, grants or configuration changes.
   Numeric output only; NULL permission/capability means unknown, not permission granted. */
IF @ExpectedDatabase IS NULL OR LEN(@ExpectedDatabase) = 0
    THROW 51400, 'An explicit expected database is required.', 1;
IF @RequireAzureSqlDatabase IS NULL
    THROW 51400, 'An explicit Azure engine requirement is required.', 1;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> @ExpectedDatabase COLLATE Latin1_General_100_BIN2
   OR DATALENGTH(DB_NAME()) <> DATALENGTH(@ExpectedDatabase)
    THROW 51401, 'Source database did not match the approved target.', 1;
DECLARE @EngineEdition int = CONVERT(int, SERVERPROPERTY('EngineEdition'));
IF @EngineEdition IS NULL OR @EngineEdition NOT IN (2, 3, 4, 5, 8)
    THROW 51402, 'Source engine is outside the supported readiness scope.', 1;
IF @RequireAzureSqlDatabase = 1 AND @EngineEdition <> 5
    THROW 51402, 'Source is not an Azure SQL Database.', 1;

DECLARE @OptionsReadStatus int = 1,
        @ActualState int, @DesiredState int, @ReadOnlyReason bigint,
        @CurrentStorageMB bigint, @MaximumStorageMB bigint,
        @IntervalMinutes bigint, @FlushIntervalSeconds bigint, @StaleDays bigint, @CaptureMode int;
/* Execute a fixed, noninterpolated statement at a lower scope so missing-view and
   permission failures can be reported without leaking the underlying error text. */
BEGIN TRY
    EXEC sys.sp_executesql N'
        SELECT @status = 0, @actual = CONVERT(int, actual_state),
               @desired = CONVERT(int, desired_state), @reason = CONVERT(bigint, readonly_reason),
               @current = CONVERT(bigint, current_storage_size_mb),
               @maximum = CONVERT(bigint, max_storage_size_mb),
               @interval = CONVERT(bigint, interval_length_minutes),
               @flush = CONVERT(bigint, flush_interval_seconds),
               @stale = CONVERT(bigint, stale_query_threshold_days),
               @capture = CONVERT(int, query_capture_mode)
        FROM sys.database_query_store_options;',
        N'@status int OUTPUT, @actual int OUTPUT, @desired int OUTPUT, @reason bigint OUTPUT,
          @current bigint OUTPUT, @maximum bigint OUTPUT, @interval bigint OUTPUT,
          @flush bigint OUTPUT, @stale bigint OUTPUT, @capture int OUTPUT',
        @status = @OptionsReadStatus OUTPUT, @actual = @ActualState OUTPUT,
        @desired = @DesiredState OUTPUT, @reason = @ReadOnlyReason OUTPUT,
        @current = @CurrentStorageMB OUTPUT, @maximum = @MaximumStorageMB OUTPUT,
        @interval = @IntervalMinutes OUTPUT, @stale = @StaleDays OUTPUT,
        @flush = @FlushIntervalSeconds OUTPUT,
        @capture = @CaptureMode OUTPUT;
END TRY
BEGIN CATCH
    SELECT @OptionsReadStatus = 2, @ActualState = NULL, @DesiredState = NULL,
           @ReadOnlyReason = NULL, @CurrentStorageMB = NULL, @MaximumStorageMB = NULL,
           @IntervalMinutes = NULL, @FlushIntervalSeconds = NULL, @StaleDays = NULL, @CaptureMode = NULL;
END CATCH;

SELECT CONVERT(int, 1) AS TargetMatched,
       @EngineEdition AS EngineEdition,
       CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) AS ProductMajorVersion,
       (SELECT CONVERT(int, compatibility_level) FROM sys.databases WHERE database_id = DB_ID()) AS CompatibilityLevel,
       HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'VIEW DATABASE STATE') AS ViewDatabaseState,
       HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'VIEW DATABASE PERFORMANCE STATE') AS ViewDatabasePerformanceState,
       @OptionsReadStatus AS OptionsReadStatus,
       @ActualState AS ActualState, @DesiredState AS DesiredState,
       @ReadOnlyReason AS ReadOnlyReason, @CurrentStorageMB AS CurrentStorageMB,
       @MaximumStorageMB AS MaximumStorageMB, @IntervalMinutes AS IntervalMinutes,
       @FlushIntervalSeconds AS FlushIntervalSeconds,
       @StaleDays AS StaleDays, @CaptureMode AS CaptureMode,
       CASE WHEN OBJECT_ID(N'sys.query_store_runtime_stats') IS NOT NULL THEN 1 ELSE NULL END AS RuntimeStatsViewVisible,
       CASE WHEN OBJECT_ID(N'sys.query_store_runtime_stats_interval') IS NOT NULL THEN 1 ELSE NULL END AS RuntimeIntervalsViewVisible,
       CASE WHEN OBJECT_ID(N'sys.query_store_wait_stats') IS NOT NULL THEN 1 ELSE NULL END AS WaitStatsViewVisible,
       CASE WHEN EXISTS (SELECT 1 FROM sys.all_columns
                         WHERE object_id = OBJECT_ID(N'sys.database_query_store_options')
                           AND name = N'wait_stats_capture_mode') THEN 1 ELSE NULL END AS WaitCaptureOptionVisible;

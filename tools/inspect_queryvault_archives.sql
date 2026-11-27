/* Read-only inventory for SQL Server. Run as a new SSMS query on the intended
   instance with an account that can see the archive metadata and Agent jobs.
   No job commands, query text or credentials are returned. */
SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000;

SELECT CONVERT(sysname, SERVERPROPERTY('MachineName')) AS machine_name,
       CONVERT(sysname, SERVERPROPERTY('ServerName')) AS instance_name,
       CONVERT(nvarchar(128), SERVERPROPERTY('Edition')) AS edition,
       CONVERT(nvarchar(32), SERVERPROPERTY('ProductVersion')) AS product_version,
       SYSUTCDATETIME() AS inspected_at_utc;

CREATE TABLE #qv_archive_inventory
(
    database_name sysname NOT NULL,
    state_desc nvarchar(60) NOT NULL,
    compatibility_level tinyint NOT NULL,
    created_at datetime NOT NULL,
    is_read_only bit NOT NULL,
    inspection_status nvarchar(160) NOT NULL,
    core_archive bit NULL,
    canonical_contract bit NULL,
    partition_guard_51073 bit NULL,
    partition_procedure_modified_at datetime NULL,
    max_runid_partition_boundary bigint NULL,
    analytics_objects_present int NULL,
    periods_reads_analytics_labels bit NULL,
    protection_note_present bit NULL,
    run_count bigint NULL,
    last_completed_run_utc datetime2(7) NULL,
    last_completed_capture_end_utc datetime2(7) NULL,
    last_failed_run_utc datetime2(7) NULL
);

DECLARE @name sysname, @state nvarchar(60), @compat tinyint, @created datetime,
        @read_only bit, @named_candidate bit, @sql nvarchar(max);
DECLARE qv_db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, state_desc, compatibility_level, create_date, is_read_only,
           CONVERT(bit, CASE WHEN name LIKE N'%QueryVault%' OR name LIKE N'%Query%Vault%' THEN 1 ELSE 0 END)
    FROM sys.databases WHERE database_id > 4 ORDER BY name;

OPEN qv_db_cursor;
FETCH NEXT FROM qv_db_cursor INTO @name, @state, @compat, @created, @read_only, @named_candidate;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @state <> N'ONLINE' OR ISNULL(HAS_DBACCESS(@name), 0) = 0
    BEGIN
        IF @named_candidate = 1
            INSERT #qv_archive_inventory (database_name, state_desc, compatibility_level, created_at, is_read_only, inspection_status)
            VALUES (@name, @state, @compat, @created, @read_only, N'Not online or not accessible');
    END
    ELSE
    BEGIN TRY
        SET @sql = N'USE ' + QUOTENAME(@name) + N';
            DECLARE @runs int = OBJECT_ID(N''dbo.RunMetadata'', N''U''),
                    @archiver int = OBJECT_ID(N''dbo.usp_ArchiveQueryStore'', N''P''),
                    @partition_proc int = OBJECT_ID(N''dbo.usp_ManagePartitions'', N''P''),
                    @run_count bigint, @success datetime2(7), @coverage datetime2(7), @failed datetime2(7);
            IF @candidate = 0 AND @archiver IS NULL AND
                (@runs IS NULL OR OBJECT_ID(N''dbo.query_store_plan'', N''U'') IS NULL) RETURN;

            IF @runs IS NOT NULL AND
                (SELECT COUNT(*) FROM sys.columns WHERE object_id = @runs
                    AND name IN (N''RunStatus'', N''RunEndTime'', N''EndDateTime'', N''RunStartTime'')) = 4
                EXEC sys.sp_executesql N''SELECT @n = COUNT_BIG(*),
                    @ok = MAX(CASE WHEN RunStatus IN (N''''Completed'''', N''''Success'''') THEN RunEndTime END),
                    @end = MAX(CASE WHEN RunStatus IN (N''''Completed'''', N''''Success'''') THEN EndDateTime END),
                    @err = MAX(CASE WHEN RunStatus = N''''Failed'''' THEN COALESCE(RunEndTime, RunStartTime) END)
                    FROM dbo.RunMetadata;'',
                    N''@n bigint OUTPUT, @ok datetime2(7) OUTPUT, @end datetime2(7) OUTPUT, @err datetime2(7) OUTPUT'',
                    @n = @run_count OUTPUT, @ok = @success OUTPUT, @end = @coverage OUTPUT, @err = @failed OUTPUT;

            INSERT #qv_archive_inventory
            SELECT DB_NAME(), @state, @compat, @created, @read_only,
               CASE WHEN @runs IS NOT NULL AND @run_count IS NULL THEN N''Visible schema, nonstandard run metadata''
                    WHEN @runs IS NULL THEN N''No visible archive run table'' ELSE N''Inspected'' END,
               CASE WHEN @runs IS NOT NULL AND @archiver IS NOT NULL THEN 1 ELSE 0 END,
               CASE WHEN OBJECT_ID(N''dbo.query_store_runtime_stats_canonical'', N''U'') IS NOT NULL
                     AND OBJECT_ID(N''dbo.query_store_wait_stats_canonical'', N''U'') IS NOT NULL
                     AND OBJECT_ID(N''qv_report.query_period_metrics'', N''V'') IS NOT NULL THEN 1 ELSE 0 END,
               CASE WHEN OBJECT_DEFINITION(@partition_proc) IS NULL THEN NULL
                    WHEN OBJECT_DEFINITION(@partition_proc) LIKE N''%51073%'' THEN 1 ELSE 0 END,
               (SELECT modify_date FROM sys.objects WHERE object_id = @partition_proc),
               (SELECT MAX(TRY_CONVERT(bigint, v.value)) FROM sys.partition_range_values AS v
                    JOIN sys.partition_functions AS f ON f.function_id = v.function_id WHERE f.name = N''PF_RunID''),
               (SELECT COUNT(*) FROM sys.objects AS o WHERE
                    (o.schema_id = SCHEMA_ID(N''dbo'') AND o.name = N''RunAnalysisContext'' AND o.type = N''U'') OR
                    (o.schema_id = SCHEMA_ID(N''qv_report'') AND
                        ((o.type = N''V'' AND o.name IN (N''run_quality'', N''query_identity'', N''query_interval_metrics'')) OR
                         (o.type = N''IF'' AND o.name IN (N''fn_CompareRunQuality'', N''fn_CompareRuns'', N''fn_CompareWaits'', N''fn_CompareQueryWaits''))))),
               CASE WHEN OBJECT_DEFINITION(OBJECT_ID(N''qv_report.periods'', N''V'')) IS NULL THEN NULL
                    WHEN OBJECT_DEFINITION(OBJECT_ID(N''qv_report.periods'', N''V'')) LIKE N''%RunAnalysisContext%'' THEN 1 ELSE 0 END,
               CASE WHEN COL_LENGTH(N''dbo.RunMetadata'', N''ProtectionNote'') IS NOT NULL THEN 1 ELSE 0 END,
               @run_count, @success, @coverage, @failed;';
        EXEC sys.sp_executesql @sql,
            N'@candidate bit, @state nvarchar(60), @compat tinyint, @created datetime, @read_only bit',
            @candidate = @named_candidate, @state = @state, @compat = @compat, @created = @created, @read_only = @read_only;
    END TRY
    BEGIN CATCH
        INSERT #qv_archive_inventory (database_name, state_desc, compatibility_level, created_at, is_read_only, inspection_status)
        VALUES (@name, @state, @compat, @created, @read_only, CONCAT(N'Not inspected: SQL error ', ERROR_NUMBER()));
    END CATCH;
    FETCH NEXT FROM qv_db_cursor INTO @name, @state, @compat, @created, @read_only, @named_candidate;
END;
CLOSE qv_db_cursor;
DEALLOCATE qv_db_cursor;

SELECT * FROM #qv_archive_inventory
ORDER BY core_archive DESC, analytics_objects_present DESC, last_completed_capture_end_utc DESC, database_name;

BEGIN TRY
    SELECT j.name AS job_name, j.enabled AS job_enabled, s.step_id, s.database_name AS step_database,
           CASE refs.matches WHEN 1 THEN refs.archive_name WHEN 0 THEN NULL ELSE N'Multiple archive names' END AS archive_referenced_in_step,
           (SELECT COUNT(*) FROM msdb.dbo.sysjobschedules AS js
                JOIN msdb.dbo.sysschedules AS sch ON sch.schedule_id = js.schedule_id
                WHERE js.job_id = j.job_id AND sch.enabled = 1) AS enabled_schedule_count,
           h.run_date AS agent_last_step_local_yyyymmdd, h.run_time AS agent_last_step_local_hhmmss,
           CASE h.run_status WHEN 0 THEN N'Failed' WHEN 1 THEN N'Succeeded' WHEN 2 THEN N'Retry'
                WHEN 3 THEN N'Canceled' WHEN 4 THEN N'In progress' END AS last_step_status,
           h.sql_message_id AS last_step_sql_message_id
    FROM msdb.dbo.sysjobs AS j
    JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = j.job_id
    OUTER APPLY (SELECT COUNT(*) AS matches, MAX(a.database_name) AS archive_name
                 FROM #qv_archive_inventory AS a WHERE a.core_archive = 1 AND
                     (CHARINDEX(QUOTENAME(a.database_name) COLLATE DATABASE_DEFAULT, s.command COLLATE DATABASE_DEFAULT) > 0
                        OR CHARINDEX((a.database_name + N'.dbo.') COLLATE DATABASE_DEFAULT, s.command COLLATE DATABASE_DEFAULT) > 0)) AS refs
    OUTER APPLY (SELECT TOP (1) h.run_date, h.run_time, h.run_status, h.sql_message_id
                 FROM msdb.dbo.sysjobhistory AS h WHERE h.job_id = s.job_id AND h.step_id = s.step_id
                 ORDER BY h.instance_id DESC) AS h
    WHERE j.name LIKE N'%QueryVault%' OR s.command LIKE N'%usp_ArchiveQueryStore%' OR refs.matches > 0
       OR EXISTS (SELECT 1 FROM #qv_archive_inventory AS a
                  WHERE a.core_archive = 1 AND a.database_name COLLATE DATABASE_DEFAULT = s.database_name COLLATE DATABASE_DEFAULT)
    ORDER BY j.enabled DESC, j.name, s.step_id;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS agent_metadata_error, N'Agent job metadata could not be read with this login.' AS agent_metadata_status;
END CATCH;

DROP TABLE #qv_archive_inventory;
SET LOCK_TIMEOUT -1;

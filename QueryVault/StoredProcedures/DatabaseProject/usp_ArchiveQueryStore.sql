CREATE PROCEDURE dbo.usp_ArchiveQueryStore
	@SourceDatabaseName NVARCHAR(128),
	@RunName NVARCHAR(255),
	@StartDateTime DATETIME2(7) = NULL,
	@EndDateTime DATETIME2(7) = NULL,
	@DoNotDelete BIT = 0,
	@RetentionDays INT = NULL,
	@BatchSize INT = NULL,
	@LookbackMinutes INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	-- This procedure owns its archive transaction. Never roll back a caller's work.
	IF @@TRANCOUNT <> 0
	BEGIN
		-- Reject without dooming an XACT_ABORT ON caller. The caller's option
		-- is restored automatically when control returns from this procedure.
		SET XACT_ABORT OFF;
		THROW 51006, 'Archive capture must run without an ambient transaction.', 1;
	END;
	SET XACT_ABORT ON;

	DECLARE @RunID INT;
	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @ActualStartDateTime DATETIME2(7);
	DECLARE @ActualEndDateTime DATETIME2(7);
	DECLARE @RequestedEndDateTime DATETIME2(7);
	DECLARE @SafeQueryStoreCutoff DATETIME2(7);
	DECLARE @QueryStoreFlushSeconds INT = 900;
	DECLARE @ActualBatchSize INT;
	DECLARE @ActualRetentionDays INT;
	DECLARE @ActualRetentionDate DATETIME2(7);
	DECLARE @RowCount BIGINT;
	DECLARE @CompressionDelay INT;
	DECLARE @RuntimeContributorRows BIGINT;
	DECLARE @WaitContributorRows BIGINT;
	DECLARE @HasWaitStats BIT = 0;
	DECLARE @CapabilityNotes NVARCHAR(MAX);
	DECLARE @SourceColumns TABLE (ObjectName SYSNAME, ColumnName SYSNAME);
	DECLARE @OptionalColumns TABLE
	(
		ObjectName SYSNAME, AliasName SYSNAME, ColumnName SYSNAME,
		SqlType NVARCHAR(30), TargetTable SYSNAME
	);

	BEGIN TRY
		IF @LookbackMinutes IS NOT NULL AND @LookbackMinutes <= 0
			THROW 51004, '@LookbackMinutes must be greater than zero.', 1;

		IF @LookbackMinutes IS NOT NULL AND @StartDateTime IS NOT NULL
			THROW 51005, 'Specify either @LookbackMinutes or @StartDateTime, not both.', 1;

		-- Get configuration for the database
		DECLARE @ConfigID INT;
		DECLARE @DefaultDaysToArchive INT;

		SELECT
			@ConfigID = ConfigID,
			@DefaultDaysToArchive = DefaultDaysToArchive,
			@ActualBatchSize = ISNULL(@BatchSize, MaxRowsPerBatch),
			@CompressionDelay = CompressionDelayMinutes,
			@ActualRetentionDays = ISNULL(@RetentionDays, DefaultRetentionDays)
		FROM dbo.DatabaseConfig
		WHERE DatabaseName = @SourceDatabaseName
		  AND ServerName = @@SERVERNAME
		  AND IsEnabled = 1;

		IF @ConfigID IS NULL
		BEGIN
			RAISERROR('Database "%s" not found in configuration or is not enabled', 16, 1, @SourceDatabaseName);
			RETURN -1;
		END

		-- Allow one Query Store flush interval before archiving. The active
		-- interval can expose separate persisted and in-memory rows at the same
		-- documented runtime/wait aggregation grain.
		SET @SQL = N'SELECT @FlushSeconds = flush_interval_seconds
			FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.database_query_store_options;';

		EXEC sys.sp_executesql @SQL,
			N'@FlushSeconds INT OUTPUT',
			@FlushSeconds = @QueryStoreFlushSeconds OUTPUT;

		SET @QueryStoreFlushSeconds = ISNULL(@QueryStoreFlushSeconds, 900);
		SET @RequestedEndDateTime = ISNULL(@EndDateTime, SYSUTCDATETIME());
		SET @SafeQueryStoreCutoff = DATEADD(SECOND, -@QueryStoreFlushSeconds, SYSUTCDATETIME());
		SET @ActualEndDateTime = CASE
			WHEN @RequestedEndDateTime < @SafeQueryStoreCutoff THEN @RequestedEndDateTime
			ELSE @SafeQueryStoreCutoff
		END;
		SET @ActualStartDateTime = CASE
			WHEN @LookbackMinutes IS NOT NULL
				THEN DATEADD(MINUTE, -@LookbackMinutes, @ActualEndDateTime)
			ELSE ISNULL(
				@StartDateTime,
				DATEADD(DAY, -@DefaultDaysToArchive, @ActualEndDateTime)
			)
		END;

		IF @ActualEndDateTime < @ActualStartDateTime
			THROW 51003, 'The requested archive range does not contain a safely flushed Query Store interval.', 1;

		-- Retention measures the age of captured data, not how recently an old
		-- period was imported. Pins independently override expiry; retain the
		-- date so an explicit unpin restores the original policy. The upper bound is SQL's
		-- representable date horizon, not an arbitrary product retention limit.
		IF @ActualRetentionDays IS NULL OR @ActualRetentionDays < 1
			OR @ActualRetentionDays > DATEDIFF(DAY, @ActualEndDateTime, CONVERT(DATETIME2(7), '9999-12-31'))
			THROW 51009, 'RetentionDays must be positive and fit after the captured period end.', 1;

		SET @ActualRetentionDate = DATEADD(DAY, @ActualRetentionDays, @ActualEndDateTime);

		-- Inspect the source catalog, not ProductMajorVersion: Azure versions and
		-- backported features do not follow boxed-server version numbering.
		SET @SQL = N'SELECT o.name, c.name
			FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.all_objects AS o
			JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.all_columns AS c ON c.object_id = o.object_id
			JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.schemas AS s ON s.schema_id = o.schema_id
			WHERE s.name = N''sys'' AND o.name IN
			(N''query_store_plan'', N''query_store_runtime_stats'', N''query_store_wait_stats'', N''query_store_query'');';
		INSERT INTO @SourceColumns EXEC sys.sp_executesql @SQL;
		IF NOT EXISTS (SELECT 1 FROM @SourceColumns WHERE ObjectName = N'query_store_runtime_stats')
			THROW 51007, 'Query Store catalog is unavailable. Check the source and database permissions.', 1;
		SET @HasWaitStats = CASE WHEN EXISTS
			(SELECT 1 FROM @SourceColumns WHERE ObjectName = N'query_store_wait_stats') THEN 1 ELSE 0 END;
		INSERT INTO @OptionalColumns VALUES
			(N'query_store_plan', N'p', N'plan_forcing_type', N'INT', N'query_store_plan'),
			(N'query_store_plan', N'p', N'plan_forcing_type_desc', N'NVARCHAR(60)', N'query_store_plan'),
			(N'query_store_plan', N'p', N'has_compile_replay_script', N'BIT', N'query_store_plan'),
			(N'query_store_plan', N'p', N'is_optimized_plan_forcing_disabled', N'BIT', N'query_store_plan'),
			(N'query_store_plan', N'p', N'plan_type', N'INT', N'query_store_plan'),
			(N'query_store_plan', N'p', N'plan_type_desc', N'NVARCHAR(60)', N'query_store_plan'),
			(N'query_store_runtime_stats', N'rs', N'avg_num_physical_io_reads', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'last_num_physical_io_reads', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'min_num_physical_io_reads', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'max_num_physical_io_reads', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'stdev_num_physical_io_reads', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'avg_log_bytes_used', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'last_log_bytes_used', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'min_log_bytes_used', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'max_log_bytes_used', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'stdev_log_bytes_used', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'avg_tempdb_space_used', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'last_tempdb_space_used', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'min_tempdb_space_used', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'max_tempdb_space_used', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'stdev_tempdb_space_used', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'avg_page_server_io_reads', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'last_page_server_io_reads', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'min_page_server_io_reads', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'max_page_server_io_reads', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'stdev_page_server_io_reads', N'FLOAT', N'query_store_runtime_stats_contributor'),
			(N'query_store_runtime_stats', N'rs', N'replica_group_id', N'BIGINT', N'query_store_runtime_stats_contributor'),
			(N'query_store_wait_stats', N'ws', N'replica_group_id', N'BIGINT', N'query_store_wait_stats_contributor'),
			(N'query_store_query', N'q', N'is_clouddb_internal_query', N'BIT', N'query_store_query');

		-- Old archive schemas used NOT NULL for newer plan features. Require a
		-- reviewed schema upgrade instead of recording false zeros for missing data.
		IF EXISTS
		(
			SELECT 1 FROM @OptionalColumns AS o
			JOIN sys.columns AS t ON t.object_id = OBJECT_ID(N'dbo.' + o.TargetTable)
				AND t.name = o.ColumnName AND t.is_nullable = 0
			WHERE NOT EXISTS (SELECT 1 FROM @SourceColumns AS c
				WHERE c.ObjectName = o.ObjectName AND c.ColumnName = o.ColumnName)
		)
			THROW 51008, 'Archive schema requires the nullable optional-metric upgrade. Review the deployment package before capturing older sources.', 1;

		SELECT @CapabilityNotes = (
			SELECT @HasWaitStats AS wait_stats_available,
				JSON_QUERY((SELECT o.ObjectName AS [view], o.ColumnName AS [column]
					FROM @OptionalColumns AS o
					WHERE NOT EXISTS (SELECT 1 FROM @SourceColumns AS c
						WHERE c.ObjectName = o.ObjectName AND c.ColumnName = o.ColumnName)
					ORDER BY o.ObjectName, o.ColumnName FOR JSON PATH)) AS unavailable_columns
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

		PRINT 'Archiving QueryStore data from ' + @SourceDatabaseName;
		PRINT 'Date Range: ' + CONVERT(VARCHAR(30), @ActualStartDateTime, 121) + ' to ' + CONVERT(VARCHAR(30), @ActualEndDateTime, 121);

		-- Create run metadata record
		INSERT INTO dbo.RunMetadata
		(
			RunName,
			SourceDatabaseName,
			StartDateTime,
			EndDateTime,
			DoNotDelete,
			RetentionDate,
			Comments,
			RunStatus
		)
		VALUES
		(
			@RunName,
			@SourceDatabaseName,
			@ActualStartDateTime,
			@ActualEndDateTime,
			@DoNotDelete,
			@ActualRetentionDate,
			@CapabilityNotes,
			'In Progress'
		);

		SET @RunID = SCOPE_IDENTITY();
		PRINT 'Created RunID: ' + CAST(@RunID AS VARCHAR(20));

		-- Allocate exactly this immutable archive RunID and an empty future
		-- partition. Identity gaps never allocate intermediate boundaries.
		EXEC dbo.usp_ManagePartitions
			@Operation = N'EnsureRunPartition',
			@RunID = @RunID,
			@ConfigID = @ConfigID;

		-- Keep the run metadata outside the archive transaction so failures remain visible.
		BEGIN TRANSACTION;

		-- Archive query_store_runtime_stats_interval
		PRINT 'Archiving query_store_runtime_stats_interval...';
		SET @SQL = N'
		INSERT INTO dbo.query_store_runtime_stats_interval
		(RunID, runtime_stats_interval_id, start_time, end_time, comment)
		SELECT
			@RunID,
			runtime_stats_interval_id,
			start_time,
			end_time,
			comment
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval
		-- Archive completed intervals only. The active Query Store interval can
		-- expose both persisted and in-memory rows with the same statistics ID.
		WHERE end_time > @StartDateTime
		  AND end_time <= @EndDateTime;
		SET @RowsArchived = @@ROWCOUNT;';

		EXEC sys.sp_executesql @SQL,
			N'@RunID INT, @StartDateTime DATETIME2(7), @EndDateTime DATETIME2(7), @RowsArchived BIGINT OUTPUT',
			@RunID = @RunID,
			@StartDateTime = @ActualStartDateTime,
			@EndDateTime = @ActualEndDateTime,
			@RowsArchived = @RowCount OUTPUT;
		PRINT 'Archived ' + CAST(@RowCount AS VARCHAR(20)) + ' rows';

		UPDATE dbo.RunMetadata
		SET RowsArchived_RuntimeStatsInterval = @RowCount
		WHERE RunID = @RunID;

		-- Archive query_store_query_text
		PRINT 'Archiving query_store_query_text...';
		SET @SQL = N'
		INSERT INTO dbo.query_store_query_text
		(RunID, query_text_id, query_sql_text, statement_sql_handle, is_part_of_encrypted_module, has_restricted_text)
		SELECT DISTINCT
			@RunID,
			qt.query_text_id,
			qt.query_sql_text,
			qt.statement_sql_handle,
			qt.is_part_of_encrypted_module,
			qt.has_restricted_text
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_query_text qt
		WHERE EXISTS (
			SELECT 1
			FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_query q
			INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_plan p
				ON p.query_id = q.query_id
			INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats rs
				ON rs.plan_id = p.plan_id
			INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval i
				ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
			WHERE q.query_text_id = qt.query_text_id
			  AND i.end_time > @StartDateTime
			  AND i.end_time <= @EndDateTime
		);
		SET @RowsArchived = @@ROWCOUNT;';

		EXEC sys.sp_executesql @SQL,
			N'@RunID INT, @StartDateTime DATETIME2(7), @EndDateTime DATETIME2(7), @RowsArchived BIGINT OUTPUT',
			@RunID = @RunID,
			@StartDateTime = @ActualStartDateTime,
			@EndDateTime = @ActualEndDateTime,
			@RowsArchived = @RowCount OUTPUT;
		PRINT 'Archived ' + CAST(@RowCount AS VARCHAR(20)) + ' rows';

		UPDATE dbo.RunMetadata
		SET RowsArchived_QueryText = @RowCount
		WHERE RunID = @RunID;

		-- Archive query_store_query
		PRINT 'Archiving query_store_query...';
		SET @SQL = N'
		INSERT INTO dbo.query_store_query
		(RunID, query_id, query_text_id, context_settings_id, object_id, batch_sql_handle, query_hash,
		 is_internal_query, query_parameterization_type, query_parameterization_type_desc,
		 initial_compile_start_time, last_compile_start_time, last_execution_time,
		 last_compile_batch_sql_handle, last_compile_batch_offset_start, last_compile_batch_offset_end,
		 count_compiles, avg_compile_duration, last_compile_duration, avg_bind_duration, last_bind_duration,
		 avg_bind_cpu_time, last_bind_cpu_time, avg_optimize_duration, last_optimize_duration,
		 avg_optimize_cpu_time, last_optimize_cpu_time, avg_compile_memory_kb, last_compile_memory_kb,
		 max_compile_memory_kb, is_clouddb_internal_query)
		SELECT
			@RunID,
			query_id, query_text_id, context_settings_id, object_id, batch_sql_handle, query_hash,
			is_internal_query, query_parameterization_type, query_parameterization_type_desc,
			initial_compile_start_time, last_compile_start_time, last_execution_time,
			last_compile_batch_sql_handle, last_compile_batch_offset_start, last_compile_batch_offset_end,
			count_compiles, avg_compile_duration, last_compile_duration, avg_bind_duration, last_bind_duration,
			avg_bind_cpu_time, last_bind_cpu_time, avg_optimize_duration, last_optimize_duration,
			avg_optimize_cpu_time, last_optimize_cpu_time, avg_compile_memory_kb, last_compile_memory_kb,
			max_compile_memory_kb, q.[is_clouddb_internal_query]
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_query q
		WHERE EXISTS (
			SELECT 1
			FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_plan p
			INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats rs
				ON rs.plan_id = p.plan_id
			INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval i
				ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
			WHERE p.query_id = q.query_id
			  AND i.end_time > @StartDateTime
			  AND i.end_time <= @EndDateTime
		);
		SET @RowsArchived = @@ROWCOUNT;';

		-- Fixed allowlist only; no user-controlled identifiers or expressions.
		DECLARE optional_projection_0 CURSOR LOCAL FAST_FORWARD FOR
			SELECT o.AliasName + N'.[' + o.ColumnName + N']',
				N'CONVERT(' + o.SqlType + N', NULL)'
			FROM @OptionalColumns AS o
			WHERE NOT EXISTS (SELECT 1 FROM @SourceColumns AS c
				WHERE c.ObjectName = o.ObjectName AND c.ColumnName = o.ColumnName);
		DECLARE @Token0 NVARCHAR(300), @NullExpression0 NVARCHAR(100);
		OPEN optional_projection_0;
		FETCH NEXT FROM optional_projection_0 INTO @Token0, @NullExpression0;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = REPLACE(@SQL, @Token0, @NullExpression0);
			FETCH NEXT FROM optional_projection_0 INTO @Token0, @NullExpression0;
		END;
		CLOSE optional_projection_0;
		DEALLOCATE optional_projection_0;

		EXEC sys.sp_executesql @SQL,
			N'@RunID INT, @StartDateTime DATETIME2(7), @EndDateTime DATETIME2(7), @RowsArchived BIGINT OUTPUT',
			@RunID = @RunID,
			@StartDateTime = @ActualStartDateTime,
			@EndDateTime = @ActualEndDateTime,
			@RowsArchived = @RowCount OUTPUT;
		PRINT 'Archived ' + CAST(@RowCount AS VARCHAR(20)) + ' rows';

		UPDATE dbo.RunMetadata
		SET RowsArchived_Query = @RowCount
		WHERE RunID = @RunID;

		-- Archive query_store_plan
		PRINT 'Archiving query_store_plan...';
		SET @SQL = N'
		INSERT INTO dbo.query_store_plan
		(RunID, plan_id, query_id, plan_group_id, engine_version, compatibility_level, query_plan_hash,
		 query_plan, is_online_index_plan, is_trivial_plan, is_parallel_plan, is_forced_plan,
		 is_natively_compiled, force_failure_count, last_force_failure_reason, last_force_failure_reason_desc,
		 count_compiles, initial_compile_start_time, last_compile_start_time, last_execution_time,
			 avg_compile_duration, last_compile_duration, plan_forcing_type, plan_forcing_type_desc,
			 has_compile_replay_script, is_optimized_plan_forcing_disabled, plan_type, plan_type_desc)
		SELECT
			@RunID,
			p.plan_id, p.query_id, p.plan_group_id, p.engine_version, p.compatibility_level, p.query_plan_hash,
			p.query_plan, p.is_online_index_plan, p.is_trivial_plan, p.is_parallel_plan, p.is_forced_plan,
			p.is_natively_compiled, p.force_failure_count, p.last_force_failure_reason, p.last_force_failure_reason_desc,
			p.count_compiles, p.initial_compile_start_time, p.last_compile_start_time, p.last_execution_time,
			p.avg_compile_duration, p.last_compile_duration, p.[plan_forcing_type], p.[plan_forcing_type_desc],
			p.[has_compile_replay_script], p.[is_optimized_plan_forcing_disabled], p.[plan_type], p.[plan_type_desc]
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_plan p
		WHERE EXISTS (
			SELECT 1
			FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats rs
			INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval i
				ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
			WHERE rs.plan_id = p.plan_id
			  AND i.end_time > @StartDateTime
			  AND i.end_time <= @EndDateTime
		);
		SET @RowsArchived = @@ROWCOUNT;';

		-- Fixed allowlist only; no user-controlled identifiers or expressions.
		DECLARE optional_projection_1 CURSOR LOCAL FAST_FORWARD FOR
			SELECT o.AliasName + N'.[' + o.ColumnName + N']',
				N'CONVERT(' + o.SqlType + N', NULL)'
			FROM @OptionalColumns AS o
			WHERE NOT EXISTS (SELECT 1 FROM @SourceColumns AS c
				WHERE c.ObjectName = o.ObjectName AND c.ColumnName = o.ColumnName);
		DECLARE @Token1 NVARCHAR(300), @NullExpression1 NVARCHAR(100);
		OPEN optional_projection_1;
		FETCH NEXT FROM optional_projection_1 INTO @Token1, @NullExpression1;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = REPLACE(@SQL, @Token1, @NullExpression1);
			FETCH NEXT FROM optional_projection_1 INTO @Token1, @NullExpression1;
		END;
		CLOSE optional_projection_1;
		DEALLOCATE optional_projection_1;

		EXEC sys.sp_executesql @SQL,
			N'@RunID INT, @StartDateTime DATETIME2(7), @EndDateTime DATETIME2(7), @RowsArchived BIGINT OUTPUT',
			@RunID = @RunID,
			@StartDateTime = @ActualStartDateTime,
			@EndDateTime = @ActualEndDateTime,
			@RowsArchived = @RowCount OUTPUT;
		PRINT 'Archived ' + CAST(@RowCount AS VARCHAR(20)) + ' rows';

		UPDATE dbo.RunMetadata
		SET RowsArchived_Plan = @RowCount
		WHERE RunID = @RunID;

		-- Preserve every native runtime contributor before materializing one
		-- observation at the documented Query Store grain.
		PRINT 'Archiving query_store_runtime_stats contributors...';
		SET @SQL = N'
		INSERT INTO dbo.query_store_runtime_stats_contributor
		(RunID, runtime_stats_id, plan_id, runtime_stats_interval_id, execution_type, execution_type_desc,
		 first_execution_time, last_execution_time, count_executions,
		 avg_duration, last_duration, min_duration, max_duration, stdev_duration,
		 avg_cpu_time, last_cpu_time, min_cpu_time, max_cpu_time, stdev_cpu_time,
		 avg_logical_io_reads, last_logical_io_reads, min_logical_io_reads, max_logical_io_reads, stdev_logical_io_reads,
		 avg_logical_io_writes, last_logical_io_writes, min_logical_io_writes, max_logical_io_writes, stdev_logical_io_writes,
		 avg_physical_io_reads, last_physical_io_reads, min_physical_io_reads, max_physical_io_reads, stdev_physical_io_reads,
		 avg_clr_time, last_clr_time, min_clr_time, max_clr_time, stdev_clr_time,
		 avg_dop, last_dop, min_dop, max_dop, stdev_dop,
		 avg_query_max_used_memory, last_query_max_used_memory, min_query_max_used_memory, max_query_max_used_memory, stdev_query_max_used_memory,
		 avg_rowcount, last_rowcount, min_rowcount, max_rowcount, stdev_rowcount,
			 avg_num_physical_io_reads, last_num_physical_io_reads, min_num_physical_io_reads, max_num_physical_io_reads, stdev_num_physical_io_reads,
			 avg_log_bytes_used, last_log_bytes_used, min_log_bytes_used, max_log_bytes_used, stdev_log_bytes_used,
			 avg_tempdb_space_used, last_tempdb_space_used, min_tempdb_space_used, max_tempdb_space_used, stdev_tempdb_space_used,
			 avg_page_server_io_reads, last_page_server_io_reads, min_page_server_io_reads, max_page_server_io_reads, stdev_page_server_io_reads,
			 replica_group_id)
		SELECT
			@RunID,
			rs.runtime_stats_id, rs.plan_id, rs.runtime_stats_interval_id, rs.execution_type, rs.execution_type_desc,
			rs.first_execution_time, rs.last_execution_time, rs.count_executions,
			rs.avg_duration, rs.last_duration, rs.min_duration, rs.max_duration, rs.stdev_duration,
			rs.avg_cpu_time, rs.last_cpu_time, rs.min_cpu_time, rs.max_cpu_time, rs.stdev_cpu_time,
			rs.avg_logical_io_reads, rs.last_logical_io_reads, rs.min_logical_io_reads, rs.max_logical_io_reads, rs.stdev_logical_io_reads,
			rs.avg_logical_io_writes, rs.last_logical_io_writes, rs.min_logical_io_writes, rs.max_logical_io_writes, rs.stdev_logical_io_writes,
			rs.avg_physical_io_reads, rs.last_physical_io_reads, rs.min_physical_io_reads, rs.max_physical_io_reads, rs.stdev_physical_io_reads,
			rs.avg_clr_time, rs.last_clr_time, rs.min_clr_time, rs.max_clr_time, rs.stdev_clr_time,
			rs.avg_dop, rs.last_dop, rs.min_dop, rs.max_dop, rs.stdev_dop,
			rs.avg_query_max_used_memory, rs.last_query_max_used_memory, rs.min_query_max_used_memory, rs.max_query_max_used_memory, rs.stdev_query_max_used_memory,
			rs.avg_rowcount, rs.last_rowcount, rs.min_rowcount, rs.max_rowcount, rs.stdev_rowcount,
			rs.[avg_num_physical_io_reads], rs.[last_num_physical_io_reads], rs.[min_num_physical_io_reads], rs.[max_num_physical_io_reads], rs.[stdev_num_physical_io_reads],
			rs.[avg_log_bytes_used], rs.[last_log_bytes_used], rs.[min_log_bytes_used], rs.[max_log_bytes_used], rs.[stdev_log_bytes_used],
			rs.[avg_tempdb_space_used], rs.[last_tempdb_space_used], rs.[min_tempdb_space_used], rs.[max_tempdb_space_used], rs.[stdev_tempdb_space_used],
			rs.[avg_page_server_io_reads], rs.[last_page_server_io_reads], rs.[min_page_server_io_reads], rs.[max_page_server_io_reads], rs.[stdev_page_server_io_reads],
			rs.[replica_group_id]
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats rs
		INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval i
			ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
		WHERE i.end_time > @StartDateTime
		  AND i.end_time <= @EndDateTime;
		SET @RowsArchived = @@ROWCOUNT;';

		-- Fixed allowlist only; no user-controlled identifiers or expressions.
		DECLARE optional_projection_2 CURSOR LOCAL FAST_FORWARD FOR
			SELECT o.AliasName + N'.[' + o.ColumnName + N']',
				N'CONVERT(' + o.SqlType + N', NULL)'
			FROM @OptionalColumns AS o
			WHERE NOT EXISTS (SELECT 1 FROM @SourceColumns AS c
				WHERE c.ObjectName = o.ObjectName AND c.ColumnName = o.ColumnName);
		DECLARE @Token2 NVARCHAR(300), @NullExpression2 NVARCHAR(100);
		OPEN optional_projection_2;
		FETCH NEXT FROM optional_projection_2 INTO @Token2, @NullExpression2;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = REPLACE(@SQL, @Token2, @NullExpression2);
			FETCH NEXT FROM optional_projection_2 INTO @Token2, @NullExpression2;
		END;
		CLOSE optional_projection_2;
		DEALLOCATE optional_projection_2;

		EXEC sys.sp_executesql @SQL,
			N'@RunID INT, @StartDateTime DATETIME2(7), @EndDateTime DATETIME2(7), @RowsArchived BIGINT OUTPUT',
			@RunID = @RunID,
			@StartDateTime = @ActualStartDateTime,
			@EndDateTime = @ActualEndDateTime,
			@RowsArchived = @RowCount OUTPUT;
		SET @RuntimeContributorRows = @RowCount;
		PRINT 'Archived ' + CAST(@RuntimeContributorRows AS VARCHAR(20)) + ' native runtime contributor rows';

		-- Preserve every native wait contributor. Canonical wait averages are
		-- derived later from additive wait totals and matching runtime counts.
		SET @WaitContributorRows = 0;
		IF @HasWaitStats = 1
		BEGIN
		PRINT 'Archiving query_store_wait_stats contributors...';
		SET @SQL = N'
		INSERT INTO dbo.query_store_wait_stats_contributor
		(RunID, wait_stats_id, plan_id, runtime_stats_interval_id, wait_category, wait_category_desc,
		 execution_type, execution_type_desc, total_query_wait_time_ms, avg_query_wait_time_ms,
		 last_query_wait_time_ms, min_query_wait_time_ms, max_query_wait_time_ms, stdev_query_wait_time_ms,
		 replica_group_id)
		SELECT
			@RunID,
			ws.wait_stats_id, ws.plan_id, ws.runtime_stats_interval_id, ws.wait_category, ws.wait_category_desc,
			ws.execution_type, ws.execution_type_desc, ws.total_query_wait_time_ms, ws.avg_query_wait_time_ms,
			ws.last_query_wait_time_ms, ws.min_query_wait_time_ms, ws.max_query_wait_time_ms, ws.stdev_query_wait_time_ms,
			ws.[replica_group_id]
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_wait_stats ws
		INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval i
			ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
		WHERE i.end_time > @StartDateTime
		  AND i.end_time <= @EndDateTime;
		SET @RowsArchived = @@ROWCOUNT;';

		-- Fixed allowlist only; no user-controlled identifiers or expressions.
		DECLARE optional_projection_3 CURSOR LOCAL FAST_FORWARD FOR
			SELECT o.AliasName + N'.[' + o.ColumnName + N']',
				N'CONVERT(' + o.SqlType + N', NULL)'
			FROM @OptionalColumns AS o
			WHERE NOT EXISTS (SELECT 1 FROM @SourceColumns AS c
				WHERE c.ObjectName = o.ObjectName AND c.ColumnName = o.ColumnName);
		DECLARE @Token3 NVARCHAR(300), @NullExpression3 NVARCHAR(100);
		OPEN optional_projection_3;
		FETCH NEXT FROM optional_projection_3 INTO @Token3, @NullExpression3;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = REPLACE(@SQL, @Token3, @NullExpression3);
			FETCH NEXT FROM optional_projection_3 INTO @Token3, @NullExpression3;
		END;
		CLOSE optional_projection_3;
		DEALLOCATE optional_projection_3;

		EXEC sys.sp_executesql @SQL,
			N'@RunID INT, @StartDateTime DATETIME2(7), @EndDateTime DATETIME2(7), @RowsArchived BIGINT OUTPUT',
			@RunID = @RunID,
			@StartDateTime = @ActualStartDateTime,
			@EndDateTime = @ActualEndDateTime,
			@RowsArchived = @RowCount OUTPUT;
		SET @WaitContributorRows = @RowCount;
		PRINT 'Archived ' + CAST(@WaitContributorRows AS VARCHAR(20)) + ' native wait contributor rows';

		END;

		EXEC dbo.usp_MaterializeCanonicalQueryStoreStats
			@RunID = @RunID,
			@ObservationState = N'COMPLETED';

		SELECT @RowCount = COUNT_BIG(*)
		FROM dbo.query_store_runtime_stats_canonical
		WHERE RunID = @RunID;

		UPDATE dbo.RunMetadata
		SET RowsArchived_RuntimeStats = @RowCount
		WHERE RunID = @RunID;

		SELECT @RowCount = COUNT_BIG(*)
		FROM dbo.query_store_wait_stats_canonical
		WHERE RunID = @RunID;

		UPDATE dbo.RunMetadata
		SET RowsArchived_WaitStats = @RowCount
		WHERE RunID = @RunID;

		-- Mark run as completed
		UPDATE dbo.RunMetadata
		SET
			RunEndTime = SYSUTCDATETIME(),
			RunStatus = 'Completed'
		WHERE RunID = @RunID;

		-- Update last run time in config
		UPDATE dbo.DatabaseConfig
		SET
			LastRunDateTime = SYSUTCDATETIME(),
			ModifiedDate = SYSUTCDATETIME()
		WHERE ConfigID = @ConfigID;

		COMMIT TRANSACTION;

		PRINT 'Archive completed successfully for RunID: ' + CAST(@RunID AS VARCHAR(20));

		-- Return RunID
		SELECT @RunID AS RunID;
		RETURN 0;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;

		-- Mark run as failed if it was created
		IF @RunID IS NOT NULL
		BEGIN
			UPDATE dbo.RunMetadata
			SET
				RunEndTime = SYSUTCDATETIME(),
				RunStatus = 'Failed',
				Comments = ERROR_MESSAGE()
			WHERE RunID = @RunID;
		END

		SET @ErrorMessage = 'Error in usp_ArchiveQueryStore: ' + ERROR_MESSAGE();
		RAISERROR(N'%s', 16, 1, @ErrorMessage);
		RETURN -1;
	END CATCH
END
GO

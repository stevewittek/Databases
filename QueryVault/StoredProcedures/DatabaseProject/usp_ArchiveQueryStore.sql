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
	DECLARE @RowCount BIGINT;
	DECLARE @CompressionDelay INT;
	DECLARE @RuntimeContributorRows BIGINT;
	DECLARE @WaitContributorRows BIGINT;
	DECLARE @RuntimeReplicaGroupProjection NVARCHAR(128);
	DECLARE @WaitReplicaGroupProjection NVARCHAR(128);

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

		-- replica_group_id is available in SQL Server 2022 and later. It is
		-- contributor provenance, not part of Microsoft's canonical grain.
		SET @RuntimeReplicaGroupProjection = CASE
			WHEN TRY_CONVERT(INT, SERVERPROPERTY('ProductMajorVersion')) >= 16
				THEN N'rs.replica_group_id'
			ELSE N'CONVERT(BIGINT, NULL)'
		END;
		SET @WaitReplicaGroupProjection = CASE
			WHEN TRY_CONVERT(INT, SERVERPROPERTY('ProductMajorVersion')) >= 16
				THEN N'ws.replica_group_id'
			ELSE N'CONVERT(BIGINT, NULL)'
		END;

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
			RunStatus
		)
		VALUES
		(
			@RunName,
			@SourceDatabaseName,
			@ActualStartDateTime,
			@ActualEndDateTime,
			@DoNotDelete,
			CASE WHEN @DoNotDelete = 0 THEN DATEADD(DAY, @ActualRetentionDays, SYSUTCDATETIME()) ELSE NULL END,
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
			max_compile_memory_kb, is_clouddb_internal_query
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
			p.avg_compile_duration, p.last_compile_duration, p.plan_forcing_type, p.plan_forcing_type_desc,
			p.has_compile_replay_script, p.is_optimized_plan_forcing_disabled, p.plan_type, p.plan_type_desc
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
			rs.avg_num_physical_io_reads, rs.last_num_physical_io_reads, rs.min_num_physical_io_reads, rs.max_num_physical_io_reads, rs.stdev_num_physical_io_reads,
			rs.avg_log_bytes_used, rs.last_log_bytes_used, rs.min_log_bytes_used, rs.max_log_bytes_used, rs.stdev_log_bytes_used,
			rs.avg_tempdb_space_used, rs.last_tempdb_space_used, rs.min_tempdb_space_used, rs.max_tempdb_space_used, rs.stdev_tempdb_space_used,
			rs.avg_page_server_io_reads, rs.last_page_server_io_reads, rs.min_page_server_io_reads, rs.max_page_server_io_reads, rs.stdev_page_server_io_reads,
			' + @RuntimeReplicaGroupProjection + N'
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats rs
		INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval i
			ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
		WHERE i.end_time > @StartDateTime
		  AND i.end_time <= @EndDateTime;
		SET @RowsArchived = @@ROWCOUNT;';

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
			' + @WaitReplicaGroupProjection + N'
		FROM ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_wait_stats ws
		INNER JOIN ' + QUOTENAME(@SourceDatabaseName) + N'.sys.query_store_runtime_stats_interval i
			ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
		WHERE i.end_time > @StartDateTime
		  AND i.end_time <= @EndDateTime;
		SET @RowsArchived = @@ROWCOUNT;';

		EXEC sys.sp_executesql @SQL,
			N'@RunID INT, @StartDateTime DATETIME2(7), @EndDateTime DATETIME2(7), @RowsArchived BIGINT OUTPUT',
			@RunID = @RunID,
			@StartDateTime = @ActualStartDateTime,
			@EndDateTime = @ActualEndDateTime,
			@RowsArchived = @RowCount OUTPUT;
		SET @WaitContributorRows = @RowCount;
		PRINT 'Archived ' + CAST(@WaitContributorRows AS VARCHAR(20)) + ' native wait contributor rows';

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
		RAISERROR(@ErrorMessage, 16, 1);
		RETURN -1;
	END CATCH
END
GO

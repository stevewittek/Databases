CREATE PROCEDURE dbo.usp_MaterializeCanonicalQueryStoreStats
	@RunID INT,
	@ObservationState NVARCHAR(20) = N'COMPLETED'
AS
BEGIN
	SET NOCOUNT ON;

	IF @ObservationState NOT IN (N'COMPLETED', N'PROVISIONAL')
		THROW 51030, 'Observation state must be COMPLETED or PROVISIONAL.', 1;

	DECLARE @StartedTransaction BIT = 0;
	IF @@TRANCOUNT = 0
	BEGIN
		BEGIN TRANSACTION;
		SET @StartedTransaction = 1;
	END
	ELSE
		SAVE TRANSACTION MaterializeCanonicalStats;

	BEGIN TRY
		DELETE dbo.query_store_wait_stats_canonical
		WHERE RunID = @RunID;

		DELETE dbo.query_store_runtime_stats_canonical
		WHERE RunID = @RunID;

		;WITH runtime_group AS
		(
			SELECT
				c.RunID,
				c.plan_id,
				c.runtime_stats_interval_id,
				c.execution_type,
				MAX(c.execution_type_desc) AS execution_type_desc,
				COUNT_BIG(*) AS contributor_count,
				CONVERT(INT,
					COUNT(DISTINCT c.replica_group_id)
					+ CASE WHEN COUNT_BIG(*) > COUNT(c.replica_group_id) THEN 1 ELSE 0 END
				) AS replica_count,
				CASE
					WHEN COUNT(DISTINCT c.replica_group_id)
						+ CASE WHEN COUNT_BIG(*) > COUNT(c.replica_group_id) THEN 1 ELSE 0 END = 1
					THEN MAX(c.replica_group_id)
				END AS replica_group_id,
				MIN(c.first_execution_time) AS first_execution_time,
				MAX(c.last_execution_time) AS last_execution_time,
				SUM(CONVERT(DECIMAL(38,0), c.count_executions)) AS count_executions,
				SUM(CASE WHEN c.avg_duration IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_duration) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_duration IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_duration,
				MIN(c.min_duration) AS min_duration,
				MAX(c.max_duration) AS max_duration,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_duration) END AS stdev_duration,
				SUM(CASE WHEN c.avg_cpu_time IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_cpu_time) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_cpu_time IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_cpu_time,
				MIN(c.min_cpu_time) AS min_cpu_time,
				MAX(c.max_cpu_time) AS max_cpu_time,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_cpu_time) END AS stdev_cpu_time,
				SUM(CASE WHEN c.avg_logical_io_reads IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_logical_io_reads) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_logical_io_reads IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_logical_io_reads,
				MIN(c.min_logical_io_reads) AS min_logical_io_reads,
				MAX(c.max_logical_io_reads) AS max_logical_io_reads,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_logical_io_reads) END AS stdev_logical_io_reads,
				SUM(CASE WHEN c.avg_logical_io_writes IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_logical_io_writes) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_logical_io_writes IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_logical_io_writes,
				MIN(c.min_logical_io_writes) AS min_logical_io_writes,
				MAX(c.max_logical_io_writes) AS max_logical_io_writes,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_logical_io_writes) END AS stdev_logical_io_writes,
				SUM(CASE WHEN c.avg_physical_io_reads IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_physical_io_reads) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_physical_io_reads IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_physical_io_reads,
				MIN(c.min_physical_io_reads) AS min_physical_io_reads,
				MAX(c.max_physical_io_reads) AS max_physical_io_reads,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_physical_io_reads) END AS stdev_physical_io_reads,
				SUM(CASE WHEN c.avg_clr_time IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_clr_time) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_clr_time IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_clr_time,
				MIN(c.min_clr_time) AS min_clr_time,
				MAX(c.max_clr_time) AS max_clr_time,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_clr_time) END AS stdev_clr_time,
				SUM(CASE WHEN c.avg_dop IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_dop) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_dop IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_dop,
				MIN(c.min_dop) AS min_dop,
				MAX(c.max_dop) AS max_dop,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_dop) END AS stdev_dop,
				SUM(CASE WHEN c.avg_query_max_used_memory IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_query_max_used_memory) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_query_max_used_memory IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_query_max_used_memory,
				MIN(c.min_query_max_used_memory) AS min_query_max_used_memory,
				MAX(c.max_query_max_used_memory) AS max_query_max_used_memory,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_query_max_used_memory) END AS stdev_query_max_used_memory,
				SUM(CASE WHEN c.avg_rowcount IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_rowcount) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_rowcount IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_rowcount,
				MIN(c.min_rowcount) AS min_rowcount,
				MAX(c.max_rowcount) AS max_rowcount,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_rowcount) END AS stdev_rowcount,
				SUM(CASE WHEN c.avg_num_physical_io_reads IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_num_physical_io_reads) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_num_physical_io_reads IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_num_physical_io_reads,
				MIN(c.min_num_physical_io_reads) AS min_num_physical_io_reads,
				MAX(c.max_num_physical_io_reads) AS max_num_physical_io_reads,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_num_physical_io_reads) END AS stdev_num_physical_io_reads,
				SUM(CASE WHEN c.avg_log_bytes_used IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_log_bytes_used) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_log_bytes_used IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_log_bytes_used,
				MIN(c.min_log_bytes_used) AS min_log_bytes_used,
				MAX(c.max_log_bytes_used) AS max_log_bytes_used,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_log_bytes_used) END AS stdev_log_bytes_used,
				SUM(CASE WHEN c.avg_tempdb_space_used IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_tempdb_space_used) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_tempdb_space_used IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_tempdb_space_used,
				MIN(c.min_tempdb_space_used) AS min_tempdb_space_used,
				MAX(c.max_tempdb_space_used) AS max_tempdb_space_used,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_tempdb_space_used) END AS stdev_tempdb_space_used,
				SUM(CASE WHEN c.avg_page_server_io_reads IS NOT NULL
					THEN CONVERT(FLOAT, c.avg_page_server_io_reads) * CONVERT(FLOAT, c.count_executions) END)
					/ NULLIF(SUM(CASE WHEN c.avg_page_server_io_reads IS NOT NULL
						THEN CONVERT(FLOAT, c.count_executions) END), 0.0) AS avg_page_server_io_reads,
				MIN(c.min_page_server_io_reads) AS min_page_server_io_reads,
				MAX(c.max_page_server_io_reads) AS max_page_server_io_reads,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.stdev_page_server_io_reads) END AS stdev_page_server_io_reads
			FROM dbo.query_store_runtime_stats_contributor AS c
			WHERE c.RunID = @RunID
			GROUP BY c.RunID, c.plan_id, c.runtime_stats_interval_id, c.execution_type
		),
		runtime_last AS
		(
			SELECT
				c.RunID,
				c.plan_id,
				c.runtime_stats_interval_id,
				c.execution_type,
				COUNT_BIG(*) AS latest_contributor_count,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.runtime_stats_contributor_id) END
					AS last_runtime_stats_contributor_id,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_duration) END AS last_duration,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_cpu_time) END AS last_cpu_time,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_logical_io_reads) END AS last_logical_io_reads,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_logical_io_writes) END AS last_logical_io_writes,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_physical_io_reads) END AS last_physical_io_reads,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_clr_time) END AS last_clr_time,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_dop) END AS last_dop,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_query_max_used_memory) END AS last_query_max_used_memory,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_rowcount) END AS last_rowcount,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_num_physical_io_reads) END AS last_num_physical_io_reads,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_log_bytes_used) END AS last_log_bytes_used,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_tempdb_space_used) END AS last_tempdb_space_used,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(c.last_page_server_io_reads) END AS last_page_server_io_reads
			FROM dbo.query_store_runtime_stats_contributor AS c
			INNER JOIN runtime_group AS g
				ON g.RunID = c.RunID
				AND g.plan_id = c.plan_id
				AND g.runtime_stats_interval_id = c.runtime_stats_interval_id
				AND g.execution_type = c.execution_type
				AND g.last_execution_time = c.last_execution_time
			GROUP BY c.RunID, c.plan_id, c.runtime_stats_interval_id, c.execution_type
		)
		INSERT dbo.query_store_runtime_stats_canonical
		(
			RunID, plan_id, runtime_stats_interval_id, execution_type, execution_type_desc,
			contributor_count, replica_group_id, replica_count,
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
			last_runtime_stats_contributor_id, last_value_ambiguous,
			stdev_aggregation_status, observation_state
		)
		SELECT
			g.RunID, g.plan_id, g.runtime_stats_interval_id, g.execution_type, g.execution_type_desc,
			g.contributor_count, g.replica_group_id, g.replica_count,
			g.first_execution_time, g.last_execution_time, g.count_executions,
			g.avg_duration, l.last_duration, g.min_duration, g.max_duration, g.stdev_duration,
			g.avg_cpu_time, l.last_cpu_time, g.min_cpu_time, g.max_cpu_time, g.stdev_cpu_time,
			g.avg_logical_io_reads, l.last_logical_io_reads, g.min_logical_io_reads, g.max_logical_io_reads, g.stdev_logical_io_reads,
			g.avg_logical_io_writes, l.last_logical_io_writes, g.min_logical_io_writes, g.max_logical_io_writes, g.stdev_logical_io_writes,
			g.avg_physical_io_reads, l.last_physical_io_reads, g.min_physical_io_reads, g.max_physical_io_reads, g.stdev_physical_io_reads,
			g.avg_clr_time, l.last_clr_time, g.min_clr_time, g.max_clr_time, g.stdev_clr_time,
			g.avg_dop, l.last_dop, g.min_dop, g.max_dop, g.stdev_dop,
			g.avg_query_max_used_memory, l.last_query_max_used_memory, g.min_query_max_used_memory, g.max_query_max_used_memory, g.stdev_query_max_used_memory,
			g.avg_rowcount, l.last_rowcount, g.min_rowcount, g.max_rowcount, g.stdev_rowcount,
			g.avg_num_physical_io_reads, l.last_num_physical_io_reads, g.min_num_physical_io_reads, g.max_num_physical_io_reads, g.stdev_num_physical_io_reads,
			g.avg_log_bytes_used, l.last_log_bytes_used, g.min_log_bytes_used, g.max_log_bytes_used, g.stdev_log_bytes_used,
			g.avg_tempdb_space_used, l.last_tempdb_space_used, g.min_tempdb_space_used, g.max_tempdb_space_used, g.stdev_tempdb_space_used,
			g.avg_page_server_io_reads, l.last_page_server_io_reads, g.min_page_server_io_reads, g.max_page_server_io_reads, g.stdev_page_server_io_reads,
			l.last_runtime_stats_contributor_id,
			CONVERT(BIT, CASE WHEN l.latest_contributor_count > 1 THEN 1 ELSE 0 END),
			CASE WHEN g.contributor_count = 1
				THEN N'NATIVE_SINGLE_CONTRIBUTOR'
				ELSE N'UNAVAILABLE_MULTIPLE_CONTRIBUTORS' END,
			@ObservationState
		FROM runtime_group AS g
		INNER JOIN runtime_last AS l
			ON l.RunID = g.RunID
			AND l.plan_id = g.plan_id
			AND l.runtime_stats_interval_id = g.runtime_stats_interval_id
			AND l.execution_type = g.execution_type;

		IF EXISTS
		(
			SELECT 1
			FROM dbo.query_store_wait_stats_contributor AS w
			LEFT JOIN dbo.query_store_runtime_stats_canonical AS r
				ON r.RunID = w.RunID
				AND r.plan_id = w.plan_id
				AND r.runtime_stats_interval_id = w.runtime_stats_interval_id
				AND r.execution_type = w.execution_type
			WHERE w.RunID = @RunID
				AND (r.RunID IS NULL OR r.count_executions <= 0)
		)
			THROW 51031, 'Wait statistics require a matching canonical runtime execution count.', 1;

		;WITH wait_group AS
		(
			SELECT
				w.RunID,
				w.plan_id,
				w.runtime_stats_interval_id,
				w.execution_type,
				MAX(w.execution_type_desc) AS execution_type_desc,
				w.wait_category,
				MAX(w.wait_category_desc) AS wait_category_desc,
				COUNT_BIG(*) AS contributor_count,
				CONVERT(INT,
					COUNT(DISTINCT w.replica_group_id)
					+ CASE WHEN COUNT_BIG(*) > COUNT(w.replica_group_id) THEN 1 ELSE 0 END
				) AS replica_count,
				CASE
					WHEN COUNT(DISTINCT w.replica_group_id)
						+ CASE WHEN COUNT_BIG(*) > COUNT(w.replica_group_id) THEN 1 ELSE 0 END = 1
					THEN MAX(w.replica_group_id)
				END AS replica_group_id,
				SUM(CONVERT(DECIMAL(38,0), w.total_query_wait_time_ms)) AS total_query_wait_time_ms,
				MIN(w.min_query_wait_time_ms) AS min_query_wait_time_ms,
				MAX(w.max_query_wait_time_ms) AS max_query_wait_time_ms,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(w.last_query_wait_time_ms) END AS last_query_wait_time_ms,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(w.wait_stats_contributor_id) END AS last_wait_stats_contributor_id,
				CASE WHEN COUNT_BIG(*) = 1 THEN MAX(w.stdev_query_wait_time_ms) END AS stdev_query_wait_time_ms
			FROM dbo.query_store_wait_stats_contributor AS w
			WHERE w.RunID = @RunID
			GROUP BY
				w.RunID, w.plan_id, w.runtime_stats_interval_id,
				w.execution_type, w.wait_category
		)
		INSERT dbo.query_store_wait_stats_canonical
		(
			RunID, plan_id, runtime_stats_interval_id, execution_type, execution_type_desc,
			wait_category, wait_category_desc,
			contributor_count, replica_group_id, replica_count,
			total_query_wait_time_ms, avg_query_wait_time_ms,
			last_query_wait_time_ms, min_query_wait_time_ms, max_query_wait_time_ms,
			stdev_query_wait_time_ms, last_wait_stats_contributor_id,
			last_value_ambiguous, stdev_aggregation_status, observation_state
		)
		SELECT
			w.RunID, w.plan_id, w.runtime_stats_interval_id, w.execution_type, w.execution_type_desc,
			w.wait_category, w.wait_category_desc,
			w.contributor_count, w.replica_group_id, w.replica_count,
			w.total_query_wait_time_ms,
			CONVERT(FLOAT, w.total_query_wait_time_ms) / NULLIF(CONVERT(FLOAT, r.count_executions), 0.0),
			w.last_query_wait_time_ms, w.min_query_wait_time_ms, w.max_query_wait_time_ms,
			w.stdev_query_wait_time_ms, w.last_wait_stats_contributor_id,
			CONVERT(BIT, CASE WHEN w.contributor_count > 1 THEN 1 ELSE 0 END),
			CASE WHEN w.contributor_count = 1
				THEN N'NATIVE_SINGLE_CONTRIBUTOR'
				ELSE N'UNAVAILABLE_MULTIPLE_CONTRIBUTORS' END,
			@ObservationState
		FROM wait_group AS w
		INNER JOIN dbo.query_store_runtime_stats_canonical AS r
			ON r.RunID = w.RunID
			AND r.plan_id = w.plan_id
			AND r.runtime_stats_interval_id = w.runtime_stats_interval_id
			AND r.execution_type = w.execution_type;

		IF @StartedTransaction = 1
			COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @StartedTransaction = 1 AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;
		ELSE IF @StartedTransaction = 0 AND XACT_STATE() = 1
			ROLLBACK TRANSACTION MaterializeCanonicalStats;

		THROW;
	END CATCH
END
GO

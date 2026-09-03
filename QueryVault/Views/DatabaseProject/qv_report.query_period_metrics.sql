CREATE VIEW qv_report.query_period_metrics
AS
	WITH runtime_aggregate AS
	(
		SELECT
			rs.RunID AS period_id,
			p.query_id,
			SUM(CONVERT(BIGINT, rs.count_executions)) AS execution_count,
			SUM(CONVERT(DECIMAL(38, 4), rs.avg_cpu_time) * rs.count_executions) / 1000.0 AS total_cpu_ms,
			SUM(CONVERT(DECIMAL(38, 4), rs.avg_duration) * rs.count_executions) / 1000.0 AS total_duration_ms,
			SUM(CONVERT(DECIMAL(38, 4), rs.avg_logical_io_reads) * rs.count_executions) AS total_logical_reads,
			MIN(rs.first_execution_time) AS first_execution_time,
			MAX(rs.last_execution_time) AS last_execution_time,
			CONVERT(BIGINT, COUNT(DISTINCT p.plan_id)) AS plan_count
		FROM dbo.query_store_runtime_stats AS rs
		INNER JOIN dbo.query_store_plan AS p
			ON p.RunID = rs.RunID
			AND p.plan_id = rs.plan_id
		GROUP BY rs.RunID, p.query_id
	)
	SELECT
		ra.period_id,
		pr.source_server_name,
		pr.source_database_name,
		pr.period_start_utc,
		pr.period_end_utc,
		ra.query_id,
		CONVERT(VARCHAR(18), q.query_hash, 1) AS query_hash_hex,
		CASE
			WHEN qt.is_part_of_encrypted_module = 1 OR qt.has_restricted_text = 1
				THEN N'[Query text restricted]'
			ELSE LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N' '), CHAR(10), N' '), 4000)
		END AS query_text_preview,
		ra.execution_count,
		ra.total_cpu_ms,
		ra.total_duration_ms,
		ra.total_logical_reads,
		ra.total_cpu_ms / NULLIF(ra.execution_count, 0) AS avg_cpu_ms,
		ra.total_duration_ms / NULLIF(ra.execution_count, 0) AS avg_duration_ms,
		ra.total_logical_reads / NULLIF(ra.execution_count, 0) AS avg_logical_reads,
		ra.first_execution_time,
		ra.last_execution_time,
		ra.plan_count
	FROM runtime_aggregate AS ra
	INNER JOIN qv_report.periods AS pr
		ON pr.period_id = ra.period_id
	INNER JOIN dbo.query_store_query AS q
		ON q.RunID = ra.period_id
		AND q.query_id = ra.query_id
	INNER JOIN dbo.query_store_query_text AS qt
		ON qt.RunID = q.RunID
		AND qt.query_text_id = q.query_text_id;
GO

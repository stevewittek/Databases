CREATE VIEW qv_report.period_metrics
AS
	SELECT
		pr.period_id,
		pr.period_name,
		pr.source_server_name,
		pr.source_database_name,
		pr.period_start_utc,
		pr.period_end_utc,
		pr.period_status,
		pr.observation_state,
		pr.period_classification,
		COALESCE(SUM(qm.execution_count), 0) AS execution_count,
		COALESCE(SUM(qm.total_cpu_ms), 0) AS total_cpu_ms,
		COALESCE(SUM(qm.total_duration_ms), 0) AS total_duration_ms,
		COALESCE(SUM(qm.total_logical_reads), 0) AS total_logical_reads,
		CONVERT(BIGINT, COUNT(qm.query_id)) AS query_count,
		COALESCE(SUM(qm.plan_count), 0) AS plan_count
	FROM qv_report.periods AS pr
	LEFT JOIN qv_report.query_period_metrics AS qm
		ON qm.period_id = pr.period_id
	GROUP BY
		pr.period_id,
		pr.period_name,
		pr.source_server_name,
		pr.source_database_name,
		pr.period_start_utc,
		pr.period_end_utc,
		pr.period_status,
		pr.observation_state,
		pr.period_classification;
GO

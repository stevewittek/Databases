/* Wait totals by archived period and native Query Store wait category. */

CREATE VIEW qv_report.wait_period_metrics
AS
	SELECT
		ws.RunID AS period_id,
		pr.source_server_name,
		pr.source_database_name,
		ws.wait_category,
		COALESCE(ws.wait_category_desc, N'Unknown') AS wait_category_desc,
		SUM(CONVERT(DECIMAL(38, 4), ws.total_query_wait_time_ms)) AS total_wait_ms,
		MAX(ws.max_query_wait_time_ms) AS max_query_wait_time_ms
	FROM dbo.query_store_wait_stats AS ws
	INNER JOIN qv_report.periods AS pr
		ON pr.period_id = ws.RunID
	GROUP BY
		ws.RunID,
		pr.source_server_name,
		pr.source_database_name,
		ws.wait_category,
		ws.wait_category_desc;
GO

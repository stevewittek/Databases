CREATE VIEW qv_report.wait_period_metrics
AS
	WITH wait_observation AS
	(
		SELECT
			RunID, wait_category, wait_category_desc,
			total_query_wait_time_ms, max_query_wait_time_ms
		FROM dbo.query_store_wait_stats_canonical

		UNION ALL

		SELECT
			legacy.RunID, legacy.wait_category, legacy.wait_category_desc,
			CONVERT(DECIMAL(38,0), legacy.total_query_wait_time_ms),
			legacy.max_query_wait_time_ms
		FROM dbo.query_store_wait_stats AS legacy
		WHERE NOT EXISTS
		(
			SELECT 1
			FROM dbo.query_store_wait_stats_canonical AS canonical
			WHERE canonical.RunID = legacy.RunID
		)
	)
	SELECT
		ws.RunID AS period_id,
		pr.source_server_name,
		pr.source_database_name,
		ws.wait_category,
		COALESCE(ws.wait_category_desc, N'Unknown') AS wait_category_desc,
		SUM(CONVERT(DECIMAL(38, 4), ws.total_query_wait_time_ms)) AS total_wait_ms,
		MAX(ws.max_query_wait_time_ms) AS max_query_wait_time_ms
	FROM wait_observation AS ws
	INNER JOIN qv_report.periods AS pr
		ON pr.period_id = ws.RunID
	GROUP BY
		ws.RunID,
		pr.source_server_name,
		pr.source_database_name,
		ws.wait_category,
		ws.wait_category_desc;
GO

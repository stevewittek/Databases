/* Wait totals attributable to each query in an archived period. */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW qv_report.query_wait_period_metrics
AS
	WITH wait_observation AS
	(
		SELECT
			RunID, plan_id, wait_category, wait_category_desc,
			total_query_wait_time_ms, max_query_wait_time_ms
		FROM dbo.query_store_wait_stats_canonical

		UNION ALL

		SELECT
			legacy.RunID, legacy.plan_id, legacy.wait_category, legacy.wait_category_desc,
			CONVERT(DECIMAL(38,0), legacy.total_query_wait_time_ms),
			legacy.max_query_wait_time_ms
		FROM dbo.query_store_wait_stats AS legacy
		WHERE NOT EXISTS
		(
			SELECT 1
			FROM dbo.query_store_wait_stats_canonical AS canonical
			WHERE canonical.RunID = legacy.RunID
		)
	),
	wait_aggregate AS
	(
		SELECT
			ws.RunID AS period_id,
			p.query_id,
			ws.wait_category,
			COALESCE(ws.wait_category_desc, N'Unknown') AS wait_category_desc,
			SUM(CONVERT(DECIMAL(38, 4), ws.total_query_wait_time_ms)) AS total_wait_ms,
			MAX(ws.max_query_wait_time_ms) AS max_query_wait_time_ms
		FROM wait_observation AS ws
		INNER JOIN dbo.query_store_plan AS p
			ON p.RunID = ws.RunID
			AND p.plan_id = ws.plan_id
		GROUP BY
			ws.RunID,
			p.query_id,
			ws.wait_category,
			ws.wait_category_desc
	)
	SELECT
		wa.period_id,
		pr.source_server_name,
		pr.source_database_name,
		wa.query_id,
		CONVERT(VARCHAR(18), q.query_hash, 1) AS query_hash_hex,
		CASE
			WHEN qt.is_part_of_encrypted_module = 1 OR qt.has_restricted_text = 1
				THEN N'[Query text restricted]'
			ELSE LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N' '), CHAR(10), N' '), 4000)
		END AS query_text_preview,
		wa.wait_category,
		wa.wait_category_desc,
		wa.total_wait_ms,
		wa.max_query_wait_time_ms
	FROM wait_aggregate AS wa
	INNER JOIN dbo.query_store_query AS q
		ON q.RunID = wa.period_id
		AND q.query_id = wa.query_id
	INNER JOIN dbo.query_store_query_text AS qt
		ON qt.RunID = q.RunID
		AND qt.query_text_id = q.query_text_id
	INNER JOIN qv_report.periods AS pr
		ON pr.period_id = wa.period_id;
GO

/* One row per archived Query Store period. */

CREATE VIEW qv_report.periods
AS
	SELECT
		rm.RunID AS period_id,
		rm.RunName AS period_name,
		rm.SourceServerName AS source_server_name,
		rm.SourceDatabaseName AS source_database_name,
		rm.StartDateTime AS period_start_utc,
		rm.EndDateTime AS period_end_utc,
		rm.RunStatus AS period_status,
		CAST(NULL AS NVARCHAR(100)) AS period_classification,
		rm.DoNotDelete AS is_protected,
		rm.RetentionDate AS retention_utc,
		rm.RunStartTime AS archive_started_utc,
		rm.RunEndTime AS archive_ended_utc,
		rm.RowsArchived_Query AS archived_query_rows,
		rm.RowsArchived_QueryText AS archived_query_text_rows,
		rm.RowsArchived_Plan AS archived_plan_rows,
		rm.RowsArchived_RuntimeStats AS archived_runtime_stats_rows,
		rm.RowsArchived_RuntimeStatsInterval AS archived_interval_rows,
		rm.RowsArchived_WaitStats AS archived_wait_stats_rows,
		CONVERT(BIGINT,
			ISNULL(rm.RowsArchived_Query, 0)
			+ ISNULL(rm.RowsArchived_QueryText, 0)
			+ ISNULL(rm.RowsArchived_Plan, 0)
			+ ISNULL(rm.RowsArchived_RuntimeStats, 0)
			+ ISNULL(rm.RowsArchived_RuntimeStatsInterval, 0)
			+ ISNULL(rm.RowsArchived_WaitStats, 0)) AS archived_total_rows
	FROM dbo.RunMetadata AS rm;
GO

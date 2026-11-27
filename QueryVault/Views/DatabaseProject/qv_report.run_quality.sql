CREATE VIEW qv_report.run_quality
AS
WITH intervals AS
(
    SELECT RunID, runtime_stats_interval_id, start_time, end_time,
        LAG(end_time) OVER (PARTITION BY RunID ORDER BY start_time, end_time, runtime_stats_interval_id) AS previous_end
    FROM dbo.query_store_runtime_stats_interval
), coverage AS
(
    SELECT i.RunID, COUNT_BIG(*) AS interval_count,
        MIN(i.start_time) AS captured_start_utc, MAX(i.end_time) AS captured_end_utc,
        SUM(CONVERT(FLOAT, DATEDIFF_BIG(MILLISECOND, i.start_time, i.end_time))) / 1000.0 AS captured_seconds,
        SUM(CASE WHEN i.end_time <= i.start_time THEN 1 ELSE 0 END) AS invalid_intervals,
        SUM(CASE WHEN i.previous_end > i.start_time THEN 1 ELSE 0 END) AS overlapping_intervals,
        SUM(CASE WHEN i.start_time < (rm.StartDateTime AT TIME ZONE 'UTC')
                   OR i.end_time > (rm.EndDateTime AT TIME ZONE 'UTC') THEN 1 ELSE 0 END) AS outside_window_intervals
    FROM intervals AS i INNER JOIN dbo.RunMetadata AS rm ON rm.RunID = i.RunID
    GROUP BY i.RunID
), orphans AS
(
    SELECT r.RunID, COUNT_BIG(*) AS orphan_runtime_rows
    FROM dbo.query_store_runtime_stats_canonical AS r
    LEFT JOIN dbo.query_store_runtime_stats_interval AS i
      ON i.RunID = r.RunID AND i.runtime_stats_interval_id = r.runtime_stats_interval_id
    WHERE i.runtime_stats_interval_id IS NULL GROUP BY r.RunID
), metadata_gaps AS
(
    SELECT r.RunID, COUNT_BIG(*) AS missing_metadata_rows
    FROM dbo.query_store_runtime_stats_canonical AS r
    LEFT JOIN dbo.query_store_plan AS p ON p.RunID=r.RunID AND p.plan_id=r.plan_id
    LEFT JOIN dbo.query_store_query AS q ON q.RunID=p.RunID AND q.query_id=p.query_id
    LEFT JOIN dbo.query_store_query_text AS t ON t.RunID=q.RunID AND t.query_text_id=q.query_text_id
    WHERE p.plan_id IS NULL OR q.query_id IS NULL OR t.query_text_id IS NULL GROUP BY r.RunID
), wait_gaps AS
(
    SELECT w.RunID, COUNT_BIG(*) AS orphan_wait_rows
    FROM dbo.query_store_wait_stats_canonical AS w
    LEFT JOIN dbo.query_store_runtime_stats_interval AS i ON i.RunID=w.RunID AND i.runtime_stats_interval_id=w.runtime_stats_interval_id
    LEFT JOIN dbo.query_store_runtime_stats_canonical AS r ON r.RunID=w.RunID AND r.plan_id=w.plan_id
        AND r.runtime_stats_interval_id=w.runtime_stats_interval_id AND r.execution_type=w.execution_type
    WHERE i.runtime_stats_interval_id IS NULL OR r.plan_id IS NULL GROUP BY w.RunID
)
SELECT p.period_id, p.period_name, p.source_server_name, p.source_database_name,
    p.period_start_utc, p.period_end_utc, p.period_status, p.observation_state,
    p.period_classification, ac.ExperimentName AS experiment_name, ac.WorkloadName AS workload_name,
    ac.Variant AS variant, ac.DeploymentLabel AS deployment_label, ac.QueryStoreEpoch AS query_store_epoch,
    CONVERT(FLOAT, DATEDIFF_BIG(MILLISECOND, p.period_start_utc, p.period_end_utc))/1000.0 AS requested_seconds,
    COALESCE(c.interval_count,0) AS interval_count, c.captured_start_utc, c.captured_end_utc, c.captured_seconds,
    COALESCE(c.invalid_intervals,0) AS invalid_intervals,
    COALESCE(c.overlapping_intervals,0) AS overlapping_intervals,
    COALESCE(c.outside_window_intervals,0) AS outside_window_intervals,
    COALESCE(o.orphan_runtime_rows,0) AS orphan_runtime_rows,
    COALESCE(m.missing_metadata_rows,0) AS missing_metadata_rows,
    COALESCE(w.orphan_wait_rows,0) AS orphan_wait_rows,
    CASE WHEN EXISTS (SELECT 1 FROM dbo.query_store_wait_stats_canonical AS w WHERE w.RunID=p.period_id)
        THEN N'OBSERVED' ELSE N'NO_WAIT_OBSERVATIONS' END AS wait_data_state,
    CONVERT(BIT, CASE WHEN p.period_status=N'Completed' AND p.observation_state=N'COMPLETED'
        AND c.captured_seconds>0 AND c.invalid_intervals=0 AND c.overlapping_intervals=0
        AND c.outside_window_intervals=0 AND COALESCE(o.orphan_runtime_rows,0)=0
        AND COALESCE(m.missing_metadata_rows,0)=0 AND COALESCE(w.orphan_wait_rows,0)=0 THEN 1 ELSE 0 END) AS is_comparison_ready
FROM qv_report.periods AS p
LEFT JOIN coverage AS c ON c.RunID=p.period_id
LEFT JOIN orphans AS o ON o.RunID=p.period_id
LEFT JOIN metadata_gaps AS m ON m.RunID=p.period_id
LEFT JOIN wait_gaps AS w ON w.RunID=p.period_id
LEFT JOIN dbo.RunAnalysisContext AS ac ON ac.RunID=p.period_id;
GO

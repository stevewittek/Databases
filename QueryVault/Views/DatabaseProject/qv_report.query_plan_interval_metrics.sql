CREATE VIEW qv_report.query_plan_interval_metrics
AS
    WITH wait_totals AS
    (
        SELECT
            ws.RunID,
            ws.plan_id,
            ws.runtime_stats_interval_id,
            ws.execution_type,
            SUM(CONVERT(DECIMAL(38,4), ws.total_query_wait_time_ms)) AS total_wait_ms
        FROM dbo.query_store_wait_stats_canonical AS ws
        WHERE ws.observation_state = N'COMPLETED'
        GROUP BY ws.RunID, ws.plan_id, ws.runtime_stats_interval_id, ws.execution_type
    )
    SELECT
        pr.period_id,
        pr.source_server_name,
        pr.source_database_name,
        pr.period_start_utc,
        pr.period_end_utc,
        pr.period_status,
        pr.observation_state AS period_observation_state,
        q.query_id,
        p.plan_id,
        CONVERT(VARCHAR(18), q.query_hash, 1) AS query_hash_hex,
        CONVERT(VARCHAR(18), p.query_plan_hash, 1) AS query_plan_hash_hex,
        p.compatibility_level,
        p.engine_version,
        p.is_parallel_plan,
        p.is_forced_plan,
        p.plan_type_desc,
        i.runtime_stats_interval_id,
        i.start_time AS interval_start_utc,
        i.end_time AS interval_end_utc,
        rs.execution_type,
        rs.execution_type_desc,
        rs.observation_state AS runtime_observation_state,
        rs.first_execution_time,
        rs.last_execution_time,
        rs.count_executions AS execution_count,
        CONVERT(DECIMAL(38,4), rs.avg_cpu_time) * rs.count_executions / 1000.0 AS total_cpu_ms,
        CONVERT(DECIMAL(38,4), rs.avg_duration) * rs.count_executions / 1000.0 AS total_duration_ms,
        CONVERT(DECIMAL(38,4), rs.avg_logical_io_reads) * rs.count_executions AS total_logical_reads,
        CONVERT(DECIMAL(38,4), rs.avg_logical_io_writes) * rs.count_executions AS total_logical_writes,
        CONVERT(DECIMAL(38,4), rs.avg_cpu_time) / 1000.0 AS avg_cpu_ms,
        CONVERT(DECIMAL(38,4), rs.avg_duration) / 1000.0 AS avg_duration_ms,
        CONVERT(DECIMAL(38,4), rs.avg_logical_io_reads) AS avg_logical_reads,
        CONVERT(DECIMAL(38,4), rs.avg_logical_io_writes) AS avg_logical_writes,
        CONVERT(DECIMAL(38,4), rs.avg_dop) AS avg_dop,
        wt.total_wait_ms,
        CASE WHEN wt.total_wait_ms IS NULL THEN CONVERT(BIT, 0)
             ELSE CONVERT(BIT, 1) END AS has_wait_observation,
        CASE
            WHEN pr.observation_state <> N'COMPLETED'
                THEN N'PERIOD_NOT_FINAL'
            WHEN i.start_time < CONVERT(DATETIMEOFFSET(7), pr.period_start_utc)
                OR i.end_time > CONVERT(DATETIMEOFFSET(7), pr.period_end_utc)
                THEN N'PARTIAL_INTERVAL'
            ELSE N'COMPLETE_INTERVAL'
        END AS evidence_quality,
        CASE
            WHEN pr.observation_state = N'COMPLETED'
                 AND i.start_time >= CONVERT(DATETIMEOFFSET(7), pr.period_start_utc)
                 AND i.end_time <= CONVERT(DATETIMEOFFSET(7), pr.period_end_utc)
                THEN CONVERT(BIT, 1)
            ELSE CONVERT(BIT, 0)
        END AS baseline_eligible
    FROM dbo.query_store_runtime_stats_canonical AS rs
    INNER JOIN qv_report.periods AS pr
        ON pr.period_id = rs.RunID
        AND pr.period_status = N'Completed'
    INNER JOIN dbo.query_store_runtime_stats_interval AS i
        ON i.RunID = rs.RunID
        AND i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    INNER JOIN dbo.query_store_plan AS p
        ON p.RunID = rs.RunID
        AND p.plan_id = rs.plan_id
    INNER JOIN dbo.query_store_query AS q
        ON q.RunID = p.RunID
        AND q.query_id = p.query_id
    LEFT JOIN wait_totals AS wt
        ON wt.RunID = rs.RunID
        AND wt.plan_id = rs.plan_id
        AND wt.runtime_stats_interval_id = rs.runtime_stats_interval_id
        AND wt.execution_type = rs.execution_type
    WHERE rs.observation_state = N'COMPLETED';
GO

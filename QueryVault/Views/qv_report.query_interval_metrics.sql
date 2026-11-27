SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Canonical-only timeline. Keep RunID in every join; never sum overlapping archive snapshots.
   Success, abort and exception outcomes remain distinct. All durations below are milliseconds. */
CREATE OR ALTER VIEW qv_report.query_interval_metrics
AS
SELECT r.RunID AS period_id, p.query_id, r.plan_id, r.execution_type,
    r.execution_type_desc, r.observation_state, r.runtime_stats_interval_id,
    CONVERT(DATETIME2(7), SWITCHOFFSET(i.start_time,'+00:00')) AS interval_start_utc,
    CONVERT(DATETIME2(7), SWITCHOFFSET(i.end_time,'+00:00')) AS interval_end_utc,
    CONVERT(FLOAT,DATEDIFF_BIG(MILLISECOND,i.start_time,i.end_time))/1000.0 AS interval_seconds,
    r.count_executions AS execution_count,
    r.avg_duration/1000.0 AS avg_duration_ms, r.max_duration/1000.0 AS max_duration_ms,
    r.avg_cpu_time/1000.0 AS avg_cpu_ms, r.avg_logical_io_reads AS avg_logical_reads,
    r.avg_duration*CONVERT(FLOAT,r.count_executions)/1000.0 AS total_duration_ms,
    r.avg_cpu_time*CONVERT(FLOAT,r.count_executions)/1000.0 AS total_cpu_ms,
    r.avg_logical_io_reads*CONVERT(FLOAT,r.count_executions) AS total_logical_reads,
    r.avg_physical_io_reads AS avg_physical_reads, r.avg_logical_io_writes AS avg_logical_writes,
    r.avg_dop, r.avg_query_max_used_memory*8.0 AS avg_max_used_memory_kb,
    r.avg_tempdb_space_used*8.0 AS avg_tempdb_space_kb,
    r.avg_log_bytes_used AS avg_log_bytes_used
FROM dbo.query_store_runtime_stats_canonical AS r
INNER JOIN dbo.query_store_runtime_stats_interval AS i ON i.RunID=r.RunID AND i.runtime_stats_interval_id=r.runtime_stats_interval_id
INNER JOIN dbo.query_store_plan AS p ON p.RunID=r.RunID AND p.plan_id=r.plan_id;
GO

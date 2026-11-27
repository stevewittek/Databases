SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Per-query before/after analysis. Missing-side metrics remain NULL, never manufactured as zero.
   Query IDs are matched only within a guarded source pair, then identity evidence is checked.
   No arbitrary pairs of all historical runs are materialized. */
CREATE OR ALTER FUNCTION qv_report.fn_CompareRuns(@BaselineRunID INT, @CandidateRunID INT)
RETURNS TABLE
AS RETURN
WITH b AS (SELECT * FROM qv_report.query_period_metrics WHERE period_id=@BaselineRunID),
     c AS (SELECT * FROM qv_report.query_period_metrics WHERE period_id=@CandidateRunID),
paired AS
(
    SELECT COALESCE(b.query_id,c.query_id) AS query_id,
        COALESCE(c.query_text_preview,b.query_text_preview) AS query_text_preview,
        b.execution_count AS baseline_executions, c.execution_count AS candidate_executions,
        b.avg_duration_ms AS baseline_avg_duration_ms, c.avg_duration_ms AS candidate_avg_duration_ms,
        b.avg_cpu_ms AS baseline_avg_cpu_ms, c.avg_cpu_ms AS candidate_avg_cpu_ms,
        b.avg_logical_reads AS baseline_avg_reads, c.avg_logical_reads AS candidate_avg_reads,
        b.total_duration_ms AS baseline_total_duration_ms, c.total_duration_ms AS candidate_total_duration_ms,
        b.total_cpu_ms AS baseline_total_cpu_ms, c.total_cpu_ms AS candidate_total_cpu_ms,
        b.total_logical_reads AS baseline_total_reads, c.total_logical_reads AS candidate_total_reads,
        b.plan_count AS baseline_plan_count, c.plan_count AS candidate_plan_count,
        CASE WHEN b.query_id IS NULL THEN N'NEW' WHEN c.query_id IS NULL THEN N'NOT_OBSERVED'
            WHEN bi.query_hash IS NULL OR ci.query_hash IS NULL OR bi.text_digest IS NULL OR ci.text_digest IS NULL THEN N'IDENTITY_UNVERIFIED'
            WHEN bi.query_hash<>ci.query_hash OR bi.context_settings_id<>ci.context_settings_id
              OR COALESCE(bi.object_id,-1)<>COALESCE(ci.object_id,-1) OR bi.text_digest<>ci.text_digest
              OR bi.initial_compile_start_time<>ci.initial_compile_start_time THEN N'IDENTITY_CHANGED'
            ELSE N'MATCHED' END AS match_state
    FROM b FULL OUTER JOIN c ON c.query_id=b.query_id
    LEFT JOIN qv_report.query_identity AS bi ON bi.period_id=@BaselineRunID AND bi.query_id=b.query_id
    LEFT JOIN qv_report.query_identity AS ci ON ci.period_id=@CandidateRunID AND ci.query_id=c.query_id
), measured AS
(
    SELECT p.*, q.baseline_seconds, q.candidate_seconds, q.identity_confidence,
        p.baseline_executions/NULLIF(q.baseline_seconds,0) AS baseline_executions_per_second,
        p.candidate_executions/NULLIF(q.candidate_seconds,0) AS candidate_executions_per_second,
        p.baseline_total_cpu_ms/NULLIF(q.baseline_seconds,0)*3600.0 AS baseline_cpu_ms_per_hour,
        p.candidate_total_cpu_ms/NULLIF(q.candidate_seconds,0)*3600.0 AS candidate_cpu_ms_per_hour
    FROM paired AS p CROSS JOIN qv_report.fn_CompareRunQuality(@BaselineRunID,@CandidateRunID) AS q
    WHERE q.comparison_state=N'READY'
)
SELECT @BaselineRunID AS baseline_run_id, @CandidateRunID AS candidate_run_id, m.*,
    CASE WHEN match_state=N'MATCHED' THEN candidate_avg_duration_ms-baseline_avg_duration_ms END AS avg_duration_delta_ms,
    CASE WHEN match_state=N'MATCHED' THEN 100.0*(candidate_avg_duration_ms-baseline_avg_duration_ms)/NULLIF(baseline_avg_duration_ms,0) END AS avg_duration_delta_pct,
    CASE WHEN match_state=N'MATCHED' THEN 100.0*(candidate_avg_cpu_ms-baseline_avg_cpu_ms)/NULLIF(baseline_avg_cpu_ms,0) END AS avg_cpu_delta_pct,
    CASE WHEN match_state=N'MATCHED' THEN 100.0*(candidate_avg_reads-baseline_avg_reads)/NULLIF(baseline_avg_reads,0) END AS avg_reads_delta_pct,
    CASE WHEN match_state=N'MATCHED' THEN candidate_total_duration_ms-baseline_total_duration_ms END AS total_duration_delta_ms,
    CASE WHEN match_state=N'MATCHED' THEN (candidate_avg_duration_ms-baseline_avg_duration_ms)*candidate_executions END AS estimated_extra_duration_ms,
    CASE WHEN match_state<>N'MATCHED' THEN NULL
        WHEN EXISTS (SELECT p.query_plan_hash FROM dbo.query_store_plan AS p WHERE p.RunID=@BaselineRunID AND p.query_id=m.query_id
                     EXCEPT SELECT p.query_plan_hash FROM dbo.query_store_plan AS p WHERE p.RunID=@CandidateRunID AND p.query_id=m.query_id)
          OR EXISTS (SELECT p.query_plan_hash FROM dbo.query_store_plan AS p WHERE p.RunID=@CandidateRunID AND p.query_id=m.query_id
                     EXCEPT SELECT p.query_plan_hash FROM dbo.query_store_plan AS p WHERE p.RunID=@BaselineRunID AND p.query_id=m.query_id)
        THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END AS plan_inventory_changed
FROM measured AS m;
GO

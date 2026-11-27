SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Wait category totals plus per-execution intensity. Absence is unavailable, not zero. */
CREATE OR ALTER FUNCTION qv_report.fn_CompareWaits(@BaselineRunID INT, @CandidateRunID INT)
RETURNS TABLE
AS RETURN
WITH b AS (SELECT * FROM qv_report.wait_period_metrics WHERE period_id=@BaselineRunID),
     c AS (SELECT * FROM qv_report.wait_period_metrics WHERE period_id=@CandidateRunID)
SELECT @BaselineRunID AS baseline_run_id, @CandidateRunID AS candidate_run_id,
    COALESCE(c.wait_category,b.wait_category) AS wait_category,
    COALESCE(c.wait_category_desc,b.wait_category_desc) AS wait_category_desc,
    b.total_wait_ms AS baseline_wait_ms, c.total_wait_ms AS candidate_wait_ms,
    b.total_wait_ms/NULLIF(q.baseline_seconds,0)*3600 AS baseline_wait_ms_per_hour,
    c.total_wait_ms/NULLIF(q.candidate_seconds,0)*3600 AS candidate_wait_ms_per_hour,
    b.total_wait_ms/NULLIF(bm.execution_count,0) AS baseline_wait_ms_per_execution,
    c.total_wait_ms/NULLIF(cm.execution_count,0) AS candidate_wait_ms_per_execution,
    CASE WHEN b.wait_category IS NULL THEN N'NO_BASELINE_OBSERVATION'
         WHEN c.wait_category IS NULL THEN N'NO_CANDIDATE_OBSERVATION' ELSE N'BOTH_OBSERVED' END AS observation_state
FROM b FULL OUTER JOIN c ON b.wait_category=c.wait_category
CROSS JOIN qv_report.fn_CompareRunQuality(@BaselineRunID,@CandidateRunID) AS q
LEFT JOIN qv_report.period_metrics AS bm ON bm.period_id=@BaselineRunID
LEFT JOIN qv_report.period_metrics AS cm ON cm.period_id=@CandidateRunID
WHERE q.comparison_state=N'READY';
GO

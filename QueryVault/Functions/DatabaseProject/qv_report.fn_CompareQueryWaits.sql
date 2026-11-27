CREATE FUNCTION qv_report.fn_CompareQueryWaits(@BaselineRunID INT, @CandidateRunID INT)
RETURNS TABLE
AS RETURN
WITH b AS (SELECT * FROM qv_report.query_wait_period_metrics WHERE period_id=@BaselineRunID),
     c AS (SELECT * FROM qv_report.query_wait_period_metrics WHERE period_id=@CandidateRunID)
SELECT p.query_id, COALESCE(c.wait_category,b.wait_category) AS wait_category,
    COALESCE(c.wait_category_desc,b.wait_category_desc) AS wait_category_desc,
    b.total_wait_ms AS baseline_wait_ms, c.total_wait_ms AS candidate_wait_ms,
    b.total_wait_ms/NULLIF(p.baseline_executions,0) AS baseline_wait_ms_per_execution,
    c.total_wait_ms/NULLIF(p.candidate_executions,0) AS candidate_wait_ms_per_execution,
    c.total_wait_ms/NULLIF(p.candidate_executions,0)-b.total_wait_ms/NULLIF(p.baseline_executions,0) AS wait_per_execution_delta_ms,
    CASE WHEN b.query_id IS NULL THEN N'NO_BASELINE_OBSERVATION'
         WHEN c.query_id IS NULL THEN N'NO_CANDIDATE_OBSERVATION' ELSE N'BOTH_OBSERVED' END AS observation_state
FROM b FULL OUTER JOIN c ON b.query_id=c.query_id AND b.wait_category=c.wait_category
INNER JOIN qv_report.fn_CompareRuns(@BaselineRunID,@CandidateRunID) AS p ON p.query_id=COALESCE(b.query_id,c.query_id)
WHERE p.match_state=N'MATCHED';
GO

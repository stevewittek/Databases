/* Read-only SSMS / sqlcmd report. Set two explicit run IDs from the discovery query. */
SET NOCOUNT ON;
DECLARE @BaselineRunID INT=NULL, @CandidateRunID INT=NULL;
DECLARE @MinimumExecutions INT=10, @RegressionPercent FLOAT=20;
IF @BaselineRunID IS NULL OR @CandidateRunID IS NULL
BEGIN
    SELECT * FROM qv_report.run_quality ORDER BY period_start_utc DESC,period_id DESC;
    THROW 51240,'Set @BaselineRunID and @CandidateRunID from the discovery result.',1;
END;
SELECT * FROM qv_report.fn_CompareRunQuality(@BaselineRunID,@CandidateRunID);
IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRunQuality(@BaselineRunID,@CandidateRunID) WHERE comparison_state=N'READY')
    THROW 51241,'This run pair is not comparable. Inspect the readiness result.',1;
SELECT * FROM qv_report.run_quality WHERE period_id IN (@BaselineRunID,@CandidateRunID);
SELECT TOP (100) * FROM qv_report.fn_CompareRuns(@BaselineRunID,@CandidateRunID)
WHERE match_state=N'MATCHED' AND baseline_executions>=@MinimumExecutions AND candidate_executions>=@MinimumExecutions
    AND avg_duration_delta_pct>=@RegressionPercent
ORDER BY estimated_extra_duration_ms DESC,query_id;
SELECT TOP (100) * FROM qv_report.fn_CompareRuns(@BaselineRunID,@CandidateRunID)
WHERE match_state=N'MATCHED' AND baseline_executions>=@MinimumExecutions AND candidate_executions>=@MinimumExecutions
    AND avg_duration_delta_pct<=-@RegressionPercent
ORDER BY estimated_extra_duration_ms,query_id;
SELECT * FROM qv_report.fn_CompareRuns(@BaselineRunID,@CandidateRunID) WHERE match_state<>N'MATCHED' ORDER BY query_id;
SELECT * FROM qv_report.fn_CompareWaits(@BaselineRunID,@CandidateRunID) ORDER BY candidate_wait_ms DESC;

SELECT TOP (100) * FROM qv_report.fn_CompareQueryWaits(@BaselineRunID,@CandidateRunID)
ORDER BY wait_per_execution_delta_ms DESC,query_id,wait_category;

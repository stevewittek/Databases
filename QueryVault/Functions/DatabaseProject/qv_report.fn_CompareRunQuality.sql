CREATE FUNCTION qv_report.fn_CompareRunQuality(@BaselineRunID INT, @CandidateRunID INT)
RETURNS TABLE
AS RETURN
SELECT @BaselineRunID AS baseline_run_id, @CandidateRunID AS candidate_run_id,
    b.captured_seconds AS baseline_seconds, c.captured_seconds AS candidate_seconds,
    b.wait_data_state AS baseline_wait_state, c.wait_data_state AS candidate_wait_state,
    CASE
        WHEN b.period_id IS NULL OR c.period_id IS NULL THEN N'RUN_NOT_FOUND'
        WHEN b.period_id=c.period_id THEN N'SAME_RUN'
        WHEN b.source_server_name COLLATE Latin1_General_100_BIN2<>c.source_server_name COLLATE Latin1_General_100_BIN2
          OR b.source_database_name COLLATE Latin1_General_100_BIN2<>c.source_database_name COLLATE Latin1_General_100_BIN2 THEN N'SOURCE_MISMATCH'
        WHEN b.is_comparison_ready=0 OR c.is_comparison_ready=0 THEN N'RUN_NOT_READY'
        WHEN b.captured_start_utc<c.captured_end_utc AND c.captured_start_utc<b.captured_end_utc THEN N'OVERLAPPING_WINDOWS'
        WHEN b.query_store_epoch IS NOT NULL AND c.query_store_epoch IS NOT NULL AND b.query_store_epoch<>c.query_store_epoch THEN N'EPOCH_MISMATCH'
        ELSE N'READY' END AS comparison_state,
    CASE WHEN b.query_store_epoch IS NOT NULL AND b.query_store_epoch=c.query_store_epoch
        THEN N'OPERATOR_CONFIRMED_EPOCH' ELSE N'UNVERIFIED_QUERY_STORE_CONTINUITY' END AS identity_confidence,
    CONVERT(BIT,CASE WHEN b.captured_seconds<>c.captured_seconds THEN 1 ELSE 0 END) AS unequal_windows,
    CONVERT(BIT,CASE WHEN b.workload_name=c.workload_name AND b.experiment_name=c.experiment_name THEN 1 ELSE 0 END) AS same_experiment,
    CASE WHEN c.captured_start_utc<b.captured_start_utc THEN N'CANDIDATE_PRECEDES_BASELINE' ELSE N'FORWARD' END AS time_direction
FROM (VALUES (1)) AS anchor(n)
LEFT JOIN qv_report.run_quality AS b ON b.period_id=@BaselineRunID
LEFT JOIN qv_report.run_quality AS c ON c.period_id=@CandidateRunID;
GO

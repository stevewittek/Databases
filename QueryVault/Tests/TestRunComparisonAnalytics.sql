/* Deterministic transaction-only fixtures; requires the analytics schema already deployed.
   No source Query Store changes, partition maintenance or retained test data. */
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @b INT,@c INT,@foreign INT,@epoch UNIQUEIDENTIFIER=NEWID();
    INSERT dbo.RunMetadata(RunName,SourceDatabaseName,SourceServerName,StartDateTime,EndDateTime,RunStatus)
    VALUES(N'Analytics baseline',N'fixture',N'fixture','2026-01-01T00:00:00','2026-01-01T01:00:00',N'Completed');
    SET @b=SCOPE_IDENTITY();
    INSERT dbo.RunMetadata(RunName,SourceDatabaseName,SourceServerName,StartDateTime,EndDateTime,RunStatus)
    VALUES(N'Analytics candidate',N'fixture',N'fixture','2026-01-02T00:00:00','2026-01-02T02:00:00',N'Completed');
    SET @c=SCOPE_IDENTITY();
    INSERT dbo.RunMetadata(RunName,SourceDatabaseName,SourceServerName,StartDateTime,EndDateTime,RunStatus)
    VALUES(N'Foreign source',N'fixture',N'other-server','2026-01-03','2026-01-04',N'Completed');
    SET @foreign=SCOPE_IDENTITY();
    INSERT dbo.RunAnalysisContext(RunID,Classification,ExperimentName,WorkloadName,Variant,QueryStoreEpoch)
    VALUES(@b,N'Load test',N'fixture',N'probe',N'baseline',@epoch),(@c,N'Load test',N'fixture',N'probe',N'regressed',@epoch);
    INSERT dbo.query_store_runtime_stats_interval(RunID,runtime_stats_interval_id,start_time,end_time)
    VALUES(@b,1,'2026-01-01T00:00:00+00:00','2026-01-01T01:00:00+00:00'),
          (@c,1,'2026-01-02T00:00:00+00:00','2026-01-02T02:00:00+00:00');
    DECLARE @fixture TABLE(RunID INT,query_id BIGINT,plan_id BIGINT,n INT,duration FLOAT,cpu FLOAT,hash BINARY(8));
    INSERT @fixture VALUES
        (@b,1,11,10,1000,500,0x0000000000000001),(@c,1,12,20,2000,1000,0x0000000000000002),
        (@b,2,21,10,1000,500,0x0000000000000001),(@c,2,22,40,1000,500,0x0000000000000001),
        (@c,3,31,10,1000,500,0x0000000000000001),(@b,4,41,10,1000,500,0x0000000000000001),
        (@b,5,51,10,1000,500,0x0000000000000001),(@c,5,52,10,2000,500,0x0000000000000001),
        (@b,6,61,10,0,0,0x0000000000000001),(@c,6,62,10,1000,500,0x0000000000000001);
    INSERT dbo.query_store_query_text(RunID,query_text_id,query_sql_text,is_part_of_encrypted_module,has_restricted_text)
    SELECT RunID,query_id,CONCAT(N'SELECT ',query_id),0,0 FROM @fixture;
    INSERT dbo.query_store_query(RunID,query_id,query_text_id,context_settings_id,query_hash,is_internal_query,query_parameterization_type,initial_compile_start_time)
    SELECT RunID,query_id,query_id,1,CONVERT(BINARY(8),query_id),0,0,'2025-01-01T00:00:00+00:00' FROM @fixture;
    -- A reused query ID with different context must not be presented as a regression.
    UPDATE dbo.query_store_query SET context_settings_id=2 WHERE RunID=@c AND query_id=5;
    INSERT dbo.query_store_plan(RunID,plan_id,query_id,compatibility_level,query_plan_hash,
        is_online_index_plan,is_trivial_plan,is_parallel_plan,is_forced_plan,is_natively_compiled,
        force_failure_count,last_force_failure_reason,initial_compile_start_time)
    SELECT RunID,plan_id,query_id,150,hash,0,0,0,0,0,0,0,'2025-01-01T00:00:00+00:00' FROM @fixture;
    INSERT dbo.query_store_runtime_stats_canonical(RunID,plan_id,runtime_stats_interval_id,execution_type,
        execution_type_desc,contributor_count,replica_count,first_execution_time,last_execution_time,count_executions,
        avg_duration,max_duration,avg_cpu_time,avg_logical_io_reads,last_value_ambiguous,stdev_aggregation_status,observation_state)
    SELECT f.RunID,f.plan_id,1,0,N'Regular',1,0,i.start_time,i.end_time,f.n,f.duration,CONVERT(BIGINT,f.duration),f.cpu,100,
        0,N'NATIVE_SINGLE_CONTRIBUTOR',N'COMPLETED'
    FROM @fixture AS f INNER JOIN dbo.query_store_runtime_stats_interval AS i ON i.RunID=f.RunID AND i.runtime_stats_interval_id=1;
    INSERT dbo.query_store_wait_stats_canonical(RunID,plan_id,runtime_stats_interval_id,execution_type,wait_category,
        wait_category_desc,contributor_count,replica_count,total_query_wait_time_ms,last_value_ambiguous,stdev_aggregation_status,observation_state)
    VALUES(@b,11,1,0,1,N'CPU',1,0,100,0,N'NATIVE_SINGLE_CONTRIBUTOR',N'COMPLETED'),
          (@c,12,1,0,1,N'CPU',1,0,400,0,N'NATIVE_SINGLE_CONTRIBUTOR',N'COMPLETED'),
          (@c,12,1,0,2,N'Worker Thread',1,0,200,0,N'NATIVE_SINGLE_CONTRIBUTOR',N'COMPLETED');
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRunQuality(@b,@c) WHERE comparison_state=N'READY' AND unequal_windows=1 AND identity_confidence=N'OPERATOR_CONFIRMED_EPOCH')
        THROW 51220,'Valid pair or unequal windows were not recognized.',1;
    IF (SELECT COUNT(*) FROM qv_report.fn_CompareRuns(@b,@c))<>6 THROW 51221,'Full query membership was not preserved.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c) WHERE query_id=1 AND match_state=N'MATCHED'
        AND ABS(avg_duration_delta_pct-100)<0.01 AND ABS(estimated_extra_duration_ms-20)<0.01
        AND ABS(baseline_executions_per_second-candidate_executions_per_second)<0.00001 AND plan_inventory_changed=1)
        THROW 51222,'Latency, impact, plan-set or normalized rate calculation failed.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c) WHERE query_id=2 AND ABS(avg_duration_delta_pct)<0.01
        AND total_duration_delta_ms>0 AND plan_inventory_changed=0)
        THROW 51223,'Frequency-only increase was incorrectly treated as slower latency or plan change.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c) WHERE query_id=3 AND match_state=N'NEW' AND baseline_executions IS NULL AND avg_duration_delta_pct IS NULL)
        THROW 51224,'New-query semantics failed.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c) WHERE query_id=4 AND match_state=N'NOT_OBSERVED' AND candidate_executions IS NULL)
        THROW 51225,'Absent-query semantics failed.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c) WHERE query_id=5 AND match_state=N'IDENTITY_CHANGED' AND avg_duration_delta_pct IS NULL)
        THROW 51226,'Query identity safeguard failed.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c) WHERE query_id=6 AND avg_duration_delta_pct IS NULL)
        THROW 51227,'Zero baseline must have undefined percentage.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareWaits(@b,@c) WHERE wait_category=2 AND baseline_wait_ms IS NULL AND observation_state=N'NO_BASELINE_OBSERVATION')
        THROW 51228,'Missing wait category was fabricated as zero.',1;
    IF EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@b)) OR EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@foreign))
        OR EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,-1)) THROW 51229,'Invalid pair was accepted.',1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareQueryWaits(@b,@c) WHERE query_id=1 AND wait_category=1 AND ABS(wait_per_execution_delta_ms-10)<0.01)
        THROW 51236,'Query-attributed wait intensity failed.',1;
    UPDATE dbo.query_store_query_text SET has_restricted_text=1 WHERE RunID=@c AND query_text_id=1;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c) WHERE query_id=1 AND match_state=N'IDENTITY_UNVERIFIED' AND avg_duration_delta_pct IS NULL)
        THROW 51237,'Restricted text identity was accepted.',1;
    UPDATE dbo.query_store_query_text SET has_restricted_text=0 WHERE RunID=@c AND query_text_id=1;
    UPDATE dbo.RunAnalysisContext SET QueryStoreEpoch=NEWID() WHERE RunID=@c;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRunQuality(@b,@c) WHERE comparison_state=N'EPOCH_MISMATCH')
        THROW 51230,'Epoch boundary was ignored.',1;
    UPDATE dbo.RunAnalysisContext SET QueryStoreEpoch=@epoch WHERE RunID=@c;
    UPDATE dbo.query_store_runtime_stats_canonical SET observation_state=N'PROVISIONAL' WHERE RunID=@c;
    IF EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c)) THROW 51231,'Provisional run was accepted.',1;
    UPDATE dbo.query_store_runtime_stats_canonical SET observation_state=N'COMPLETED' WHERE RunID=@c;
    UPDATE dbo.query_store_runtime_stats_interval SET start_time='2025-12-31' WHERE RunID=@b;
    IF EXISTS(SELECT 1 FROM qv_report.fn_CompareRuns(@b,@c)) THROW 51232,'Out-of-window interval was accepted.',1;
    UPDATE dbo.query_store_runtime_stats_interval SET start_time='2026-01-01' WHERE RunID=@b;
    UPDATE dbo.RunMetadata SET StartDateTime='2026-01-01',EndDateTime='2026-01-01T02:00:00' WHERE RunID=@c;
    UPDATE dbo.query_store_runtime_stats_interval SET start_time='2026-01-01',end_time='2026-01-01T02:00:00+00:00' WHERE RunID=@c;
    IF NOT EXISTS(SELECT 1 FROM qv_report.fn_CompareRunQuality(@b,@c) WHERE comparison_state=N'OVERLAPPING_WINDOWS')
        THROW 51233,'Overlapping snapshots were accepted.',1;
    IF EXISTS(SELECT 1 FROM qv_report.fn_CompareQueryWaits(@b,@b)) THROW 51234,'Same-run query wait comparison was accepted.',1;
    DELETE dbo.RunMetadata WHERE RunID=@b;
    IF EXISTS(SELECT 1 FROM dbo.RunAnalysisContext WHERE RunID=@b) THROW 51235,'Experiment metadata did not follow run deletion.',1;
    ROLLBACK;
    SELECT N'PASS' AS result,N'Run comparison analytics deterministic assertions' AS test_name;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;

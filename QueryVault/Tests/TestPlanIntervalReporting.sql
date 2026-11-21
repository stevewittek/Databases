/*
  Read-only reconciliation for qv_report.query_plan_interval_metrics.
  Requires at least one completed archive containing canonical runtime facts.
  No source Query Store settings, plans, indexes, or archive facts are modified.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @PeriodID INT =
(
    SELECT TOP (1) pr.period_id
    FROM qv_report.periods AS pr
    INNER JOIN dbo.query_store_runtime_stats_canonical AS rs
        ON rs.RunID = pr.period_id
        AND rs.observation_state = N'COMPLETED'
    WHERE pr.period_status = N'Completed'
    ORDER BY pr.period_end_utc DESC, pr.period_id DESC
);

IF @PeriodID IS NULL
    THROW 51140, 'No completed canonical archive period is available for plan/interval reporting validation.', 1;

DECLARE @DirectExecutions DECIMAL(38,0);
DECLARE @ReportedExecutions DECIMAL(38,0);
DECLARE @DirectCpu DECIMAL(38,4);
DECLARE @ReportedCpu DECIMAL(38,4);
DECLARE @DirectDuration DECIMAL(38,4);
DECLARE @ReportedDuration DECIMAL(38,4);
DECLARE @DirectReads DECIMAL(38,4);
DECLARE @ReportedReads DECIMAL(38,4);

SELECT
    @DirectExecutions = SUM(rs.count_executions),
    @DirectCpu = SUM(CONVERT(DECIMAL(38,4), rs.avg_cpu_time) * rs.count_executions) / 1000.0,
    @DirectDuration = SUM(CONVERT(DECIMAL(38,4), rs.avg_duration) * rs.count_executions) / 1000.0,
    @DirectReads = SUM(CONVERT(DECIMAL(38,4), rs.avg_logical_io_reads) * rs.count_executions)
FROM dbo.query_store_runtime_stats_canonical AS rs
WHERE rs.RunID = @PeriodID
    AND rs.observation_state = N'COMPLETED';

SELECT
    @ReportedExecutions = SUM(qm.execution_count),
    @ReportedCpu = SUM(qm.total_cpu_ms),
    @ReportedDuration = SUM(qm.total_duration_ms),
    @ReportedReads = SUM(qm.total_logical_reads)
FROM qv_report.query_plan_interval_metrics AS qm
WHERE qm.period_id = @PeriodID;

IF COALESCE(@DirectExecutions, -1) <> COALESCE(@ReportedExecutions, -1)
    THROW 51141, 'Query plan/interval reporting lost or duplicated canonical executions.', 1;

IF ABS(COALESCE(@DirectCpu, 0) - COALESCE(@ReportedCpu, 0)) > 0.01
    OR ABS(COALESCE(@DirectDuration, 0) - COALESCE(@ReportedDuration, 0)) > 0.01
    OR ABS(COALESCE(@DirectReads, 0) - COALESCE(@ReportedReads, 0)) > 0.01
    THROW 51142, 'Query plan/interval reported CPU, duration, or reads do not reconcile.', 1;

IF EXISTS
(
    SELECT 1
    FROM qv_report.query_plan_interval_metrics AS qm
    WHERE qm.period_id = @PeriodID
        AND qm.baseline_eligible = 1
        AND (qm.evidence_quality <> N'COMPLETE_INTERVAL'
             OR qm.runtime_observation_state <> N'COMPLETED')
)
    THROW 51143, 'The query plan/interval report accepted incomplete observations as a baseline.', 1;

SELECT
    N'PASS' AS result,
    @PeriodID AS validated_period_id,
    @ReportedExecutions AS validated_executions,
    @ReportedCpu AS validated_cpu_ms,
    @ReportedDuration AS validated_duration_ms,
    @ReportedReads AS validated_logical_reads;

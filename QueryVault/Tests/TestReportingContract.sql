/* Read-only smoke and reconciliation checks for the qv_report public API. */

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @PeriodID int =
(
	SELECT TOP (1) period_id
	FROM qv_report.periods
	WHERE period_status = N'Completed'
		AND EXISTS
		(
			SELECT 1
			FROM qv_report.query_period_metrics AS qm
			WHERE qm.period_id = qv_report.periods.period_id
		)
	ORDER BY period_end_utc DESC, period_id DESC
);

IF @PeriodID IS NULL
	THROW 51110, 'No completed archived period is available for reporting validation.', 1;

DECLARE @ReportExecutions decimal(38,4), @DirectExecutions decimal(38,4);
DECLARE @ReportCpu decimal(38,4), @DirectCpu decimal(38,4);
DECLARE @ReportDuration decimal(38,4), @DirectDuration decimal(38,4);
DECLARE @ReportReads decimal(38,4), @DirectReads decimal(38,4);
DECLARE @ReportWait decimal(38,4), @DirectWait decimal(38,4);

SELECT
	@ReportExecutions = execution_count,
	@ReportCpu = total_cpu_ms,
	@ReportDuration = total_duration_ms,
	@ReportReads = total_logical_reads
FROM qv_report.period_metrics
WHERE period_id = @PeriodID;

;WITH runtime_observation AS
(
	SELECT RunID, count_executions, avg_cpu_time, avg_duration, avg_logical_io_reads
	FROM dbo.query_store_runtime_stats_canonical
	WHERE RunID = @PeriodID

	UNION ALL

	SELECT RunID, CONVERT(decimal(38,0), count_executions),
		avg_cpu_time, avg_duration, avg_logical_io_reads
	FROM dbo.query_store_runtime_stats AS legacy
	WHERE RunID = @PeriodID
		AND NOT EXISTS
		(
			SELECT 1
			FROM dbo.query_store_runtime_stats_canonical AS canonical
			WHERE canonical.RunID = legacy.RunID
		)
)
SELECT
	@DirectExecutions = SUM(CONVERT(decimal(38,4), count_executions)),
	@DirectCpu = SUM(CONVERT(decimal(38,4), avg_cpu_time) * count_executions) / 1000.0,
	@DirectDuration = SUM(CONVERT(decimal(38,4), avg_duration) * count_executions) / 1000.0,
	@DirectReads = SUM(CONVERT(decimal(38,4), avg_logical_io_reads) * count_executions)
FROM runtime_observation;

IF ABS(COALESCE(@ReportExecutions, 0) - COALESCE(@DirectExecutions, 0)) > 0.0001
	OR ABS(COALESCE(@ReportCpu, 0) - COALESCE(@DirectCpu, 0)) > 0.0001
	OR ABS(COALESCE(@ReportDuration, 0) - COALESCE(@DirectDuration, 0)) > 0.0001
	OR ABS(COALESCE(@ReportReads, 0) - COALESCE(@DirectReads, 0)) > 0.0001
	THROW 51111, 'qv_report period metric reconciliation failed.', 1;

SELECT @ReportWait = SUM(total_wait_ms)
FROM qv_report.wait_period_metrics
WHERE period_id = @PeriodID;

;WITH wait_observation AS
(
	SELECT RunID, total_query_wait_time_ms
	FROM dbo.query_store_wait_stats_canonical
	WHERE RunID = @PeriodID

	UNION ALL

	SELECT RunID, CONVERT(decimal(38,0), total_query_wait_time_ms)
	FROM dbo.query_store_wait_stats AS legacy
	WHERE RunID = @PeriodID
		AND NOT EXISTS
		(
			SELECT 1
			FROM dbo.query_store_wait_stats_canonical AS canonical
			WHERE canonical.RunID = legacy.RunID
		)
)
SELECT @DirectWait = SUM(CONVERT(decimal(38,4), total_query_wait_time_ms))
FROM wait_observation;

IF ABS(COALESCE(@ReportWait, 0) - COALESCE(@DirectWait, 0)) > 0.0001
	THROW 51112, 'qv_report wait metric reconciliation failed.', 1;

DECLARE @TopQueryID BIGINT =
(
	SELECT TOP (1) query_id
	FROM qv_report.query_period_metrics
	WHERE period_id = @PeriodID
	ORDER BY total_duration_ms DESC, query_id
);

IF @TopQueryID IS NULL
	THROW 51115, 'TopQueries/QueryPerformance regression returned no archived query.', 1;

DECLARE @ComparisonPeriodID INT =
(
	SELECT TOP (1) period_id
	FROM qv_report.period_metrics
	WHERE period_id <> @PeriodID
		AND execution_count > 0
	ORDER BY period_end_utc DESC, period_id DESC
);

IF @ComparisonPeriodID IS NULL
	THROW 51116, 'PeriodComparison regression requires two nonempty archived periods.', 1;

DECLARE @ComparisonRows INT =
(
	SELECT COUNT(*)
	FROM qv_report.period_metrics AS baseline
	CROSS JOIN qv_report.period_metrics AS comparison
	WHERE baseline.period_id = @PeriodID
		AND comparison.period_id = @ComparisonPeriodID
);

IF @ComparisonRows <> 1
	THROW 51117, 'PeriodComparison regression did not resolve one period pair.', 1;

IF EXISTS
(
	SELECT 1
	FROM dbo.query_store_plan AS p
	WHERE p.RunID = @PeriodID
		AND p.query_plan IS NOT NULL
		AND TRY_CONVERT(xml, p.query_plan) IS NULL
)
	THROW 51113, 'An archived plan cannot be converted to native Showplan XML.', 1;

DECLARE @Showplan xml =
(
	SELECT TOP (1) showplan_xml
	FROM qv_report.query_plans
	WHERE period_id = @PeriodID
		AND showplan_xml IS NOT NULL
	ORDER BY plan_id
);

IF @Showplan IS NOT NULL
	AND @Showplan.exist('declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/showplan"; /ShowPlanXML') <> 1
	THROW 51114, 'Reporting API returned XML that is not native SQL Server Showplan XML.', 1;

DECLARE @PlanID BIGINT =
(
	SELECT TOP (1) plan_id
	FROM qv_report.query_plans
	WHERE period_id = @PeriodID
	ORDER BY plan_id
);

IF @PlanID IS NOT NULL
	EXEC qv_report.usp_GetShowplanXml @PeriodID = @PeriodID, @PlanID = @PlanID;

SELECT
	N'PASS' AS result,
	@PeriodID AS validated_period_id,
	@ReportExecutions AS execution_count,
	@ReportCpu AS total_cpu_ms,
	@ReportDuration AS total_duration_ms,
	@ReportReads AS total_logical_reads,
	@ReportWait AS total_wait_ms,
	@TopQueryID AS top_query_id,
	@ComparisonPeriodID AS comparison_period_id,
	CASE WHEN @Showplan IS NULL THEN N'No plan in selected period' ELSE N'Native Showplan XML validated' END AS showplan_result;

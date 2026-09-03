/* Read-only smoke and reconciliation checks for the qv_report public API. */

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @PeriodID int =
(
	SELECT TOP (1) period_id
	FROM qv_report.periods
	WHERE period_status = N'Completed'
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

SELECT
	@DirectExecutions = SUM(CONVERT(decimal(38,4), count_executions)),
	@DirectCpu = SUM(CONVERT(decimal(38,4), avg_cpu_time) * count_executions) / 1000.0,
	@DirectDuration = SUM(CONVERT(decimal(38,4), avg_duration) * count_executions) / 1000.0,
	@DirectReads = SUM(CONVERT(decimal(38,4), avg_logical_io_reads) * count_executions)
FROM dbo.query_store_runtime_stats
WHERE RunID = @PeriodID;

IF ABS(COALESCE(@ReportExecutions, 0) - COALESCE(@DirectExecutions, 0)) > 0.0001
	OR ABS(COALESCE(@ReportCpu, 0) - COALESCE(@DirectCpu, 0)) > 0.0001
	OR ABS(COALESCE(@ReportDuration, 0) - COALESCE(@DirectDuration, 0)) > 0.0001
	OR ABS(COALESCE(@ReportReads, 0) - COALESCE(@DirectReads, 0)) > 0.0001
	THROW 51111, 'qv_report period metric reconciliation failed.', 1;

SELECT @ReportWait = SUM(total_wait_ms)
FROM qv_report.wait_period_metrics
WHERE period_id = @PeriodID;

SELECT @DirectWait = SUM(CONVERT(decimal(38,4), total_query_wait_time_ms))
FROM dbo.query_store_wait_stats
WHERE RunID = @PeriodID;

IF ABS(COALESCE(@ReportWait, 0) - COALESCE(@DirectWait, 0)) > 0.0001
	THROW 51112, 'qv_report wait metric reconciliation failed.', 1;

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

SELECT
	N'PASS' AS result,
	@PeriodID AS validated_period_id,
	@ReportExecutions AS execution_count,
	@ReportCpu AS total_cpu_ms,
	@ReportDuration AS total_duration_ms,
	@ReportReads AS total_logical_reads,
	@ReportWait AS total_wait_ms,
	CASE WHEN @Showplan IS NULL THEN N'No plan in selected period' ELSE N'Native Showplan XML validated' END AS showplan_result;

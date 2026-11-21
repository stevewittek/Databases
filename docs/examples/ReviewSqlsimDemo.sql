/* Read-only review of the preserved November 21, 2026 Voyager 1 demonstration.
   Connect to Voyager 1 with Windows authentication and validated encryption.
   This script does not rerun the workload, capture, pin or purge anything. */
USE [QueryVaultSqlsimArchive_20261121];
GO
SET NOCOUNT ON;
IF DB_NAME() <> N'QueryVaultSqlsimArchive_20261121'
    THROW 51980, 'Connect to the dedicated sqlsim demonstration archive.', 1;

SELECT RunID, RunName, SourceDatabaseName, StartDateTime AS PeriodStartUTC,
       EndDateTime AS PeriodEndUTC, RunStatus, DoNotDelete, ProtectionNote,
       RunStartTime AS CaptureStartUTC, RunEndTime AS CaptureEndUTC
FROM dbo.RunMetadata
WHERE RunID = 1 AND RunName = N'QV_SQLSIM_DEMO_20261121';

/* Query ID 6 identifies the actual workload statement. A text-marker search
   alone also matches inspection queries that contain that marker literal. */
SELECT period_id, query_id, execution_count, plan_count,
       total_cpu_ms, total_duration_ms, total_logical_reads,
       avg_cpu_ms, avg_duration_ms, avg_logical_reads, query_text_preview
FROM qv_report.query_period_metrics
WHERE period_id = 1 AND query_id = 6
  AND source_database_name = N'QueryVaultSqlsimSource_20261121';

SELECT period_id, period_status, observation_state, is_protected,
       period_start_utc, period_end_utc
FROM qv_report.periods
WHERE period_id = 1;

/* Optional, also read-only: retrieve the saved plan XML in SSMS.
EXEC qv_report.usp_GetShowplanXml @PeriodID = 1, @QueryID = 6;
*/

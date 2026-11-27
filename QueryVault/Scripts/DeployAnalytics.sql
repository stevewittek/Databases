/* SQLCMD mode, run from QueryVault/Scripts in the intended archive database.
   Additive upgrade only. Caller sets database explicitly with sqlcmd -d.
   Existing QueryVault reporting contract must already exist. */
:on error exit
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() IN (N'master',N'model',N'msdb',N'tempdb')
    THROW 51200, 'Select the intended QueryVault archive database.', 1;
IF OBJECT_ID(N'dbo.RunMetadata', N'U') IS NULL OR OBJECT_ID(N'qv_report.query_period_metrics',N'V') IS NULL
    THROW 51201, 'Deploy the existing QueryVault reporting contract first.', 1;
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'dbo.RunAnalysisContext',N'U') IS NULL
BEGIN
CREATE TABLE dbo.RunAnalysisContext
(
    RunID INT NOT NULL,
    Classification NVARCHAR(100) NOT NULL,
    ExperimentName NVARCHAR(200) NULL,
    WorkloadName NVARCHAR(200) NULL,
    Variant NVARCHAR(100) NULL,
    DeploymentLabel NVARCHAR(200) NULL,
    QueryStoreEpoch UNIQUEIDENTIFIER NULL,
    Notes NVARCHAR(2000) NULL,
    UpdatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_RunAnalysisContext_UpdatedUtc DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_RunAnalysisContext PRIMARY KEY CLUSTERED (RunID),
    CONSTRAINT FK_RunAnalysisContext_Run FOREIGN KEY (RunID) REFERENCES dbo.RunMetadata(RunID) ON DELETE CASCADE,
    CONSTRAINT CK_RunAnalysisContext_Classification CHECK
        (Classification IN (N'Baseline', N'Deployment', N'Load test', N'Incident', N'Ad hoc'))
);
END;
GO
:r ../Views/qv_report.periods.sql
:r ../Views/qv_report.run_quality.sql
:r ../Views/qv_report.query_identity.sql
:r ../Views/qv_report.query_interval_metrics.sql
:r ../Functions/qv_report.fn_CompareRunQuality.sql
:r ../Functions/qv_report.fn_CompareRuns.sql
:r ../Functions/qv_report.fn_CompareWaits.sql
:r ../Functions/qv_report.fn_CompareQueryWaits.sql
GO
COMMIT;
GO

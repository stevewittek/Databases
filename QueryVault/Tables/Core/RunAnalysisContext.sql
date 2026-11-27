/* Optional experiment metadata. RunID remains the sole archive identity.
   QueryStoreEpoch is an operator-managed reset/restore boundary, not auto-detected. */
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
GO

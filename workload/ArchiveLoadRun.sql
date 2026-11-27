/* Same-instance lab capture recipe. Run in the intended QueryVault archive database.
   Fill server-clock boundaries from the experiment log, after the load has stopped.
   Requires a configured QueryVaultLoadLab source and deployed analytics schema. */
SET XACT_ABORT ON;
DECLARE @ServerStartUtc DATETIME2(7)=NULL, @ServerEndUtc DATETIME2(7)=NULL;
DECLARE @Experiment NVARCHAR(200)=N'predicate-lab-01', @Scenario NVARCHAR(100)=N'predicate', @Variant NVARCHAR(100)=N'baseline';
DECLARE @Epoch UNIQUEIDENTIFIER=NULL; -- Same value for both variants; rotate after Query Store reset/restore.
IF @ServerStartUtc IS NULL OR @ServerEndUtc IS NULL OR @Epoch IS NULL
    THROW 51250,'Set measured SQL server UTC boundaries and the Query Store lifetime epoch.',1;
IF @Scenario NOT IN (N'predicate',N'sort') THROW 51258,'Unknown scenario.',1;
IF @Variant NOT IN (N'baseline',N'regressed') THROW 51251,'Unknown variant.',1;
IF DB_NAME() IN (N'master',N'model',N'msdb',N'tempdb',N'QueryVaultLoadLab')
    THROW 51252,'Select the intended QueryVault archive database.',1;
DECLARE @CaptureStart DATETIME2(7)=DATEADD(MINUTE,DATEDIFF(MINUTE,CONVERT(DATETIME2,'20000101'),@ServerStartUtc)+1,CONVERT(DATETIME2,'20000101'));
DECLARE @CaptureEnd DATETIME2(7)=DATEADD(MINUTE,DATEDIFF(MINUTE,CONVERT(DATETIME2,'20000101'),@ServerEndUtc),CONVERT(DATETIME2,'20000101'));
IF @CaptureEnd<=@CaptureStart THROW 51253,'Run longer to obtain a fully contained one-minute interval.',1;
DECLARE @FlushSeconds INT=(SELECT flush_interval_seconds FROM QueryVaultLoadLab.sys.database_query_store_options);
IF @FlushSeconds IS NULL OR @CaptureEnd>DATEADD(SECOND,-@FlushSeconds,SYSUTCDATETIME())
    THROW 51254,'Wait for Query Store flush grace before archiving.',1;
-- Session lock avoids overlapping lab captures through this recipe without wrapping the archiver in a transaction.
DECLARE @LockResult INT;
EXEC @LockResult=sys.sp_getapplock @Resource=N'QueryVaultLoadLab:archive',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
IF @LockResult<0 THROW 51255,'Another lab capture is running.',1;
BEGIN TRY
    IF EXISTS(SELECT 1 FROM dbo.RunMetadata WHERE SourceDatabaseName=N'QueryVaultLoadLab' AND SourceServerName=@@SERVERNAME
        AND RunStatus=N'Completed' AND StartDateTime<@CaptureEnd AND EndDateTime>@CaptureStart)
        THROW 51256,'A completed lab archive overlaps this window; inspect existing runs.',1;
    DECLARE @Name NVARCHAR(255)=CONCAT(@Experiment,N' / ',@Variant,N' / ',CONVERT(NVARCHAR(19),@CaptureStart,126));
    EXEC dbo.usp_ArchiveQueryStore @SourceDatabaseName=N'QueryVaultLoadLab',@RunName=@Name,
        @StartDateTime=@CaptureStart,@EndDateTime=@CaptureEnd,@DoNotDelete=1;
    DECLARE @RunID INT;
    IF (SELECT COUNT(*) FROM dbo.RunMetadata WHERE RunName=@Name AND SourceDatabaseName=N'QueryVaultLoadLab'
        AND SourceServerName=@@SERVERNAME AND StartDateTime=@CaptureStart AND EndDateTime=@CaptureEnd AND RunStatus=N'Completed')<>1
        THROW 51257,'Capture did not produce exactly one completed run; inspect archive metadata.',1;
    SELECT @RunID=RunID FROM dbo.RunMetadata WHERE RunName=@Name AND SourceDatabaseName=N'QueryVaultLoadLab'
        AND SourceServerName=@@SERVERNAME AND StartDateTime=@CaptureStart AND EndDateTime=@CaptureEnd AND RunStatus=N'Completed';
    INSERT dbo.RunAnalysisContext(RunID,Classification,ExperimentName,WorkloadName,Variant,QueryStoreEpoch)
    VALUES(@RunID,N'Load test',@Experiment,@Scenario,@Variant,@Epoch);
    EXEC sys.sp_releaseapplock @Resource=N'QueryVaultLoadLab:archive',@LockOwner=N'Session';
    SELECT * FROM qv_report.run_quality WHERE period_id=@RunID;
END TRY
BEGIN CATCH
    EXEC sys.sp_releaseapplock @Resource=N'QueryVaultLoadLab:archive',@LockOwner=N'Session';
    THROW;
END CATCH;

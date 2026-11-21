/*
    Disposable SQL lab only. Requires QueryVaultLabSource with Query Store enabled
    and the updated archive procedure already installed. The collector owns its
    transaction, so this test intentionally persists three empty historical runs;
    remove the disposable database/container after the complete suite.
    Capturing an empty historical interval still executes the real collector.
*/
:on error exit
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_ID(N'QueryVaultLabSource') IS NULL
    THROW 51530, 'Create the disposable QueryVaultLabSource fixture first.', 1;
IF @@TRANCOUNT<>0
    THROW 51531, 'Retention capture test requires no ambient transaction.', 1;

EXEC dbo.usp_InitializeDatabase
    @DatabaseName=N'QueryVaultLabSource',
    @ServerName=@@SERVERNAME,
    @DefaultDaysToArchive=1,
    @DefaultRetentionDays=30,
    @AutoDeleteEnabled=0;

DECLARE @Tag nvarchar(36)=CONVERT(nvarchar(36), NEWID());
DECLARE @RunName nvarchar(255)=N'__RetentionPeriodExpiry_'+@Tag;
DECLARE @PinnedName nvarchar(255)=N'__RetentionPinned_'+@Tag;
DECLARE @DefaultName nvarchar(255)=N'__RetentionDefault_'+@Tag;
DECLARE @RunID int;
DECLARE @PinnedRunID int;
DECLARE @DefaultRunID int;

EXEC dbo.usp_ArchiveQueryStore
    @SourceDatabaseName=N'QueryVaultLabSource', @RunName=@RunName,
    @StartDateTime='2000-01-01', @EndDateTime='2000-01-02', @RetentionDays=30;
SELECT @RunID=RunID FROM dbo.RunMetadata WHERE RunName=@RunName;
IF @RunID IS NULL OR NOT EXISTS
(
    SELECT 1 FROM dbo.RunMetadata
    WHERE RunID=@RunID AND RunStatus=N'Completed'
      AND EndDateTime='2000-01-02'
      AND RetentionDate=DATEADD(DAY,30,EndDateTime)
      AND RetentionDate='2000-02-01'
      AND DoNotDelete=0
)
    THROW 51532, 'Historical capture expiry was not anchored to the captured period end.', 1;

EXEC dbo.usp_ArchiveQueryStore
    @SourceDatabaseName=N'QueryVaultLabSource', @RunName=@PinnedName,
    @StartDateTime='2000-01-01', @EndDateTime='2000-01-02',
    @RetentionDays=30, @DoNotDelete=1;
SELECT @PinnedRunID=RunID FROM dbo.RunMetadata WHERE RunName=@PinnedName;
IF @PinnedRunID IS NULL OR NOT EXISTS
(
    SELECT 1 FROM dbo.RunMetadata
    WHERE RunID=@PinnedRunID AND RunStatus=N'Completed'
      AND DoNotDelete=1 AND RetentionDate=DATEADD(DAY,30,EndDateTime)
)
    THROW 51533, 'Pinned capture lost protection or its original policy expiry.', 1;

EXEC dbo.usp_SetRunProtection @RunID=@PinnedRunID, @DoNotDelete=0,
    @Note=N'Disposable test: restore the original period expiry';
IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@PinnedRunID
                AND DoNotDelete=0 AND RetentionDate='2000-02-01')
    THROW 51537, 'Explicit unpin did not preserve the original period expiry.', 1;
EXEC dbo.usp_SetRunProtection @RunID=@PinnedRunID, @DoNotDelete=1,
    @Note=N'Disposable test: preserve the historical benchmark';

-- NULL parameter selects the configured value, and must use the same anchor.
EXEC dbo.usp_ArchiveQueryStore
    @SourceDatabaseName=N'QueryVaultLabSource', @RunName=@DefaultName,
    @StartDateTime='2000-01-02', @EndDateTime='2000-01-03', @RetentionDays=NULL;
SELECT @DefaultRunID=RunID FROM dbo.RunMetadata WHERE RunName=@DefaultName;
IF @DefaultRunID IS NULL OR NOT EXISTS
(
    SELECT 1 FROM dbo.RunMetadata
    WHERE RunID=@DefaultRunID AND RunStatus=N'Completed'
      AND RetentionDate=DATEADD(DAY,30,EndDateTime)
)
    THROW 51534, 'Configured default retention used a different date anchor.', 1;

DECLARE @Invalid TABLE (Days int NOT NULL);
INSERT @Invalid VALUES (0),(-1),(2147483647);
DECLARE @Days int;
DECLARE @Before bigint;
DECLARE @Rejected bit;
DECLARE @InvalidName nvarchar(255)=N'__RetentionInvalid_'+@Tag;
DECLARE invalid_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT Days FROM @Invalid;
OPEN invalid_cursor;
FETCH NEXT FROM invalid_cursor INTO @Days;
WHILE @@FETCH_STATUS=0
BEGIN
    SELECT @Before=COUNT_BIG(*) FROM dbo.RunMetadata;
    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_ArchiveQueryStore
            @SourceDatabaseName=N'QueryVaultLabSource', @RunName=@InvalidName,
            @StartDateTime='2000-01-01', @EndDateTime='2000-01-02', @RetentionDays=@Days;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE N'%RetentionDays must be positive and fit after the captured period end.%'
            THROW;
        SET @Rejected=1;
    END CATCH;
    IF @Rejected=0 OR (SELECT COUNT_BIG(*) FROM dbo.RunMetadata)<>@Before
        THROW 51535, 'Invalid retention was accepted or created run metadata.', 1;
    FETCH NEXT FROM invalid_cursor INTO @Days;
END;
CLOSE invalid_cursor;
DEALLOCATE invalid_cursor;

IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID AND RetentionDate='2000-02-01')
    OR NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@PinnedRunID AND DoNotDelete=1 AND RetentionDate=DATEADD(DAY,30,EndDateTime))
    THROW 51536, 'Later captures or invalid inputs changed existing retention/protection.', 1;

SELECT N'PASS' AS TestResult, @RunID AS PeriodAnchoredRunID, @PinnedRunID AS ProtectedRunID,
       @DefaultRunID AS ConfiguredDefaultRunID;

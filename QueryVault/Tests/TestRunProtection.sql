/*
    Disposable-lab-only test. The procedure owns its transaction, so fixtures
    are cleaned up explicitly rather than hidden inside a caller transaction.
    No archive facts or partition boundaries are created by this test.
*/
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @RunID INT;
DECLARE @NullExpiryRunID INT;
DECLARE @MissingRunID INT;
DECLARE @Rejected BIT;
DECLARE @Whitespace NVARCHAR(MAX) = N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13);
DECLARE @LongNote NVARCHAR(MAX) = REPLICATE(CONVERT(NVARCHAR(MAX), N'x'), 1001);

BEGIN TRY
    INSERT dbo.RunMetadata
        (RunName, SourceDatabaseName, StartDateTime, EndDateTime,
         RunStatus, DoNotDelete, RetentionDate, Comments)
    VALUES
        (N'__RunProtectionTest', N'__RunProtectionTest', '2026-01-01', '2026-01-02',
         N'Completed', 0, '2026-02-01', N'Existing capture evidence');
    SET @RunID = SCOPE_IDENTITY();
    INSERT dbo.RunMetadata
        (RunName, SourceDatabaseName, StartDateTime, EndDateTime,
         RunStatus, DoNotDelete, RetentionDate, Comments)
    VALUES
        (N'__RunProtectionNullExpiry', N'__RunProtectionTest', '2026-01-02', '2026-01-03',
         N'Completed', 1, NULL, N'Original permanent period');
    SET @NullExpiryRunID = SCOPE_IDENTITY();

    EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=1,
        @Note=N'Keep this period for the incident comparison';
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID AND DoNotDelete=1
        AND ProtectionNote=N'Keep this period for the incident comparison'
        AND RetentionDate='2026-02-01' AND Comments=N'Existing capture evidence')
        THROW 51700, 'Pin did not atomically preserve the flag, note, expiry and existing evidence.', 1;

    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=0;
    END TRY BEGIN CATCH IF ERROR_NUMBER()=201 SET @Rejected=1 ELSE THROW; END CATCH;
    IF @Rejected=0 THROW 51701, 'Missing note parameter was accepted.', 1;

    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=0, @Note=NULL;
    END TRY BEGIN CATCH IF ERROR_NUMBER()=51602 SET @Rejected=1 ELSE THROW; END CATCH;
    IF @Rejected=0 THROW 51702, 'Null note was accepted.', 1;

    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=0, @Note=@Whitespace;
    END TRY BEGIN CATCH IF ERROR_NUMBER()=51602 SET @Rejected=1 ELSE THROW; END CATCH;
    IF @Rejected=0 THROW 51703, 'Whitespace-only note was accepted.', 1;

    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=0, @Note=@LongNote;
    END TRY BEGIN CATCH IF ERROR_NUMBER()=51603 SET @Rejected=1 ELSE THROW; END CATCH;
    IF @Rejected=0 THROW 51704, 'Oversized note was silently truncated.', 1;

    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=NULL, @Note=N'Invalid flag';
    END TRY BEGIN CATCH IF ERROR_NUMBER()=51601 SET @Rejected=1 ELSE THROW; END CATCH;
    IF @Rejected=0 THROW 51705, 'Null protection flag was accepted.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID AND DoNotDelete=1
        AND ProtectionNote=N'Keep this period for the incident comparison')
        THROW 51706, 'Rejected inputs changed run protection.', 1;

    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    UPDATE dbo.RunMetadata SET Comments=N'Caller-owned pending change' WHERE RunID=@RunID;
    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=0, @Note=N'Must not run';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER()=50000
           AND ERROR_MESSAGE()=N'Run protection must run without an ambient transaction.'
            SET @Rejected=1;
        ELSE THROW;
    END CATCH;
    IF @Rejected=0 OR @@TRANCOUNT<>1 OR XACT_STATE()<>1 OR (@@OPTIONS & 16384)<>16384
        THROW 51707, 'Ambient-transaction rejection damaged caller transaction state.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID AND DoNotDelete=1
        AND Comments=N'Caller-owned pending change'
        AND ProtectionNote=N'Keep this period for the incident comparison')
        THROW 51708, 'Ambient-transaction rejection changed or rolled back caller data.', 1;
    ROLLBACK;
    SET XACT_ABORT OFF;
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID
        AND Comments=N'Existing capture evidence')
        THROW 51709, 'Caller rollback failed to restore its own change.', 1;

    EXEC dbo.usp_SetRunProtection @RunID=@RunID, @DoNotDelete=0,
        @Note=N'Investigation complete; return to configured retention';
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID AND DoNotDelete=0
        AND RetentionDate='2026-02-01' AND Comments=N'Existing capture evidence'
        AND ProtectionNote=N'Investigation complete; return to configured retention')
        THROW 51710, 'Unpin changed expiry or discarded the supplied reason.', 1;

    EXEC dbo.usp_SetRunProtection @RunID=@NullExpiryRunID, @DoNotDelete=0,
        @Note=N'Unpin without inventing an expiry';
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@NullExpiryRunID
        AND DoNotDelete=0 AND RetentionDate IS NULL AND Comments=N'Original permanent period')
        THROW 51711, 'Unpin invented an expiry for an originally permanent run.', 1;

    SET @MissingRunID=@NullExpiryRunID;
    DELETE dbo.RunMetadata WHERE RunID=@NullExpiryRunID;
    SET @NullExpiryRunID=NULL;
    SET @Rejected=0;
    BEGIN TRY
        EXEC dbo.usp_SetRunProtection @RunID=@MissingRunID, @DoNotDelete=1, @Note=N'Missing run';
    END TRY BEGIN CATCH IF ERROR_NUMBER()=51605 SET @Rejected=1 ELSE THROW; END CATCH;
    IF @Rejected=0 OR @@TRANCOUNT<>0
        THROW 51712, 'Missing-run failure was not cleanly rejected.', 1;

    DELETE dbo.RunMetadata WHERE RunID=@RunID;
    SELECT N'PASS' AS TestResult,
        N'Pin/unpin, mandatory notes, existing evidence, expiry and caller transaction ownership' AS Validated;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    DELETE dbo.RunMetadata WHERE RunID IN (@RunID,@NullExpiryRunID);
    THROW;
END CATCH;
GO

/*
    Pin or unpin one archived period with an explicit reason.
    Preservation changes serialize with the physical partition lifecycle.
    Existing expiry and Comments are preserved; unpinning does not invent expiry.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.usp_SetRunProtection
    @RunID INT,
    @DoNotDelete BIT,
    @Note NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- Disable XACT_ABORT in this procedure's scope before raising the guard.
    -- On procedure exit SQL Server restores the caller's original SET option.
    -- This preserves a caller's committable transaction even with XACT_ABORT ON.
    IF @@TRANCOUNT <> 0
    BEGIN
        SET XACT_ABORT OFF;
        RAISERROR ('Run protection must run without an ambient transaction.', 16, 1);
        RETURN -1;
    END;

    IF @RunID IS NULL OR @RunID <= 0
        THROW 51600, 'A positive RunID is required.', 1;
    IF @DoNotDelete IS NULL
        THROW 51601, 'An explicit DoNotDelete value is required.', 1;
    IF @Note IS NULL OR LEN(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(@Note,
        NCHAR(9), N' '), NCHAR(10), N' '), NCHAR(13), N' ')))) = 0
        THROW 51602, 'A nonblank protection-change note is required.', 1;
    IF DATALENGTH(@Note) > 2000
        THROW 51603, 'Protection-change notes must fit NVARCHAR(1000).', 1;

    SET XACT_ABORT ON;
    DECLARE @LockResult INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'QueryVault.PF_RunID',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 30000;
        IF @LockResult < 0
            THROW 51604, 'Could not acquire the QueryVault partition lifecycle lock.', 1;

        UPDATE dbo.RunMetadata WITH (UPDLOCK, HOLDLOCK)
        SET DoNotDelete = @DoNotDelete,
            ProtectionNote = CONVERT(NVARCHAR(1000), @Note)
        WHERE RunID = @RunID;
        IF @@ROWCOUNT <> 1
            THROW 51605, 'RunID was not found; no protection was changed.', 1;

        COMMIT TRANSACTION;
        SELECT @RunID AS RunID, @DoNotDelete AS DoNotDelete,
               CONVERT(NVARCHAR(1000), @Note) AS ProtectionNote;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

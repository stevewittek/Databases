/*
    Transactional compilation test for the two procedures changed by the
    current safety work. The final rollback restores deployed definitions.
*/

:on error exit

USE [QueryVaultDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;
GO

:r ..\StoredProcedures\usp_ManagePartitions.sql
:r ..\StoredProcedures\usp_ArchiveQueryStore.sql
GO

BEGIN TRY
    EXEC sys.sp_refreshsqlmodule N'dbo.usp_ManagePartitions';
    EXEC sys.sp_refreshsqlmodule N'dbo.usp_ArchiveQueryStore';

    ROLLBACK TRANSACTION;
    SELECT N'PASS' AS TestResult;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

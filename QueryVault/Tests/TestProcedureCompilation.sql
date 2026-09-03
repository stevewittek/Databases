/*
    Transactional compilation test for the procedures changed by canonical
    aggregation. The final rollback restores deployed definitions and schema.
*/

:on error exit

USE [QueryVaultDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;
GO

:r ..\Scripts\MigrateRunPartitioning.sql
:r ..\Functions\ufn_EvaluatePartitionCapacity.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_canonical.sql
:r ..\Tables\QueryStore\query_store_wait_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_wait_stats_canonical.sql
:r ..\Tables\PartitionMaintenance\query_store_runtime_stats_contributor_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_runtime_stats_canonical_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_wait_stats_contributor_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_wait_stats_canonical_PartitionMaintenance.sql
:r ..\StoredProcedures\usp_ManagePartitions.sql
:r ..\StoredProcedures\usp_InitializeDatabase.sql
:r ..\StoredProcedures\usp_MaterializeCanonicalQueryStoreStats.sql
:r ..\StoredProcedures\usp_ArchiveQueryStore.sql
:r ..\StoredProcedures\usp_PurgeExpiredArchives.sql
:r ..\Views\dbo.vw_QueryVaultStorageRecommendation.sql
GO

BEGIN TRY
    EXEC sys.sp_refreshsqlmodule N'dbo.ufn_EvaluatePartitionCapacity';
    EXEC sys.sp_refreshsqlmodule N'dbo.usp_ManagePartitions';
    EXEC sys.sp_refreshsqlmodule N'dbo.usp_InitializeDatabase';
    EXEC sys.sp_refreshsqlmodule N'dbo.usp_MaterializeCanonicalQueryStoreStats';
    EXEC sys.sp_refreshsqlmodule N'dbo.usp_ArchiveQueryStore';
    EXEC sys.sp_refreshsqlmodule N'dbo.usp_PurgeExpiredArchives';
    EXEC sys.sp_refreshsqlmodule N'dbo.vw_QueryVaultStorageRecommendation';

    ROLLBACK TRANSACTION;
    SELECT N'PASS' AS TestResult;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

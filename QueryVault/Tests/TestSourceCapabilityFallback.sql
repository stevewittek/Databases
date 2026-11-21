/* Disposable lab only. Requires QueryVaultLabSource with completed runtime stats.
   Emulates a catalog without newer fields; this is NOT a real SQL 2016 test.
   Procedure definition is restored on both success and failure. Captured lab
   runs remain for review. Never run on a production archive. */
:on error exit
USE QueryVaultDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @Original nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore'));
DECLARE @AlterOriginal nvarchar(max) = REPLACE(@Original, N'CREATE PROCEDURE', N'ALTER PROCEDURE');
DECLARE @Modified nvarchar(max) = REPLACE(@AlterOriginal,
 N'INSERT INTO @SourceColumns EXEC sys.sp_executesql @SQL;',
 N'INSERT INTO @SourceColumns EXEC sys.sp_executesql @SQL;
 DELETE FROM @SourceColumns WHERE ObjectName = N''query_store_wait_stats''
 OR ColumnName IN (N''plan_forcing_type'',N''plan_forcing_type_desc'',
 N''has_compile_replay_script'',N''is_optimized_plan_forcing_disabled'',N''plan_type'',N''plan_type_desc'',
 N''is_clouddb_internal_query'',N''replica_group_id'')
 OR ColumnName LIKE N''%log_bytes_used'' OR ColumnName LIKE N''%tempdb_space_used''
 OR ColumnName LIKE N''%page_server_io_reads'' OR ColumnName LIKE N''%num_physical_io_reads'';');
IF @Modified = @AlterOriginal THROW 51980, 'Capability fixture did not modify the procedure.', 1;
BEGIN TRY
 EXEC sys.sp_executesql @Modified;
 DECLARE @End datetime2 = DATEADD(MINUTE,-2,SYSUTCDATETIME());
 EXEC dbo.usp_ArchiveQueryStore @SourceDatabaseName=N'QueryVaultLabSource',
   @RunName=N'Capability fallback fixture', @StartDateTime='2026-01-01', @EndDateTime=@End;
 DECLARE @RunID int = (SELECT MAX(RunID) FROM dbo.RunMetadata WHERE RunName=N'Capability fallback fixture');
 IF NOT EXISTS (SELECT 1 FROM dbo.query_store_plan WHERE RunID=@RunID)
   THROW 51981, 'Fixture needs archived plans.', 1;
 IF EXISTS (SELECT 1 FROM dbo.query_store_plan WHERE RunID=@RunID AND
   (plan_forcing_type IS NOT NULL OR has_compile_replay_script IS NOT NULL
   OR is_optimized_plan_forcing_disabled IS NOT NULL OR plan_type IS NOT NULL))
   THROW 51982, 'Unavailable plan features were not NULL.', 1;
 IF EXISTS (SELECT 1 FROM dbo.query_store_runtime_stats_contributor WHERE RunID=@RunID
   AND (avg_log_bytes_used IS NOT NULL OR avg_tempdb_space_used IS NOT NULL OR replica_group_id IS NOT NULL))
   THROW 51983, 'Unavailable runtime features were not NULL.', 1;
 IF EXISTS (SELECT 1 FROM dbo.query_store_wait_stats_contributor WHERE RunID=@RunID)
   THROW 51984, 'Unavailable wait view was collected.', 1;
 IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID AND RunStatus=N'Completed'
   AND JSON_VALUE(Comments,'$.wait_stats_available')=N'false')
   THROW 51985, 'Missing capability evidence.', 1;
 EXEC sys.sp_executesql @AlterOriginal;
 SELECT N'PASS' AS CapabilityFallbackTest, @RunID AS RunID;
END TRY
BEGIN CATCH
 EXEC sys.sp_executesql @AlterOriginal;
 THROW;
END CATCH;
GO

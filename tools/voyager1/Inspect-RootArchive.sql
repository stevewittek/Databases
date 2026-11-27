SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000;

DECLARE @reporting_schema_id int = SCHEMA_ID(N'qv_report');
DECLARE @partition_function_id int = (SELECT function_id FROM sys.partition_functions WHERE name=N'PF_RunID');
DECLARE @overflow_partition int = (SELECT fanout FROM sys.partition_functions WHERE function_id=@partition_function_id);

SELECT CONVERT(nvarchar(128), SERVERPROPERTY('MachineName')) AS MachineName,
       CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')) AS InstanceName,
       CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) AS MajorVersion,
       DB_NAME() AS DatabaseName,
       CONVERT(nvarchar(64), DATABASEPROPERTYEX(DB_NAME(), 'Updateability')) AS Updateability,
       CASE WHEN OBJECT_ID(N'dbo.RunMetadata', N'U') IS NOT NULL
                  AND OBJECT_ID(N'dbo.DatabaseConfig', N'U') IS NOT NULL
                  AND OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P') IS NOT NULL THEN 1 ELSE 0 END AS HasArchive,
       CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE schema_id=@reporting_schema_id
                            AND principal_id=DATABASE_PRINCIPAL_ID(N'dbo')) THEN 1 ELSE 0 END AS HasReportingSchema,
       CASE WHEN @partition_function_id IS NOT NULL AND EXISTS (SELECT 1 FROM sys.partition_schemes
                 WHERE function_id=@partition_function_id AND name=N'PS_RunID') THEN 1 ELSE 0 END AS HasRunPartitioning,
       (SELECT MAX(TRY_CONVERT(bigint, value)) FROM sys.partition_range_values
            WHERE function_id=@partition_function_id) AS MaxRunBoundary,
       (SELECT COUNT(*) FROM sys.dm_db_partition_stats AS p
            JOIN sys.indexes AS i ON i.object_id=p.object_id AND i.index_id=p.index_id
            JOIN sys.partition_schemes AS ps ON ps.data_space_id=i.data_space_id
            WHERE ps.function_id=@partition_function_id AND i.type=5
                AND p.partition_number=@overflow_partition AND p.row_count>0) AS PopulatedColumnstoreOverflowPartitions,
       (SELECT COUNT(*) FROM sys.dm_db_partition_stats AS p
            JOIN sys.indexes AS i ON i.object_id=p.object_id AND i.index_id=p.index_id
            JOIN sys.partition_schemes AS ps ON ps.data_space_id=i.data_space_id
            WHERE ps.function_id=@partition_function_id AND p.index_id IN (0,1)) AS ObservedRunPartitions;

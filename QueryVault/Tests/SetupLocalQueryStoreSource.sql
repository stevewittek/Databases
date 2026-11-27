/* Disposable Docker lab only. Refuses to overwrite an existing database.
   Wait for an interval to close and its flush delay before capturing. */
:on error exit
USE master;
GO
IF DB_ID(N'QueryVaultLabSource') IS NOT NULL
 THROW 51970, 'QueryVaultLabSource already exists; refusing overwrite.', 1;
GO
CREATE DATABASE QueryVaultLabSource;
GO
ALTER DATABASE QueryVaultLabSource SET QUERY_STORE = ON
 (OPERATION_MODE=READ_WRITE, QUERY_CAPTURE_MODE=ALL,
  INTERVAL_LENGTH_MINUTES=1, DATA_FLUSH_INTERVAL_SECONDS=60);
GO
USE QueryVaultLabSource;
GO
CREATE TABLE dbo.Workload (id int NOT NULL PRIMARY KEY, value int NOT NULL);
INSERT dbo.Workload VALUES (1,10),(2,20);
SELECT SUM(value) FROM dbo.Workload;
EXEC sys.sp_query_store_flush_db;
GO

/*
	========================================
	QueryVault Database - Master Deployment Script
	========================================

	This script deploys the complete QueryVault database solution for archiving
	SQL Server Query Store data with partitioning and automated maintenance.

	COMPONENTS:
	- Core metadata tables (RunMetadata, DatabaseConfig)
	- Partition function and scheme
	- 6 partitioned QueryStore archive tables with clustered columnstore indexes
	- 6 partition maintenance mirror tables
	- Stored procedures for archiving and partition management
	- SQL Agent job templates

	PREREQUISITES:
	- SQL Server 2016 or higher (for Query Store and columnstore support)
	- Sufficient permissions to create database, tables, and procedures
	- msdb access for SQL Agent job creation (optional)

	USAGE:
	1. Review and modify any default settings below
	2. Execute this script on your target SQL Server instance
	3. Configure databases for archiving using usp_InitializeDatabase
	4. Create SQL Agent jobs using the templates in the Jobs folder

	Author: QueryVault Team
	Date: $(Date)
	Version: 1.0
*/

SET NOCOUNT ON;
GO

-- ========================================
-- STEP 1: Create Database
-- ========================================
PRINT '========================================';
PRINT 'STEP 1: Creating QueryVaultDB Database';
PRINT '========================================';
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'QueryVaultDB')
BEGIN
	CREATE DATABASE QueryVaultDB;
	PRINT 'QueryVaultDB created successfully';
END
ELSE
BEGIN
	PRINT 'QueryVaultDB already exists';
END
GO

USE QueryVaultDB;
GO

-- ========================================
-- STEP 2: Create Partition Function
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'STEP 2: Creating Partition Function';
PRINT '========================================';
GO

:r "$(ProjectDir)Partitions\PartitionFunction.sql"
GO

-- ========================================
-- STEP 3: Create Partition Scheme
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'STEP 3: Creating Partition Scheme';
PRINT '========================================';
GO

:r "$(ProjectDir)Partitions\PartitionScheme.sql"
GO

-- ========================================
-- STEP 4: Create Core Metadata Tables
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'STEP 4: Creating Core Metadata Tables';
PRINT '========================================';
GO

:r "$(ProjectDir)Tables\Core\RunMetadata.sql"
GO

:r "$(ProjectDir)Tables\Core\DatabaseConfig.sql"
GO

-- ========================================
-- STEP 5: Create QueryStore Archive Tables
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'STEP 5: Creating QueryStore Archive Tables';
PRINT '========================================';
GO

:r "$(ProjectDir)Tables\QueryStore\query_store_query.sql"
GO

:r "$(ProjectDir)Tables\QueryStore\query_store_query_text.sql"
GO

:r "$(ProjectDir)Tables\QueryStore\query_store_plan.sql"
GO

:r "$(ProjectDir)Tables\QueryStore\query_store_runtime_stats.sql"
GO

:r "$(ProjectDir)Tables\QueryStore\query_store_runtime_stats_interval.sql"
GO

:r "$(ProjectDir)Tables\QueryStore\query_store_wait_stats.sql"
GO

-- ========================================
-- STEP 6: Create Partition Maintenance Tables
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'STEP 6: Creating Partition Maintenance Tables';
PRINT '========================================';
GO

:r "$(ProjectDir)Tables\PartitionMaintenance\query_store_query_PartitionMaintenance.sql"
GO

:r "$(ProjectDir)Tables\PartitionMaintenance\query_store_query_text_PartitionMaintenance.sql"
GO

:r "$(ProjectDir)Tables\PartitionMaintenance\query_store_plan_PartitionMaintenance.sql"
GO

:r "$(ProjectDir)Tables\PartitionMaintenance\query_store_runtime_stats_PartitionMaintenance.sql"
GO

:r "$(ProjectDir)Tables\PartitionMaintenance\query_store_runtime_stats_interval_PartitionMaintenance.sql"
GO

:r "$(ProjectDir)Tables\PartitionMaintenance\query_store_wait_stats_PartitionMaintenance.sql"
GO

-- ========================================
-- STEP 7: Create Stored Procedures
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'STEP 7: Creating Stored Procedures';
PRINT '========================================';
GO

:r "$(ProjectDir)StoredProcedures\usp_ManagePartitions.sql"
GO

:r "$(ProjectDir)StoredProcedures\usp_InitializeDatabase.sql"
GO

:r "$(ProjectDir)StoredProcedures\usp_GetArchiveSummary.sql"
GO

:r "$(ProjectDir)StoredProcedures\usp_ArchiveQueryStore.sql"
GO

:r "$(ProjectDir)StoredProcedures\usp_PurgeExpiredArchives.sql"
GO

-- ========================================
-- STEP 8: Deployment Summary
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'DEPLOYMENT SUMMARY';
PRINT '========================================';
PRINT '';

-- Count objects
DECLARE @TableCount INT;
DECLARE @ProcedureCount INT;
DECLARE @PartitionFunctionCount INT;
DECLARE @PartitionSchemeCount INT;

SELECT @TableCount = COUNT(*) FROM sys.tables WHERE SCHEMA_NAME(schema_id) = 'dbo';
SELECT @ProcedureCount = COUNT(*) FROM sys.procedures WHERE SCHEMA_NAME(schema_id) = 'dbo';
SELECT @PartitionFunctionCount = COUNT(*) FROM sys.partition_functions WHERE name = 'PF_RunID';
SELECT @PartitionSchemeCount = COUNT(*) FROM sys.partition_schemes WHERE name = 'PS_RunID';

PRINT 'Database: QueryVaultDB';
PRINT 'Tables Created: ' + CAST(@TableCount AS VARCHAR(10));
PRINT 'Stored Procedures Created: ' + CAST(@ProcedureCount AS VARCHAR(10));
PRINT 'Partition Functions: ' + CAST(@PartitionFunctionCount AS VARCHAR(10));
PRINT 'Partition Schemes: ' + CAST(@PartitionSchemeCount AS VARCHAR(10));
PRINT '';

-- List tables
PRINT 'Tables:';
SELECT '  - ' + name AS TableName FROM sys.tables WHERE SCHEMA_NAME(schema_id) = 'dbo' ORDER BY name;
PRINT '';

-- List procedures
PRINT 'Stored Procedures:';
SELECT '  - ' + name AS ProcedureName FROM sys.procedures WHERE SCHEMA_NAME(schema_id) = 'dbo' ORDER BY name;
PRINT '';

-- Partition info
PRINT 'Partition Information:';
EXEC dbo.usp_ManagePartitions @Operation = 'GetInfo';
PRINT '';

PRINT '========================================';
PRINT 'DEPLOYMENT COMPLETED SUCCESSFULLY';
PRINT '========================================';
PRINT '';
PRINT 'NEXT STEPS:';
PRINT '1. Register databases for archiving:';
PRINT '   EXEC dbo.usp_InitializeDatabase @DatabaseName = ''YourDatabaseName'';';
PRINT '';
PRINT '2. Create SQL Agent jobs:';
PRINT '   - Use Jobs\CreateArchiveJob_Template.sql for single database jobs';
PRINT '   - Use Jobs\CreateArchiveJob_AllDatabases.sql for automated multi-database archiving';
PRINT '';
PRINT '3. Test archiving:';
PRINT '   EXEC dbo.usp_ArchiveQueryStore';
PRINT '        @SourceDatabaseName = ''YourDatabaseName'',';
PRINT '        @RunName = ''Test Archive'',';
PRINT '        @DoNotDelete = 1;';
PRINT '';
PRINT '4. View archive summary:';
PRINT '   EXEC dbo.usp_GetArchiveSummary;';
PRINT '';
GO

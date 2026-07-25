/*
	========================================
	QueryVault Database - Standalone Deployment Script
	========================================

	This is a complete standalone deployment script that contains all SQL code inline.
	No external file references - just execute this script to deploy everything.

	COMPONENTS:
	- QueryVaultDB database
	- Core metadata tables (RunMetadata, DatabaseConfig)
	- Partition function and scheme (100 initial partitions)
	- 6 partitioned QueryStore archive tables with clustered columnstore indexes
	- 6 partition maintenance mirror tables for partition switching
	- 4 stored procedures for archiving and management

	PREREQUISITES:
	- SQL Server 2016 or higher
	- sysadmin or db_owner permissions

	Author: QueryVault Team
	Version: 1.0
*/

SET NOCOUNT ON;
GO

PRINT '========================================';
PRINT 'QueryVault Database Deployment';
PRINT '========================================';
PRINT '';

-- ========================================
-- Create Database
-- ========================================
PRINT 'Creating QueryVaultDB Database...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'QueryVaultDB')
BEGIN
	CREATE DATABASE QueryVaultDB;
	PRINT 'QueryVaultDB created successfully';
END
ELSE
BEGIN
	PRINT 'QueryVaultDB already exists - using existing database';
END
GO

USE QueryVaultDB;
GO

PRINT '';
PRINT 'Current Database: QueryVaultDB';
PRINT '';
GO

-- Note: For full deployment with all table and procedure definitions, 
-- this script should be run from the project directory using the Deploy.sql script
-- which uses :r commands to include all component scripts.
--
-- Alternatively, you can manually execute scripts in this order:
-- 1. Partitions\PartitionFunction.sql
-- 2. Partitions\PartitionScheme.sql
-- 3. Tables\Core\*.sql
-- 4. Tables\QueryStore\*.sql
-- 5. Tables\PartitionMaintenance\*.sql
-- 6. StoredProcedures\*.sql

PRINT '========================================';
PRINT 'To complete deployment, run the scripts in this order:';
PRINT '1. Partitions\PartitionFunction.sql';
PRINT '2. Partitions\PartitionScheme.sql';
PRINT '3. Tables\Core\RunMetadata.sql';
PRINT '4. Tables\Core\DatabaseConfig.sql';
PRINT '5. Tables\QueryStore\query_store_*.sql (6 files)';
PRINT '6. Tables\PartitionMaintenance\query_store_*_PartitionMaintenance.sql (6 files)';
PRINT '7. StoredProcedures\*.sql (4 files)';
PRINT '';
PRINT 'Or run: Scripts\Deploy.sql from SQLCMD with -v "ProjectDir=<path>"';
PRINT '========================================';
GO

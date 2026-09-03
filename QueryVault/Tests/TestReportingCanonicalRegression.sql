/*
	Transactional reporting regression over the canonical-first qv_report views.
	The additive schema and view definitions are rolled back after the existing
	period totals, query, wait, plan history, and native Showplan checks run.
*/

:on error exit

USE [QueryVaultDB];
GO

SET XACT_ABORT ON;
BEGIN TRANSACTION;
GO

IF SCHEMA_ID(N'qv_report') IS NULL
	EXEC(N'CREATE SCHEMA qv_report AUTHORIZATION dbo;');
GO

-- The local SQL 2019 test database predates SQL 2022 plan_type metadata.
-- Add the nullable compatibility column only inside this rolled-back test.
IF COL_LENGTH(N'dbo.query_store_plan', N'plan_type_desc') IS NULL
	ALTER TABLE dbo.query_store_plan ADD plan_type_desc NVARCHAR(60) NULL;
GO

:r ..\Tables\QueryStore\query_store_runtime_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_canonical.sql
:r ..\Tables\QueryStore\query_store_wait_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_wait_stats_canonical.sql
:r ..\Views\qv_report.periods.sql
:r ..\Views\qv_report.query_period_metrics.sql
:r ..\Views\qv_report.period_metrics.sql
:r ..\Views\qv_report.wait_period_metrics.sql
:r ..\Views\qv_report.query_wait_period_metrics.sql
:r ..\Views\qv_report.query_plans.sql
:r ..\StoredProcedures\qv_report.usp_GetShowplanXml.sql
:r TestReportingContract.sql
GO

ROLLBACK TRANSACTION;
GO

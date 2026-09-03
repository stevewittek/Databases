/*
	One-time DBA bootstrap for the stable reporting API.

	Run this script before DeployQueryVault.ps1. The production deployment
	identity intentionally is not allowed to impersonate dbo or create a schema
	owned by dbo. Keeping qv_report owned by dbo preserves ownership chaining so
	the Grafana reader needs no permissions on QueryVault's internal tables.
*/

:setvar QueryVaultDatabase "QueryVaultDB"

USE [$(QueryVaultDatabase)];
GO

IF SCHEMA_ID(N'qv_report') IS NULL
	EXEC(N'CREATE SCHEMA qv_report AUTHORIZATION dbo;');
GO

IF NOT EXISTS
(
	SELECT 1
	FROM sys.schemas AS s
	WHERE s.name = N'qv_report'
		AND USER_NAME(s.principal_id) = N'dbo'
)
	THROW 51022, 'qv_report exists but is not owned by dbo. Stop and have a DBA correct the schema owner.', 1;
GO

/*
	Run after a DBA creates the queryvault_grafana SQL login through the
	organization's approved secret-management process. This file never handles
	or stores the login password.
*/

:setvar QueryVaultDatabase "QueryVaultDB"
:setvar QueryVaultGrafanaLogin "queryvault_grafana"

USE [$(QueryVaultDatabase)];
GO

IF SUSER_ID(N'$(QueryVaultGrafanaLogin)') IS NULL
	THROW 51021, 'Create the QueryVault Grafana SQL login before provisioning the database user.', 1;
GO

IF USER_ID(N'$(QueryVaultGrafanaLogin)') IS NULL
	CREATE USER [$(QueryVaultGrafanaLogin)] FOR LOGIN [$(QueryVaultGrafanaLogin)];
GO

GRANT SELECT ON SCHEMA::qv_report TO [$(QueryVaultGrafanaLogin)];
GRANT EXECUTE ON OBJECT::qv_report.usp_GetShowplanXml TO [$(QueryVaultGrafanaLogin)];
GO

:on error exit

/*
  One-time provisioning for the local Voyager 2 deployment login.
  Supply QueryVaultDeployerPassword as a sqlcmd environment variable.
  The password is never stored in this file or printed.

  CREATE ANY DATABASE is required by SQL Server for RESTORE VERIFYONLY. The
  deployment scripts still require QueryVaultDB to exist and never request
  database creation in production.
*/

IF N'$(QueryVaultDeployerPassword)' = N''
   OR N'$(QueryVaultDeployerPassword)' = N'$' + N'(QueryVaultDeployerPassword)'
    THROW 51200, 'QueryVaultDeployerPassword was not supplied to sqlcmd.', 1;
GO

USE [master];
GO

IF SUSER_ID(N'queryvault_deployer') IS NULL
BEGIN
    DECLARE @CreatePassword nvarchar(256) = N'$(QueryVaultDeployerPassword)';
    DECLARE @CreateLogin nvarchar(max) =
        N'CREATE LOGIN [queryvault_deployer] WITH PASSWORD=N'''
        + REPLACE(@CreatePassword,N'''',N'''''')
        + N''', CHECK_POLICY=ON, CHECK_EXPIRATION=OFF, DEFAULT_DATABASE=[QueryVaultDB];';
    EXEC sys.sp_executesql @CreateLogin;
END;
ELSE
BEGIN
    ALTER LOGIN [queryvault_deployer] ENABLE;
    DECLARE @ExistingPassword nvarchar(256) = N'$(QueryVaultDeployerPassword)';
    DECLARE @AlterLogin nvarchar(max) =
        N'ALTER LOGIN [queryvault_deployer] WITH PASSWORD=N'''
        + REPLACE(@ExistingPassword,N'''',N'''''')
        + N''', DEFAULT_DATABASE=[QueryVaultDB], CHECK_POLICY=ON;';
    EXEC sys.sp_executesql @AlterLogin;
END;
GO

GRANT CREATE ANY DATABASE TO [queryvault_deployer];
GO

USE [QueryVaultDB];
GO

IF USER_ID(N'queryvault_deployer') IS NULL
    CREATE USER [queryvault_deployer] FOR LOGIN [queryvault_deployer];
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.database_role_members
    WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'db_datareader')
      AND member_principal_id=USER_ID(N'queryvault_deployer')
)
    ALTER ROLE [db_datareader] ADD MEMBER [queryvault_deployer];

IF NOT EXISTS
(
    SELECT 1 FROM sys.database_role_members
    WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'db_ddladmin')
      AND member_principal_id=USER_ID(N'queryvault_deployer')
)
    ALTER ROLE [db_ddladmin] ADD MEMBER [queryvault_deployer];

IF NOT EXISTS
(
    SELECT 1 FROM sys.database_role_members
    WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'db_backupoperator')
      AND member_principal_id=USER_ID(N'queryvault_deployer')
)
    ALTER ROLE [db_backupoperator] ADD MEMBER [queryvault_deployer];

GRANT VIEW DEFINITION TO [queryvault_deployer];
GRANT VIEW DATABASE PERFORMANCE STATE TO [queryvault_deployer];
GRANT ALTER ANY DATASPACE TO [queryvault_deployer];
GO

USE [msdb];
GO

IF USER_ID(N'queryvault_deployer') IS NULL
    CREATE USER [queryvault_deployer] FOR LOGIN [queryvault_deployer];
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.database_role_members
    WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'SQLAgentReaderRole')
      AND member_principal_id=USER_ID(N'queryvault_deployer')
)
    ALTER ROLE [SQLAgentReaderRole] ADD MEMBER [queryvault_deployer];

GRANT SELECT ON dbo.sysjobs TO [queryvault_deployer];
GRANT SELECT ON dbo.sysjobschedules TO [queryvault_deployer];
GRANT SELECT ON dbo.sysschedules TO [queryvault_deployer];
GO

SELECT N'queryvault_deployer' AS LoginName,N'Provisioned' AS ProvisioningStatus;
GO

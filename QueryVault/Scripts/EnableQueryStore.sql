/*
	Enable QueryStore on All Registered Databases
	This script enables QueryStore with recommended settings on all databases
	registered in the QueryVault configuration
*/

USE master;
GO

SET NOCOUNT ON;

PRINT '========================================';
PRINT 'Enabling QueryStore on All Registered Databases';
PRINT '========================================';
PRINT '';

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @SQL NVARCHAR(MAX);
DECLARE @IsEnabled BIT;
DECLARE @EnabledCount INT = 0;
DECLARE @AlreadyEnabledCount INT = 0;

-- Cursor through all registered databases
DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
	SELECT DatabaseName
	FROM QueryVaultDB.dbo.DatabaseConfig
	WHERE IsEnabled = 1
	  AND DatabaseName != 'QueryVaultDB'  -- Don't enable on QueryVaultDB itself
	ORDER BY DatabaseName;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
	-- Check if database exists and is online
	IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName AND state_desc = 'ONLINE')
	BEGIN
		-- Check if QueryStore is already enabled
		SET @SQL = N'
		USE ' + QUOTENAME(@DatabaseName) + N';
		SELECT @IsEnabledOUT = CASE 
			WHEN EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state > 0) 
			THEN 1 
			ELSE 0 
		END;';

		EXEC sp_executesql @SQL, N'@IsEnabledOUT BIT OUTPUT', @IsEnabled OUTPUT;

		IF @IsEnabled = 1
		BEGIN
			PRINT '✓ QueryStore already enabled on: ' + @DatabaseName;
			SET @AlreadyEnabledCount = @AlreadyEnabledCount + 1;
		END
		ELSE
		BEGIN
			-- Enable QueryStore with recommended settings
			BEGIN TRY
				SET @SQL = N'
				ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' 
				SET QUERY_STORE = ON
				(
					OPERATION_MODE = READ_WRITE,
					CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
					DATA_FLUSH_INTERVAL_SECONDS = 900,
					INTERVAL_LENGTH_MINUTES = 60,
					MAX_STORAGE_SIZE_MB = 1000,
					QUERY_CAPTURE_MODE = AUTO,
					SIZE_BASED_CLEANUP_MODE = AUTO,
					MAX_PLANS_PER_QUERY = 200
				);';

				EXEC sp_executesql @SQL;
				PRINT '✓ Successfully enabled QueryStore on: ' + @DatabaseName;
				SET @EnabledCount = @EnabledCount + 1;
			END TRY
			BEGIN CATCH
				PRINT '✗ Error enabling QueryStore on ' + @DatabaseName + ': ' + ERROR_MESSAGE();
			END CATCH
		END
	END
	ELSE
	BEGIN
		PRINT '⚠  Database not found or offline: ' + @DatabaseName;
	END

	PRINT '';
	FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

PRINT '========================================';
PRINT 'QueryStore Enablement Summary';
PRINT '========================================';
PRINT 'Newly enabled: ' + CAST(@EnabledCount AS VARCHAR(10));
PRINT 'Already enabled: ' + CAST(@AlreadyEnabledCount AS VARCHAR(10));
PRINT 'Total databases: ' + CAST(@EnabledCount + @AlreadyEnabledCount AS VARCHAR(10));
PRINT '';

-- Show current status
PRINT 'Current QueryStore Status:';
PRINT '';

SET @SQL = N'';

SELECT @SQL = @SQL + 
	'USE ' + QUOTENAME(DatabaseName) + '; ' +
	'SELECT ''' + DatabaseName + ''' AS DatabaseName, ' +
	'    CASE WHEN EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state > 0) THEN ''Enabled'' ELSE ''Disabled'' END AS Status, ' +
	'    (SELECT actual_state_desc FROM sys.database_query_store_options) AS StateDesc, ' +
	'    (SELECT CAST(current_storage_size_mb AS VARCHAR(20)) FROM sys.database_query_store_options) + '' MB'' AS StorageUsed; '
FROM QueryVaultDB.dbo.DatabaseConfig
WHERE IsEnabled = 1
ORDER BY DatabaseName;

IF LEN(@SQL) > 0
BEGIN
	EXEC sp_executesql @SQL;
END

PRINT '';
PRINT '========================================';
PRINT 'Next Steps:';
PRINT '1. Run some queries on your databases to populate QueryStore';
PRINT '2. Test archiving: EXEC QueryVaultDB.dbo.usp_ArchiveQueryStore @SourceDatabaseName = ''YourDatabase'', @RunName = ''Test'', @DoNotDelete = 1';
PRINT '3. Create SQL Agent jobs using scripts in Jobs folder';
PRINT '========================================';
GO

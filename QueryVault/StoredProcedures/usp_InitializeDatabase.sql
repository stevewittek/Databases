/*
	Stored Procedure: usp_InitializeDatabase
	Registers a new database for QueryStore archiving
*/

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.usp_InitializeDatabase
	@DatabaseName NVARCHAR(128),
	@ServerName NVARCHAR(128) = NULL,
	@DefaultDaysToArchive INT = 30,
	@ScheduleType NVARCHAR(50) = 'Daily',
	@ScheduleTime TIME(7) = '02:00:00',
	@CompressionDelayMinutes INT = 0,
	@DefaultRetentionDays INT = 365,
	@AutoDeleteEnabled BIT = 0,
	@MaxRetainedRuns INT = 1000,
	@PartitionWarningPct TINYINT = 80,
	@StorageMode NVARCHAR(20) = N'AUTO',
	@Comments NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @ConfigID INT;

	SET @StorageMode = UPPER(LTRIM(RTRIM(@StorageMode)));

	IF @MaxRetainedRuns IS NULL OR @MaxRetainedRuns < 1 OR @MaxRetainedRuns > 14990
		THROW 51040, 'MaxRetainedRuns must be between 1 and 14990.', 1;

	IF @PartitionWarningPct IS NULL OR @PartitionWarningPct < 50 OR @PartitionWarningPct > 95
		THROW 51041, 'PartitionWarningPct must be between 50 and 95.', 1;

	IF @StorageMode IS NULL OR @StorageMode NOT IN (N'AUTO', N'ROWSTORE', N'COLUMNSTORE')
		THROW 51042, 'StorageMode must be AUTO, ROWSTORE, or COLUMNSTORE.', 1;

	BEGIN TRY
		-- Default to current server if not specified
		SET @ServerName = ISNULL(@ServerName, @@SERVERNAME);

		-- Check if database already exists in config
		SELECT @ConfigID = ConfigID
		FROM dbo.DatabaseConfig
		WHERE DatabaseName = @DatabaseName
		  AND ServerName = @ServerName;

		IF @ConfigID IS NOT NULL
		BEGIN
			PRINT 'Database "' + @DatabaseName + '" already exists in configuration with ConfigID: ' + CAST(@ConfigID AS VARCHAR(20));
			PRINT 'Updating configuration...';

			UPDATE dbo.DatabaseConfig
			SET 
				DefaultDaysToArchive = @DefaultDaysToArchive,
				ScheduleType = @ScheduleType,
				ScheduleTime = @ScheduleTime,
				CompressionDelayMinutes = @CompressionDelayMinutes,
				DefaultRetentionDays = @DefaultRetentionDays,
				AutoDeleteEnabled = @AutoDeleteEnabled,
				MaxRetainedRuns = @MaxRetainedRuns,
				PartitionWarningPct = @PartitionWarningPct,
				StorageMode = @StorageMode,
				Comments = ISNULL(@Comments, Comments),
				ModifiedDate = SYSUTCDATETIME(),
				ModifiedBy = SUSER_SNAME(),
				IsEnabled = 1
			WHERE ConfigID = @ConfigID;

			PRINT 'Configuration updated successfully';
		END
		ELSE
		BEGIN
			PRINT 'Registering new database "' + @DatabaseName + '" for QueryStore archiving...';

			INSERT INTO dbo.DatabaseConfig
			(
				DatabaseName,
				ServerName,
				IsEnabled,
				DefaultDaysToArchive,
				ScheduleType,
				ScheduleTime,
				CompressionDelayMinutes,
				DefaultRetentionDays,
				AutoDeleteEnabled,
				MaxRetainedRuns,
				PartitionWarningPct,
				StorageMode,
				Comments
			)
			VALUES
			(
				@DatabaseName,
				@ServerName,
				1, -- Enabled by default
				@DefaultDaysToArchive,
				@ScheduleType,
				@ScheduleTime,
				@CompressionDelayMinutes,
				@DefaultRetentionDays,
				@AutoDeleteEnabled,
				@MaxRetainedRuns,
				@PartitionWarningPct,
				@StorageMode,
				@Comments
			);

			SET @ConfigID = SCOPE_IDENTITY();
			PRINT 'Database registered successfully with ConfigID: ' + CAST(@ConfigID AS VARCHAR(20));
		END

		-- Return the config information
		SELECT 
			ConfigID,
			DatabaseName,
			ServerName,
			IsEnabled,
			DefaultDaysToArchive,
			ScheduleType,
			ScheduleTime,
			CompressionDelayMinutes,
			DefaultRetentionDays,
			AutoDeleteEnabled,
			MaxRetainedRuns,
			PartitionWarningPct,
			StorageMode,
			Comments,
			CreatedDate,
			ModifiedDate
		FROM dbo.DatabaseConfig
		WHERE ConfigID = @ConfigID;

		RETURN 0;

	END TRY
	BEGIN CATCH
		SET @ErrorMessage = 'Error in usp_InitializeDatabase: ' + ERROR_MESSAGE();
		RAISERROR(@ErrorMessage, 16, 1);
		RETURN -1;
	END CATCH
END
GO

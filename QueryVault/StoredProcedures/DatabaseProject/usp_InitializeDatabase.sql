CREATE PROCEDURE dbo.usp_InitializeDatabase
	@DatabaseName NVARCHAR(128),
	@ServerName NVARCHAR(128) = NULL,
	@DefaultDaysToArchive INT = 30,
	@ScheduleType NVARCHAR(50) = 'Daily',
	@ScheduleTime TIME(7) = '02:00:00',
	@CompressionDelayMinutes INT = 0,
	@DefaultRetentionDays INT = 365,
	@AutoDeleteEnabled BIT = 0,
	@Comments NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @ConfigID INT;

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

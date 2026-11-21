CREATE PROCEDURE dbo.usp_PurgeExpiredArchives
	@AsOfDateTime DATETIME2(7) = NULL,
	@DryRun BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	-- NULL must not fall through the preview branch into destructive work.
	-- Disable XACT_ABORT inside this procedure before rejecting the argument;
	-- the caller's SET option is restored automatically when control returns.
	IF @DryRun IS NULL
	BEGIN
		SET XACT_ABORT OFF;
		RAISERROR ('DryRun cannot be NULL; specify 1 for preview or 0 for deletion.', 16, 1);
		RETURN -1;
	END;
	-- A caller may use purge inside a wider reversible maintenance transaction.
	-- Savepoints must remain usable after expected statement failures. Procedure
	-- SET options are restored when control returns to the caller.
	DECLARE @CallerOwnsTransaction BIT = CASE WHEN @@TRANCOUNT > 0 THEN 1 ELSE 0 END;
	IF @CallerOwnsTransaction = 1
		SET XACT_ABORT OFF;
	ELSE
		SET XACT_ABORT ON;

	DECLARE @EffectiveAsOf DATETIME2(7) = ISNULL(@AsOfDateTime, SYSUTCDATETIME());
	DECLARE @RunID INT;
	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @FailureCount INT = 0;
	DECLARE @PurgedCount INT = 0;
	DECLARE @LockResult INT;

	DECLARE @Candidates TABLE
	(
		RunID INT NOT NULL PRIMARY KEY,
		SourceDatabaseName NVARCHAR(128) NOT NULL,
		RetentionDate DATETIME2(7) NOT NULL
	);

	DECLARE @Failures TABLE
	(
		RunID INT NOT NULL,
		ErrorMessage NVARCHAR(4000) NOT NULL
	);

	INSERT @Candidates (RunID, SourceDatabaseName, RetentionDate)
	SELECT rm.RunID, rm.SourceDatabaseName, rm.RetentionDate
	FROM dbo.RunMetadata AS rm
	JOIN dbo.DatabaseConfig AS dc
		ON dc.DatabaseName = rm.SourceDatabaseName
		AND dc.ServerName = rm.SourceServerName
	WHERE dc.AutoDeleteEnabled = 1
	  AND rm.RunStatus = N'Completed'
	  AND rm.DoNotDelete = 0
	  AND rm.RetentionDate IS NOT NULL
	  AND rm.RetentionDate <= @EffectiveAsOf;

	IF @DryRun = 1
	BEGIN
		SELECT RunID, SourceDatabaseName, RetentionDate
		FROM @Candidates
		ORDER BY RunID;

		RETURN 0;
	END;

	DECLARE purge_cursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT RunID
		FROM @Candidates
		ORDER BY RunID;

	OPEN purge_cursor;
	FETCH NEXT FROM purge_cursor INTO @RunID;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		BEGIN TRY
			IF @CallerOwnsTransaction = 0
				BEGIN TRANSACTION;
			ELSE
				SAVE TRANSACTION PurgeExpiredRun;

			-- All lifecycle paths take the application lock before RunMetadata
			-- row locks, including direct SwitchOut/Truncate/MergeBoundary calls.
			EXEC @LockResult = sys.sp_getapplock
				@Resource = N'QueryVault.PF_RunID',
				@LockMode = N'Exclusive',
				@LockOwner = N'Transaction',
				@LockTimeout = 30000;

			IF @LockResult < 0
				THROW 51054, 'Could not acquire the QueryVault partition lifecycle lock.', 1;

			-- Recheck eligibility while holding an update lock. This prevents a
			-- concurrently protected run from being removed after selection.
			IF EXISTS
			(
				SELECT 1
				FROM dbo.RunMetadata AS rm WITH (UPDLOCK, HOLDLOCK)
				JOIN dbo.DatabaseConfig AS dc
					ON dc.DatabaseName = rm.SourceDatabaseName
					AND dc.ServerName = rm.SourceServerName
				WHERE rm.RunID = @RunID
				  AND dc.AutoDeleteEnabled = 1
				  AND rm.RunStatus = N'Completed'
				  AND rm.DoNotDelete = 0
				  AND rm.RetentionDate IS NOT NULL
				  AND rm.RetentionDate <= @EffectiveAsOf
			)
			BEGIN
				EXEC dbo.usp_ManagePartitions
					@Operation = N'SwitchOut',
					@RunID = @RunID;

				EXEC dbo.usp_ManagePartitions
					@Operation = N'Truncate',
					@RunID = @RunID;

				DELETE dbo.RunMetadata
				WHERE RunID = @RunID;

				EXEC dbo.usp_ManagePartitions
					@Operation = N'MergeBoundary',
					@RunID = @RunID;

				SET @PurgedCount += 1;
			END;

			IF @CallerOwnsTransaction = 0
				COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			IF @CallerOwnsTransaction = 0 AND XACT_STATE() <> 0
				ROLLBACK TRANSACTION;
			ELSE IF @CallerOwnsTransaction = 1 AND XACT_STATE() = 1
				ROLLBACK TRANSACTION PurgeExpiredRun;
			ELSE IF @CallerOwnsTransaction = 1
			BEGIN
				-- Do not destroy the caller's transaction. An unrecoverable error
				-- (for example, a deadlock victim) must return to its owner now.
				CLOSE purge_cursor;
				DEALLOCATE purge_cursor;
				THROW;
			END;

			SET @ErrorMessage = ERROR_MESSAGE();
			SET @FailureCount += 1;

			INSERT @Failures (RunID, ErrorMessage)
			VALUES (@RunID, @ErrorMessage);
		END CATCH;

		FETCH NEXT FROM purge_cursor INTO @RunID;
	END;

	CLOSE purge_cursor;
	DEALLOCATE purge_cursor;

	SELECT
		@PurgedCount AS PurgedRunCount,
		@FailureCount AS FailedRunCount,
		@EffectiveAsOf AS AsOfDateTime;

	IF @FailureCount > 0
	BEGIN
		SELECT RunID, ErrorMessage
		FROM @Failures
		ORDER BY RunID;

		SET @ErrorMessage = CONCAT(
			N'QueryVault purge failed for ',
			@FailureCount,
			N' run(s). Successful eligible runs were still purged.'
		);
		THROW 51001, @ErrorMessage, 1;
	END;

	RETURN 0;
END;
GO

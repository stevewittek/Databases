/*
	Stored Procedure: usp_PurgeExpiredArchives
	Purges completed, unprotected archive runs after their configured retention date.
*/

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.usp_PurgeExpiredArchives
	@AsOfDateTime DATETIME2(7) = NULL,
	@DryRun BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @EffectiveAsOf DATETIME2(7) = ISNULL(@AsOfDateTime, SYSUTCDATETIME());
	DECLARE @RunID INT;
	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @FailureCount INT = 0;
	DECLARE @PurgedCount INT = 0;

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
			BEGIN TRANSACTION;

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

			COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			IF XACT_STATE() <> 0
				ROLLBACK TRANSACTION;

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

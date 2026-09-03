/*
	Manage the physical lifecycle of RunID-owned archive partitions.
	RunID is the immutable archive identity; partition_number is never persisted.
*/

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.usp_ManagePartitions
	@Operation NVARCHAR(50),
	@RunID INT = NULL,
	@NewPartitionCount INT = 1, -- compatibility parameter; bulk allocation is prohibited
	@ConfigID INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @PartitionNumber INT;
	DECLARE @SplitPartitionNumber INT;
	DECLARE @PhysicalPartitionCount INT;
	DECLARE @PartitionsToAdd INT;
	DECLARE @MaxBoundary INT;
	DECLARE @MaxRetainedRuns INT;
	DECLARE @PartitionWarningPct TINYINT;
	DECLARE @RetainedRunCount INT;
	DECLARE @WarningRunCount INT;
	DECLARE @IsAtOrAboveWarning BIT;
	DECLARE @ExceedsConfiguredRetainedRuns BIT;
	DECLARE @ExceedsOperationalPartitionLimit BIT;
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @StartedTransaction BIT = 0;
	DECLARE @LockResult INT;

	IF @Operation = N'GetInfo'
	BEGIN
		SELECT
			@PhysicalPartitionCount = pf.fanout,
			@MaxBoundary = MAX(CONVERT(INT, prv.value))
		FROM sys.partition_functions AS pf
		LEFT JOIN sys.partition_range_values AS prv
			ON prv.function_id = pf.function_id
		WHERE pf.name = N'PF_RunID'
		GROUP BY pf.fanout;

		IF @ConfigID IS NOT NULL
		BEGIN
			SELECT
				@MaxRetainedRuns = MaxRetainedRuns,
				@PartitionWarningPct = PartitionWarningPct
			FROM dbo.DatabaseConfig
			WHERE ConfigID = @ConfigID;

			IF @MaxRetainedRuns IS NULL
				THROW 51050, 'ConfigID was not found.', 1;

			SELECT @RetainedRunCount = COUNT(*)
			FROM dbo.RunMetadata AS rm
			INNER JOIN dbo.DatabaseConfig AS dc
				ON dc.ConfigID = @ConfigID
				AND dc.DatabaseName = rm.SourceDatabaseName
				AND dc.ServerName = rm.SourceServerName
			WHERE rm.RunStatus IN (N'In Progress', N'Completed');

			SELECT
				@WarningRunCount = WarningRunCount,
				@IsAtOrAboveWarning = IsAtOrAboveWarning
			FROM dbo.ufn_EvaluatePartitionCapacity
			(
				@RetainedRunCount, @MaxRetainedRuns, @PartitionWarningPct,
				@PhysicalPartitionCount, 0
			);
		END;

		SELECT
			N'PF_RunID' AS PartitionFunction,
			N'PS_RunID' AS PartitionScheme,
			@PhysicalPartitionCount AS PhysicalPartitionCount,
			@MaxBoundary AS MaximumBoundaryValue,
			CONVERT(INT, 15000) AS SqlServerPartitionLimit,
			CONVERT(INT, 10) AS ReservedPartitionHeadroom,
			CONVERT(INT, 14990) AS OperationalPartitionLimit,
			@ConfigID AS ConfigID,
			@RetainedRunCount AS ActiveRetainedRunCount,
			@MaxRetainedRuns AS MaxRetainedRuns,
			@PartitionWarningPct AS PartitionWarningPct,
			@WarningRunCount AS WarningRunCount,
			@IsAtOrAboveWarning AS IsAtOrAboveWarning;
		RETURN 0;
	END;

	IF @Operation IN (N'EnsureRunPartition', N'AddPartition')
	BEGIN
		IF @RunID IS NULL OR @RunID < 1
			THROW 51051, 'A positive RunID is required for run partition allocation.', 1;

		IF @RunID = 2147483647
			THROW 51052, 'RunID cannot reserve the required empty future boundary.', 1;

		IF @Operation = N'AddPartition' AND @NewPartitionCount <> 1
			THROW 51053, 'Bulk partition allocation is prohibited; allocate one exact RunID lifecycle at a time.', 1;

		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
			SET @StartedTransaction = 1;
		END
		ELSE
			SAVE TRANSACTION ManagePartitionsMutation;

		BEGIN TRY
			EXEC @LockResult = sys.sp_getapplock
				@Resource = N'QueryVault.PF_RunID',
				@LockMode = N'Exclusive',
				@LockOwner = N'Transaction',
				@LockTimeout = 30000;

			IF @LockResult < 0
				THROW 51054, 'Could not acquire the QueryVault partition lifecycle lock.', 1;

			IF @ConfigID IS NULL
			BEGIN
				SELECT @ConfigID = dc.ConfigID
				FROM dbo.RunMetadata AS rm
				INNER JOIN dbo.DatabaseConfig AS dc
					ON dc.DatabaseName = rm.SourceDatabaseName
					AND dc.ServerName = rm.SourceServerName
				WHERE rm.RunID = @RunID;
			END;

			SELECT
				@MaxRetainedRuns = MaxRetainedRuns,
				@PartitionWarningPct = PartitionWarningPct
			FROM dbo.DatabaseConfig
			WHERE ConfigID = @ConfigID;

			IF @MaxRetainedRuns IS NULL
				THROW 51055, 'Run partition allocation requires a matching DatabaseConfig row.', 1;

			IF NOT EXISTS
			(
				SELECT 1
				FROM dbo.RunMetadata AS rm
				INNER JOIN dbo.DatabaseConfig AS dc
					ON dc.ConfigID = @ConfigID
					AND dc.DatabaseName = rm.SourceDatabaseName
					AND dc.ServerName = rm.SourceServerName
				WHERE rm.RunID = @RunID
			)
				THROW 51056, 'RunID does not belong to the supplied DatabaseConfig row.', 1;

			SELECT @RetainedRunCount = COUNT(*)
			FROM dbo.RunMetadata AS rm
			INNER JOIN dbo.DatabaseConfig AS dc
				ON dc.ConfigID = @ConfigID
				AND dc.DatabaseName = rm.SourceDatabaseName
				AND dc.ServerName = rm.SourceServerName
			WHERE rm.RunStatus IN (N'In Progress', N'Completed');

			SELECT
				@PhysicalPartitionCount = pf.fanout,
				@MaxBoundary = MAX(CONVERT(INT, prv.value))
			FROM sys.partition_functions AS pf
			LEFT JOIN sys.partition_range_values AS prv
				ON prv.function_id = pf.function_id
			WHERE pf.name = N'PF_RunID'
			GROUP BY pf.fanout;

			IF @PhysicalPartitionCount IS NULL
				THROW 51057, 'PF_RunID does not exist.', 1;

			IF @RunID < @MaxBoundary
				AND NOT EXISTS
				(
					SELECT 1
					FROM sys.partition_range_values AS prv
					INNER JOIN sys.partition_functions AS pf
						ON pf.function_id = prv.function_id
					WHERE pf.name = N'PF_RunID'
						AND CONVERT(INT, prv.value) = @RunID
				)
				THROW 51058, 'Cannot split a historical populated range; RunID boundaries must be allocated monotonically.', 1;

			SET @PartitionsToAdd = 0;
			IF NOT EXISTS
			(
				SELECT 1
				FROM sys.partition_range_values AS prv
				INNER JOIN sys.partition_functions AS pf
					ON pf.function_id = prv.function_id
				WHERE pf.name = N'PF_RunID'
					AND CONVERT(INT, prv.value) = @RunID
			)
				SET @PartitionsToAdd += 1;

			IF NOT EXISTS
			(
				SELECT 1
				FROM sys.partition_range_values AS prv
				INNER JOIN sys.partition_functions AS pf
					ON pf.function_id = prv.function_id
				WHERE pf.name = N'PF_RunID'
					AND CONVERT(INT, prv.value) = @RunID + 1
			)
				SET @PartitionsToAdd += 1;

			SELECT
				@WarningRunCount = WarningRunCount,
				@IsAtOrAboveWarning = IsAtOrAboveWarning,
				@ExceedsConfiguredRetainedRuns = ExceedsConfiguredRetainedRuns,
				@ExceedsOperationalPartitionLimit = ExceedsOperationalPartitionLimit
			FROM dbo.ufn_EvaluatePartitionCapacity
			(
				@RetainedRunCount, @MaxRetainedRuns, @PartitionWarningPct,
				@PhysicalPartitionCount, @PartitionsToAdd
			);

			IF @ExceedsConfiguredRetainedRuns = 1
				THROW 51059, 'MaxRetainedRuns is reached; purge an eligible run or intentionally increase the configuration.', 1;

			IF @ExceedsOperationalPartitionLimit = 1
				THROW 51060, 'Partition allocation would consume reserved headroom below SQL Server''s 15000-partition limit.', 1;

			IF @PartitionsToAdd > 0
			BEGIN
				SET @SplitPartitionNumber = CASE
					WHEN NOT EXISTS
					(
						SELECT 1
						FROM sys.partition_range_values AS prv
						INNER JOIN sys.partition_functions AS pf
							ON pf.function_id = prv.function_id
						WHERE pf.name = N'PF_RunID'
							AND CONVERT(INT, prv.value) = @RunID
					)
					THEN $PARTITION.PF_RunID(@RunID)
					ELSE $PARTITION.PF_RunID(@RunID + 1)
				END;

				IF EXISTS
				(
					SELECT 1 FROM dbo.query_store_query WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_query_text WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_plan WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_interval WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_contributor WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_canonical WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_contributor WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_canonical WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_query_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_query_text_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_plan_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @SplitPartitionNumber
				)
					THROW 51073, 'RunID allocation requires an empty split partition; migrate legacy overflow data before retrying.', 1;
			END;

			IF @IsAtOrAboveWarning = 1
				RAISERROR(
					'QueryVault retained-run warning: %d retained runs; warning threshold %d; configured maximum %d.',
					10, 1, @RetainedRunCount, @WarningRunCount, @MaxRetainedRuns
				) WITH NOWAIT;

			IF NOT EXISTS
			(
				SELECT 1
				FROM sys.partition_range_values AS prv
				INNER JOIN sys.partition_functions AS pf
					ON pf.function_id = prv.function_id
				WHERE pf.name = N'PF_RunID'
					AND CONVERT(INT, prv.value) = @RunID
			)
			BEGIN
				ALTER PARTITION SCHEME PS_RunID NEXT USED [PRIMARY];
				SET @SQL = N'ALTER PARTITION FUNCTION PF_RunID() SPLIT RANGE('
					+ CONVERT(NVARCHAR(20), @RunID) + N');';
				EXEC sys.sp_executesql @SQL;
			END;

			IF NOT EXISTS
			(
				SELECT 1
				FROM sys.partition_range_values AS prv
				INNER JOIN sys.partition_functions AS pf
					ON pf.function_id = prv.function_id
				WHERE pf.name = N'PF_RunID'
					AND CONVERT(INT, prv.value) = @RunID + 1
			)
			BEGIN
				ALTER PARTITION SCHEME PS_RunID NEXT USED [PRIMARY];
				SET @SQL = N'ALTER PARTITION FUNCTION PF_RunID() SPLIT RANGE('
					+ CONVERT(NVARCHAR(20), @RunID + 1) + N');';
				EXEC sys.sp_executesql @SQL;
			END;

			SET @PartitionNumber = $PARTITION.PF_RunID(@RunID);
			IF @PartitionNumber = $PARTITION.PF_RunID(@RunID + 1)
				THROW 51061, 'RunID was not isolated from its future partition.', 1;

			IF EXISTS
			(
				SELECT 1
				FROM dbo.RunMetadata
				WHERE RunID <> @RunID
					AND RunStatus IN (N'In Progress', N'Completed')
					AND $PARTITION.PF_RunID(RunID) = @PartitionNumber
			)
				THROW 51062, 'The allocated physical partition maps another retained RunID.', 1;

			IF @StartedTransaction = 1
				COMMIT TRANSACTION;

			RETURN 0;
		END TRY
		BEGIN CATCH
			IF @StartedTransaction = 1 AND XACT_STATE() <> 0
				ROLLBACK TRANSACTION;
			ELSE IF @StartedTransaction = 0 AND XACT_STATE() = 1
				ROLLBACK TRANSACTION ManagePartitionsMutation;
			THROW;
		END CATCH;
	END;

	IF @Operation IN (N'SwitchOut', N'Truncate')
	BEGIN
		IF @RunID IS NULL
			THROW 51063, 'RunID is required for SwitchOut or Truncate.', 1;

		IF EXISTS
		(
			SELECT 1 FROM dbo.RunMetadata
			WHERE RunID = @RunID AND DoNotDelete = 1
		)
			THROW 51064, 'Pinned or preserved runs cannot be switched or truncated.', 1;

		SET @PartitionNumber = $PARTITION.PF_RunID(@RunID);

		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
			SET @StartedTransaction = 1;
		END
		ELSE
			SAVE TRANSACTION ManagePartitionsMutation;

		BEGIN TRY
			EXEC @LockResult = sys.sp_getapplock
				@Resource = N'QueryVault.PF_RunID',
				@LockMode = N'Exclusive',
				@LockOwner = N'Transaction',
				@LockTimeout = 30000;

			IF @LockResult < 0
				THROW 51054, 'Could not acquire the QueryVault partition lifecycle lock.', 1;

			IF @Operation = N'SwitchOut'
			BEGIN
				IF EXISTS
				(
					SELECT 1 FROM dbo.query_store_query WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_query_text WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_plan WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_interval WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_contributor WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_canonical WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_contributor WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_canonical WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				)
					THROW 51065, 'Refusing to switch a physical partition that contains multiple RunID values.', 1;

				IF EXISTS
				(
					SELECT 1 FROM dbo.query_store_query_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_query_text_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_plan_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				)
					THROW 51066, 'The target maintenance partition is not empty.', 1;

				DECLARE @Tables TABLE (TableName SYSNAME NOT NULL);
				INSERT @Tables (TableName) VALUES
					(N'query_store_query'),
					(N'query_store_query_text'),
					(N'query_store_plan'),
					(N'query_store_runtime_stats'),
					(N'query_store_runtime_stats_interval'),
					(N'query_store_wait_stats'),
					(N'query_store_runtime_stats_contributor'),
					(N'query_store_runtime_stats_canonical'),
					(N'query_store_wait_stats_contributor'),
					(N'query_store_wait_stats_canonical');

				DECLARE @TableName SYSNAME;
				DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
					SELECT TableName FROM @Tables;
				OPEN table_cursor;
				FETCH NEXT FROM table_cursor INTO @TableName;
				WHILE @@FETCH_STATUS = 0
				BEGIN
					SET @SQL = N'ALTER TABLE dbo.' + QUOTENAME(@TableName)
						+ N' SWITCH PARTITION ' + CONVERT(NVARCHAR(20), @PartitionNumber)
						+ N' TO dbo.' + QUOTENAME(@TableName + N'_PartitionMaintenance')
						+ N' PARTITION ' + CONVERT(NVARCHAR(20), @PartitionNumber) + N';';
					EXEC sys.sp_executesql @SQL;
					FETCH NEXT FROM table_cursor INTO @TableName;
				END;
				CLOSE table_cursor;
				DEALLOCATE table_cursor;
			END
			ELSE
			BEGIN
				IF EXISTS
				(
					SELECT 1 FROM dbo.query_store_query_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_query_text_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_plan_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
					UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				)
					THROW 51067, 'Refusing to truncate a physical partition that contains multiple RunID values.', 1;

				DECLARE @MaintenanceTables TABLE (TableName SYSNAME NOT NULL);
				INSERT @MaintenanceTables (TableName) VALUES
					(N'query_store_query_PartitionMaintenance'),
					(N'query_store_query_text_PartitionMaintenance'),
					(N'query_store_plan_PartitionMaintenance'),
					(N'query_store_runtime_stats_PartitionMaintenance'),
					(N'query_store_runtime_stats_interval_PartitionMaintenance'),
					(N'query_store_wait_stats_PartitionMaintenance'),
					(N'query_store_runtime_stats_contributor_PartitionMaintenance'),
					(N'query_store_runtime_stats_canonical_PartitionMaintenance'),
					(N'query_store_wait_stats_contributor_PartitionMaintenance'),
					(N'query_store_wait_stats_canonical_PartitionMaintenance');

				DECLARE maintenance_cursor CURSOR LOCAL FAST_FORWARD FOR
					SELECT TableName FROM @MaintenanceTables;
				OPEN maintenance_cursor;
				FETCH NEXT FROM maintenance_cursor INTO @TableName;
				WHILE @@FETCH_STATUS = 0
				BEGIN
					SET @SQL = N'TRUNCATE TABLE dbo.' + QUOTENAME(@TableName)
						+ N' WITH (PARTITIONS(' + CONVERT(NVARCHAR(20), @PartitionNumber) + N'));';
					EXEC sys.sp_executesql @SQL;
					FETCH NEXT FROM maintenance_cursor INTO @TableName;
				END;
				CLOSE maintenance_cursor;
				DEALLOCATE maintenance_cursor;
			END;

			IF @StartedTransaction = 1
				COMMIT TRANSACTION;
			RETURN 0;
		END TRY
		BEGIN CATCH
			IF CURSOR_STATUS('local', 'table_cursor') >= -1
			BEGIN
				IF CURSOR_STATUS('local', 'table_cursor') > -1 CLOSE table_cursor;
				DEALLOCATE table_cursor;
			END;
			IF CURSOR_STATUS('local', 'maintenance_cursor') >= -1
			BEGIN
				IF CURSOR_STATUS('local', 'maintenance_cursor') > -1 CLOSE maintenance_cursor;
				DEALLOCATE maintenance_cursor;
			END;
			IF @StartedTransaction = 1 AND XACT_STATE() <> 0
				ROLLBACK TRANSACTION;
			ELSE IF @StartedTransaction = 0 AND XACT_STATE() = 1
				ROLLBACK TRANSACTION ManagePartitionsMutation;
			THROW;
		END CATCH;
	END;

	IF @Operation = N'MergeBoundary'
	BEGIN
		IF @RunID IS NULL
			THROW 51068, 'RunID is required for MergeBoundary.', 1;

		IF EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID = @RunID AND DoNotDelete = 1)
			THROW 51069, 'Pinned or preserved run boundaries cannot be merged.', 1;

		IF EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID = @RunID)
			THROW 51070, 'Delete eligible RunMetadata only after SWITCH/TRUNCATE and before merging its boundary.', 1;

		IF NOT EXISTS
		(
			SELECT 1
			FROM sys.partition_range_values AS prv
			INNER JOIN sys.partition_functions AS pf
				ON pf.function_id = prv.function_id
			WHERE pf.name = N'PF_RunID'
				AND CONVERT(INT, prv.value) = @RunID
		)
			RETURN 0;

		SET @PartitionNumber = $PARTITION.PF_RunID(@RunID);

		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
			SET @StartedTransaction = 1;
		END
		ELSE
			SAVE TRANSACTION ManagePartitionsMutation;

		BEGIN TRY
			EXEC @LockResult = sys.sp_getapplock
				@Resource = N'QueryVault.PF_RunID',
				@LockMode = N'Exclusive',
				@LockOwner = N'Transaction',
				@LockTimeout = 30000;

			IF @LockResult < 0
				THROW 51054, 'Could not acquire the QueryVault partition lifecycle lock.', 1;

			IF EXISTS
			(
				SELECT 1 FROM dbo.RunMetadata WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_query WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_query_text WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_plan WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_interval WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_wait_stats WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_contributor WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_canonical WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_contributor WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_canonical WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_query_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_query_text_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_plan_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_runtime_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_contributor_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
				UNION ALL SELECT 1 FROM dbo.query_store_wait_stats_canonical_PartitionMaintenance WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber
			)
				THROW 51071, 'Only an empty purged RunID partition boundary can be merged.', 1;

			SET @SQL = N'ALTER PARTITION FUNCTION PF_RunID() MERGE RANGE('
				+ CONVERT(NVARCHAR(20), @RunID) + N');';
			EXEC sys.sp_executesql @SQL;

			IF @StartedTransaction = 1
				COMMIT TRANSACTION;
			RETURN 0;
		END TRY
		BEGIN CATCH
			IF @StartedTransaction = 1 AND XACT_STATE() <> 0
				ROLLBACK TRANSACTION;
			ELSE IF @StartedTransaction = 0 AND XACT_STATE() = 1
				ROLLBACK TRANSACTION ManagePartitionsMutation;
			THROW;
		END CATCH;
	END;

	THROW 51072, 'Invalid operation. Use GetInfo, EnsureRunPartition, AddPartition, SwitchOut, Truncate, or MergeBoundary.', 1;
END;
GO

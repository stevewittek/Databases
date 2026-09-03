CREATE PROCEDURE dbo.usp_ManagePartitions
	@Operation NVARCHAR(50), -- 'AddPartition', 'SwitchOut', 'Truncate', 'GetInfo'
	@RunID INT = NULL,
	@NewPartitionCount INT = 10 -- How many new partitions to add when extending
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @PartitionNumber INT;
	DECLARE @MaxRunIDInFunction INT;
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @StartedTransaction BIT = 0;

	BEGIN TRY

		-- Operation: Get Partition Information
		IF @Operation = 'GetInfo'
		BEGIN
			SELECT
				pf.name AS PartitionFunction,
				pf.fanout AS PartitionCount,
				ps.name AS PartitionScheme,
				MAX(CAST(prv.value AS INT)) AS MaxRunIDSupported
			FROM sys.partition_functions pf
			INNER JOIN sys.partition_schemes ps ON ps.function_id = pf.function_id
			LEFT JOIN sys.partition_range_values prv ON prv.function_id = pf.function_id
			WHERE pf.name = 'PF_RunID'
			GROUP BY pf.name, pf.fanout, ps.name;

			RETURN 0;
		END

		-- Operation: Add New Partitions
		IF @Operation = 'AddPartition'
		BEGIN
			IF @NewPartitionCount <= 0
				THROW 51004, 'NewPartitionCount must be greater than zero.', 1;

			-- Get current max value in partition function
			SELECT @MaxRunIDInFunction = ISNULL(MAX(CAST(value AS INT)), 0)
			FROM sys.partition_range_values prv
			INNER JOIN sys.partition_functions pf ON pf.function_id = prv.function_id
			WHERE pf.name = 'PF_RunID';

			PRINT 'Current max RunID in partition function: ' + CAST(@MaxRunIDInFunction AS VARCHAR(20));

			-- Add new partitions
			DECLARE @Counter INT = 1;
			DECLARE @NewPartitionValue INT;

			WHILE @Counter <= @NewPartitionCount
			BEGIN
				SET @NewPartitionValue = @MaxRunIDInFunction + @Counter;

				-- Split partition to add new boundary
				SET @SQL = 'ALTER PARTITION SCHEME PS_RunID NEXT USED [PRIMARY];';
				EXEC sys.sp_executesql @SQL;

				SET @SQL = 'ALTER PARTITION FUNCTION PF_RunID() SPLIT RANGE(' + CAST(@NewPartitionValue AS VARCHAR(20)) + ');';
				EXEC sys.sp_executesql @SQL;

				PRINT 'Added partition for RunID: ' + CAST(@NewPartitionValue AS VARCHAR(20));

				SET @Counter = @Counter + 1;
			END

			PRINT 'Successfully added ' + CAST(@NewPartitionCount AS VARCHAR(20)) + ' new partitions';
			RETURN 0;
		END

		-- Operation: Switch Out Partition (to maintenance table for cleanup)
		IF @Operation = 'SwitchOut'
		BEGIN
			IF @RunID IS NULL
			BEGIN
				RAISERROR('RunID is required for SwitchOut operation', 16, 1);
				RETURN -1;
			END

			-- Get partition number for the RunID
			SELECT @PartitionNumber = $PARTITION.PF_RunID(@RunID);

			PRINT 'Switching partition ' + CAST(@PartitionNumber AS VARCHAR(20)) + ' for RunID: ' + CAST(@RunID AS VARCHAR(20));

			IF @@TRANCOUNT = 0
			BEGIN
				BEGIN TRANSACTION;
				SET @StartedTransaction = 1;
			END;

			-- A partition switch moves every row in the physical partition. Refuse
			-- to switch if an overflow/shared partition contains another run.
			IF EXISTS
			(
				SELECT 1 FROM dbo.query_store_query
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_query_text
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_plan
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_runtime_stats
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_runtime_stats_interval
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_wait_stats
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
			)
				THROW 51005, 'Refusing to switch a physical partition that contains multiple RunID values.', 1;

			-- Switch each QueryStore table partition to maintenance table
			DECLARE @Tables TABLE (TableName NVARCHAR(128));
			INSERT INTO @Tables VALUES
				('query_store_query'),
				('query_store_query_text'),
				('query_store_plan'),
				('query_store_runtime_stats'),
				('query_store_runtime_stats_interval'),
				('query_store_wait_stats');

			DECLARE @TableName NVARCHAR(128);
			DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
				SELECT TableName FROM @Tables;

			OPEN table_cursor;
			FETCH NEXT FROM table_cursor INTO @TableName;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				SET @SQL = 'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
						  ' SWITCH PARTITION ' + CAST(@PartitionNumber AS VARCHAR(20)) +
						  ' TO dbo.' + QUOTENAME(@TableName + '_PartitionMaintenance') +
						  ' PARTITION ' + CAST(@PartitionNumber AS VARCHAR(20)) + ';';

				EXEC sys.sp_executesql @SQL;
				PRINT 'Switched partition for table: ' + @TableName;

				FETCH NEXT FROM table_cursor INTO @TableName;
			END

			CLOSE table_cursor;
			DEALLOCATE table_cursor;

			IF @StartedTransaction = 1
				COMMIT TRANSACTION;

			PRINT 'Successfully switched out all partitions for RunID: ' + CAST(@RunID AS VARCHAR(20));
			RETURN 0;
		END

		-- Operation: Truncate Maintenance Tables
		IF @Operation = 'Truncate'
		BEGIN
			IF @RunID IS NULL
			BEGIN
				RAISERROR('RunID is required for Truncate operation', 16, 1);
				RETURN -1;
			END

			-- Get partition number for the RunID
			SELECT @PartitionNumber = $PARTITION.PF_RunID(@RunID);

			PRINT 'Truncating partition ' + CAST(@PartitionNumber AS VARCHAR(20)) + ' for RunID: ' + CAST(@RunID AS VARCHAR(20));

			IF @@TRANCOUNT = 0
			BEGIN
				BEGIN TRANSACTION;
				SET @StartedTransaction = 1;
			END;

			-- Apply the same isolation guard to maintenance partitions. Truncating
			-- a shared overflow partition would otherwise remove multiple runs.
			IF EXISTS
			(
				SELECT 1 FROM dbo.query_store_query_PartitionMaintenance
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_query_text_PartitionMaintenance
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_plan_PartitionMaintenance
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_runtime_stats_PartitionMaintenance
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
				UNION ALL
				SELECT 1 FROM dbo.query_store_wait_stats_PartitionMaintenance
				WHERE $PARTITION.PF_RunID(RunID) = @PartitionNumber AND RunID <> @RunID
			)
				THROW 51006, 'Refusing to truncate a physical partition that contains multiple RunID values.', 1;

			-- Truncate each maintenance table partition
			DECLARE @MaintenanceTables TABLE (TableName NVARCHAR(128));
			INSERT INTO @MaintenanceTables VALUES
				('query_store_query_PartitionMaintenance'),
				('query_store_query_text_PartitionMaintenance'),
				('query_store_plan_PartitionMaintenance'),
				('query_store_runtime_stats_PartitionMaintenance'),
				('query_store_runtime_stats_interval_PartitionMaintenance'),
				('query_store_wait_stats_PartitionMaintenance');

			DECLARE maint_cursor CURSOR LOCAL FAST_FORWARD FOR
				SELECT TableName FROM @MaintenanceTables;

			OPEN maint_cursor;
			FETCH NEXT FROM maint_cursor INTO @TableName;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				SET @SQL = 'TRUNCATE TABLE dbo.' + QUOTENAME(@TableName) +
						  ' WITH (PARTITIONS(' + CAST(@PartitionNumber AS VARCHAR(20)) + '));';

				EXEC sys.sp_executesql @SQL;
				PRINT 'Truncated partition for table: ' + @TableName;

				FETCH NEXT FROM maint_cursor INTO @TableName;
			END

			CLOSE maint_cursor;
			DEALLOCATE maint_cursor;

			IF @StartedTransaction = 1
				COMMIT TRANSACTION;

			PRINT 'Successfully truncated all maintenance table partitions for RunID: ' + CAST(@RunID AS VARCHAR(20));
			RETURN 0;
		END

		-- Invalid operation
		RAISERROR('Invalid operation specified. Valid operations: AddPartition, SwitchOut, Truncate, GetInfo', 16, 1);
		RETURN -1;

	END TRY
	BEGIN CATCH
		IF @StartedTransaction = 1 AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		SET @ErrorMessage = 'Error in usp_ManagePartitions: ' + ERROR_MESSAGE();
		RAISERROR(@ErrorMessage, 16, 1);
		RETURN -1;
	END CATCH
END
GO

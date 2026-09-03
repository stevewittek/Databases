/*
	Deterministic transactional coverage for RunID partition lifecycle,
	capacity policy, pinned-run protection, alignment, and boundary merge.
*/

:on error exit

USE [QueryVaultDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

BEGIN TRANSACTION;
GO

:r ..\Scripts\MigrateRunPartitioning.sql
:r ..\Scripts\FixPartitionMaintenanceSwitchConstraints.sql
:r ..\Functions\ufn_EvaluatePartitionCapacity.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_canonical.sql
:r ..\Tables\QueryStore\query_store_wait_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_wait_stats_canonical.sql
:r ..\Tables\PartitionMaintenance\query_store_runtime_stats_contributor_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_runtime_stats_canonical_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_wait_stats_contributor_PartitionMaintenance.sql
:r ..\Tables\PartitionMaintenance\query_store_wait_stats_canonical_PartitionMaintenance.sql
:r ..\StoredProcedures\usp_InitializeDatabase.sql
:r ..\StoredProcedures\usp_ManagePartitions.sql
:r ..\StoredProcedures\usp_PurgeExpiredArchives.sql
GO

SET XACT_ABORT OFF;
GO

BEGIN TRY
	DECLARE @DatabaseName SYSNAME = CONCAT(N'__QueryVaultPartitionTest_', @@SPID);
	DECLARE @ConfigID INT;
	DECLARE @RunID1 INT;
	DECLARE @RunID2 INT;
	DECLARE @RunID3 INT;
	DECLARE @RunID4 INT;
	DECLARE @Partition1 INT;
	DECLARE @Partition2 INT;
	DECLARE @PhysicalBefore INT;
	DECLARE @PhysicalAfterFirst INT;
	DECLARE @PhysicalBeforeRejected INT;
	DECLARE @Rejected BIT;
	DECLARE @TestRunBase INT;

	EXEC dbo.usp_InitializeDatabase
		@DatabaseName = @DatabaseName,
		@ServerName = @@SERVERNAME,
		@DefaultDaysToArchive = 1,
		@DefaultRetentionDays = 1,
		@AutoDeleteEnabled = 1;

	SELECT @ConfigID = ConfigID
	FROM dbo.DatabaseConfig
	WHERE DatabaseName = @DatabaseName AND ServerName = @@SERVERNAME;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.DatabaseConfig
		WHERE ConfigID = @ConfigID
			AND MaxRetainedRuns = 1000
			AND PartitionWarningPct = 80
			AND StorageMode = N'AUTO'
	)
		THROW 51300, 'DatabaseConfig lifecycle defaults are incorrect.', 1;

	SET @Rejected = 0;
	BEGIN TRY
		EXEC dbo.usp_InitializeDatabase
			@DatabaseName = N'__InvalidZero',
			@MaxRetainedRuns = 0;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 51040 SET @Rejected = 1 ELSE THROW;
	END CATCH;
	IF @Rejected = 0 THROW 51301, 'MaxRetainedRuns = 0 was accepted.', 1;

	SET @Rejected = 0;
	BEGIN TRY
		EXEC dbo.usp_InitializeDatabase
			@DatabaseName = N'__InvalidHigh',
			@MaxRetainedRuns = 14991;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 51040 SET @Rejected = 1 ELSE THROW;
	END CATCH;
	IF @Rejected = 0 THROW 51302, 'MaxRetainedRuns above 14990 was accepted.', 1;

	SET @Rejected = 0;
	BEGIN TRY
		EXEC dbo.usp_InitializeDatabase
			@DatabaseName = N'__InvalidWarningLow',
			@PartitionWarningPct = 49;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 51041 SET @Rejected = 1 ELSE THROW;
	END CATCH;
	IF @Rejected = 0 THROW 51321, 'PartitionWarningPct below 50 was accepted.', 1;

	SET @Rejected = 0;
	BEGIN TRY
		EXEC dbo.usp_InitializeDatabase
			@DatabaseName = N'__InvalidWarningHigh',
			@PartitionWarningPct = 96;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 51041 SET @Rejected = 1 ELSE THROW;
	END CATCH;
	IF @Rejected = 0 THROW 51322, 'PartitionWarningPct above 95 was accepted.', 1;

	SET @Rejected = 0;
	BEGIN TRY
		EXEC dbo.usp_InitializeDatabase
			@DatabaseName = N'__InvalidStorageMode',
			@StorageMode = N'HEAP';
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 51042 SET @Rejected = 1 ELSE THROW;
	END CATCH;
	IF @Rejected = 0 THROW 51323, 'An unsupported StorageMode was accepted.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.ufn_EvaluatePartitionCapacity(800, 1000, 80, 1000, 2)
		WHERE IsAtOrAboveWarning = 1 AND CanAllocate = 1 AND WarningRunCount = 800
	)
		THROW 51303, 'The configured warning threshold is incorrect.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.ufn_EvaluatePartitionCapacity(1001, 1000, 80, 1000, 2)
		WHERE ExceedsConfiguredRetainedRuns = 1 AND CanAllocate = 0
	)
		THROW 51304, 'The configured retained-run maximum is not enforced.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.ufn_EvaluatePartitionCapacity(1, 14990, 80, 14989, 2)
		WHERE ExceedsOperationalPartitionLimit = 1
			AND SqlServerPartitionLimit = 15000
			AND ReservedPartitionHeadroom = 10
			AND CanAllocate = 0
	)
		THROW 51305, 'The physical partition ceiling headroom is not protected.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.ufn_EvaluatePartitionCapacity(1, 1000, 80, 500, 2)
		WHERE CanAllocate = 1 AND PartitionsToAdd = 2
	)
		OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ManagePartitions', N'P'))
			LIKE N'%@RunID - @MaxRunIDInFunction%'
		THROW 51306, 'Partition allocation still depends on lifetime RunID magnitude.', 1;

	SELECT @PhysicalBefore = fanout
	FROM sys.partition_functions
	WHERE name = N'PF_RunID';

	SELECT TOP (1) @TestRunBase = CONVERT(INT, prv.value)
	FROM sys.partition_range_values AS prv
	INNER JOIN sys.partition_functions AS pf
		ON pf.function_id = prv.function_id
	WHERE pf.name = N'PF_RunID'
		AND CONVERT(INT, prv.value) BETWEEN 20 AND 2147483644
		AND EXISTS
		(
			SELECT 1 FROM sys.partition_range_values AS next1
			WHERE next1.function_id = prv.function_id
				AND CONVERT(INT, next1.value) = CONVERT(INT, prv.value) + 1
		)
		AND EXISTS
		(
			SELECT 1 FROM sys.partition_range_values AS next2
			WHERE next2.function_id = prv.function_id
				AND CONVERT(INT, next2.value) = CONVERT(INT, prv.value) + 2
		)
		AND EXISTS
		(
			SELECT 1 FROM sys.partition_range_values AS next3
			WHERE next3.function_id = prv.function_id
				AND CONVERT(INT, next3.value) = CONVERT(INT, prv.value) + 3
		)
		AND NOT EXISTS
		(
			SELECT 1 FROM dbo.RunMetadata
			WHERE RunID BETWEEN CONVERT(INT, prv.value) AND CONVERT(INT, prv.value) + 3
		)
	ORDER BY CONVERT(INT, prv.value) DESC;

	IF @TestRunBase IS NULL
		THROW 51320, 'The lifecycle test requires four unused preallocated RunID boundaries.', 1;

	SET @RunID1 = @TestRunBase;
	SET @RunID2 = @TestRunBase + 1;
	SET @RunID3 = @TestRunBase + 2;
	SET @RunID4 = @TestRunBase + 3;

	SET IDENTITY_INSERT dbo.RunMetadata ON;
	INSERT dbo.RunMetadata
	(
		RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime,
		RunStatus, DoNotDelete, RetentionDate
	)
	VALUES
	(
		@RunID1, N'Partition lifecycle run 1', @DatabaseName,
		'2026-01-01T00:00:00', '2026-01-01T01:00:00',
		N'In Progress', 0, '2026-01-02T00:00:00'
	);
	SET IDENTITY_INSERT dbo.RunMetadata OFF;

	EXEC dbo.usp_ManagePartitions
		@Operation = N'EnsureRunPartition',
		@RunID = @RunID1,
		@ConfigID = @ConfigID;

	SET @Partition1 = $PARTITION.PF_RunID(@RunID1);
	IF @Partition1 = $PARTITION.PF_RunID(@RunID1 + 1)
		THROW 51307, 'The first run was not isolated from its empty future partition.', 1;

	SELECT @PhysicalAfterFirst = fanout
	FROM sys.partition_functions
	WHERE name = N'PF_RunID';

	IF @PhysicalAfterFirst - @PhysicalBefore NOT BETWEEN 0 AND 2
		THROW 51308, 'One run allocated more than two physical boundaries.', 1;

	SET IDENTITY_INSERT dbo.RunMetadata ON;
	INSERT dbo.RunMetadata
	(
		RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime,
		RunStatus, DoNotDelete, RetentionDate
	)
	VALUES
	(
		@RunID2, N'Partition lifecycle run 2', @DatabaseName,
		'2026-01-02T00:00:00', '2026-01-02T01:00:00',
		N'Completed', 1, NULL
	);
	SET IDENTITY_INSERT dbo.RunMetadata OFF;

	EXEC dbo.usp_ManagePartitions
		@Operation = N'EnsureRunPartition',
		@RunID = @RunID2,
		@ConfigID = @ConfigID;

	SET @Partition2 = $PARTITION.PF_RunID(@RunID2);
	IF @Partition1 = @Partition2
		THROW 51309, 'A second retained run shared the first run partition.', 1;

	IF EXISTS
	(
		SELECT 1
		FROM sys.tables AS t
		INNER JOIN sys.indexes AS i
			ON i.object_id = t.object_id
			AND i.index_id > 0
		LEFT JOIN sys.data_spaces AS ds
			ON ds.data_space_id = i.data_space_id
		WHERE t.name IN
		(
			N'query_store_query', N'query_store_query_text', N'query_store_plan',
			N'query_store_runtime_stats', N'query_store_runtime_stats_interval',
			N'query_store_wait_stats', N'query_store_runtime_stats_contributor',
			N'query_store_runtime_stats_canonical', N'query_store_wait_stats_contributor',
			N'query_store_wait_stats_canonical',
			N'query_store_query_PartitionMaintenance',
			N'query_store_query_text_PartitionMaintenance',
			N'query_store_plan_PartitionMaintenance',
			N'query_store_runtime_stats_PartitionMaintenance',
			N'query_store_runtime_stats_interval_PartitionMaintenance',
			N'query_store_wait_stats_PartitionMaintenance',
			N'query_store_runtime_stats_contributor_PartitionMaintenance',
			N'query_store_runtime_stats_canonical_PartitionMaintenance',
			N'query_store_wait_stats_contributor_PartitionMaintenance',
			N'query_store_wait_stats_canonical_PartitionMaintenance'
		)
			AND (ds.name <> N'PS_RunID' OR ds.name IS NULL)
	)
		THROW 51310, 'A run-owned table has a nonaligned index.', 1;

	INSERT dbo.query_store_runtime_stats_interval
		(RunID, runtime_stats_interval_id, start_time, end_time, comment)
	VALUES
		(@RunID1, -910000000001, '2026-01-01T00:00:00+00:00',
		 '2026-01-01T00:01:00+00:00', N'partition lifecycle test');

	EXEC dbo.usp_ManagePartitions @Operation = N'SwitchOut', @RunID = @RunID1;

	IF EXISTS
	(
		SELECT 1 FROM dbo.query_store_runtime_stats_interval
		WHERE RunID = @RunID1
	)
		OR NOT EXISTS
		(
			SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance
			WHERE RunID = @RunID1
		)
		THROW 51311, 'SWITCH did not preserve the run-owned interval rows.', 1;

	EXEC dbo.usp_ManagePartitions @Operation = N'Truncate', @RunID = @RunID1;

	IF EXISTS
	(
		SELECT 1 FROM dbo.query_store_runtime_stats_interval_PartitionMaintenance
		WHERE RunID = @RunID1
	)
		THROW 51312, 'TRUNCATE did not remove the switched run rows.', 1;

	DELETE dbo.RunMetadata WHERE RunID = @RunID1;
	EXEC dbo.usp_ManagePartitions @Operation = N'MergeBoundary', @RunID = @RunID1;

	IF EXISTS
	(
		SELECT 1
		FROM sys.partition_range_values AS prv
		INNER JOIN sys.partition_functions AS pf
			ON pf.function_id = prv.function_id
		WHERE pf.name = N'PF_RunID' AND CONVERT(INT, prv.value) = @RunID1
	)
		THROW 51313, 'The obsolete empty RunID boundary was not merged.', 1;

	SET @Rejected = 0;
	BEGIN TRY
		EXEC dbo.usp_ManagePartitions @Operation = N'SwitchOut', @RunID = @RunID2;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 51064 SET @Rejected = 1 ELSE THROW;
	END CATCH;
	IF @Rejected = 0 THROW 51314, 'A pinned run was allowed to enter purge lifecycle.', 1;

	SET IDENTITY_INSERT dbo.RunMetadata ON;
	INSERT dbo.RunMetadata
	(
		RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime, RunEndTime,
		RunStatus, DoNotDelete, RetentionDate
	)
	VALUES
	(
		@RunID3, N'Expired partition lifecycle run', @DatabaseName,
		'2026-01-03T00:00:00', '2026-01-03T01:00:00', '2026-01-03T01:01:00',
		N'Completed', 0, '2026-01-04T00:00:00'
	);
	SET IDENTITY_INSERT dbo.RunMetadata OFF;

	EXEC dbo.usp_ManagePartitions
		@Operation = N'EnsureRunPartition',
		@RunID = @RunID3,
		@ConfigID = @ConfigID;

	INSERT dbo.query_store_runtime_stats_interval
		(RunID, runtime_stats_interval_id, start_time, end_time, comment)
	VALUES
		(@RunID3, -910000000003, '2026-01-03T00:00:00+00:00',
		 '2026-01-03T00:01:00+00:00', N'expired lifecycle test');

	EXEC dbo.usp_PurgeExpiredArchives
		@AsOfDateTime = '2026-01-05T00:00:00',
		@DryRun = 0;

	IF EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID = @RunID3)
		THROW 51315, 'The eligible expired run was not purged.', 1;

	IF EXISTS
	(
		SELECT 1
		FROM sys.partition_range_values AS prv
		INNER JOIN sys.partition_functions AS pf
			ON pf.function_id = prv.function_id
		WHERE pf.name = N'PF_RunID' AND CONVERT(INT, prv.value) = @RunID3
	)
		THROW 51316, 'Purge did not merge the expired run boundary.', 1;

	IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID = @RunID2 AND DoNotDelete = 1)
		THROW 51317, 'Purge removed the pinned run.', 1;

	UPDATE dbo.DatabaseConfig
	SET MaxRetainedRuns = 1
	WHERE ConfigID = @ConfigID;

	SET IDENTITY_INSERT dbo.RunMetadata ON;
	INSERT dbo.RunMetadata
	(
		RunID, RunName, SourceDatabaseName, StartDateTime, EndDateTime,
		RunStatus, DoNotDelete, RetentionDate
	)
	VALUES
	(
		@RunID4, N'Blocked capacity run', @DatabaseName,
		'2026-01-04T00:00:00', '2026-01-04T01:00:00',
		N'In Progress', 0, '2026-01-05T00:00:00'
	);
	SET IDENTITY_INSERT dbo.RunMetadata OFF;

	SELECT @PhysicalBeforeRejected = fanout
	FROM sys.partition_functions
	WHERE name = N'PF_RunID';

	SET @Rejected = 0;
	BEGIN TRY
		EXEC dbo.usp_ManagePartitions
			@Operation = N'EnsureRunPartition',
			@RunID = @RunID4,
			@ConfigID = @ConfigID;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 51059 SET @Rejected = 1 ELSE THROW;
	END CATCH;

	IF @Rejected = 0
		THROW 51318, 'Configured retained-run maximum did not block allocation.', 1;

	IF @PhysicalBeforeRejected <>
		(SELECT fanout FROM sys.partition_functions WHERE name = N'PF_RunID')
		THROW 51319, 'Rejected capacity allocation changed the partition function.', 1;

	ROLLBACK TRANSACTION;
	SELECT N'PASS' AS result,
		N'RunID lifecycle, purge, pin, merge, capacity, alignment, and switch compatibility validated.' AS detail;
END TRY
BEGIN CATCH
	BEGIN TRY
		SET IDENTITY_INSERT dbo.RunMetadata OFF;
	END TRY
	BEGIN CATCH
	END CATCH;
	IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;
GO

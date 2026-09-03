/*
	Deterministic canonical aggregation test.

	Creates the additive canonical/contributor objects transactionally, loads
	synthetic native Query Store rows, verifies exact group behavior, and rolls
	back every database change.
*/

:on error exit

USE [QueryVaultDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

BEGIN TRANSACTION;
GO

:r ..\Tables\QueryStore\query_store_runtime_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_canonical.sql
:r ..\Tables\QueryStore\query_store_wait_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_wait_stats_canonical.sql
:r ..\StoredProcedures\usp_MaterializeCanonicalQueryStoreStats.sql
GO

BEGIN TRY
	DECLARE @RunID INT;

	INSERT dbo.RunMetadata
	(
		RunName, SourceDatabaseName, StartDateTime, EndDateTime,
		DoNotDelete, RetentionDate, RunStatus
	)
	VALUES
	(
		N'Canonical aggregation test', N'SyntheticQueryStore',
		'2026-01-01T00:00:00', '2026-01-01T01:00:00',
		1, NULL, N'In Progress'
	);
	SET @RunID = SCOPE_IDENTITY();

	DECLARE @RuntimeFixture TABLE
	(
		runtime_stats_id BIGINT NOT NULL,
		plan_id BIGINT NOT NULL,
		runtime_stats_interval_id BIGINT NOT NULL,
		execution_type TINYINT NOT NULL,
		first_execution_time DATETIMEOFFSET(7) NOT NULL,
		last_execution_time DATETIMEOFFSET(7) NOT NULL,
		count_executions BIGINT NOT NULL,
		avg_duration FLOAT NOT NULL,
		last_duration BIGINT NOT NULL,
		min_duration BIGINT NOT NULL,
		max_duration BIGINT NOT NULL,
		stdev_duration FLOAT NOT NULL,
		avg_cpu_time FLOAT NOT NULL,
		last_cpu_time BIGINT NOT NULL,
		min_cpu_time BIGINT NOT NULL,
		max_cpu_time BIGINT NOT NULL,
		stdev_cpu_time FLOAT NOT NULL,
		replica_group_id BIGINT NULL
	);

	INSERT @RuntimeFixture VALUES
		(10, 100, 1000, 0, '2026-01-01T00:01:00+00:00', '2026-01-01T00:05:00+00:00', 5, 200, 210, 100, 300, 10, 20, 21, 10, 30, 2, 7),
		-- Same native ID deliberately represents two active-interval contributors.
		(20, 200, 1000, 0, '2026-01-01T00:01:00+00:00', '2026-01-01T00:04:00+00:00', 1, 100, 111, 90, 110, 3, 10, 11, 8, 12, 1, 1),
		(20, 200, 1000, 0, '2026-01-01T00:02:00+00:00', '2026-01-01T00:06:00+00:00', 99, 1000, 999, 800, 1200, 30, 100, 101, 80, 120, 10, 2),
		(30, 300, 1000, 0, '2026-01-01T00:01:00+00:00', '2026-01-01T00:07:00+00:00', 2, 300, 301, 200, 350, 5, 30, 31, 20, 35, 2, 3),
		(31, 300, 1000, 0, '2026-01-01T00:02:00+00:00', '2026-01-01T00:07:00+00:00', 3, 400, 401, 250, 450, 6, 40, 41, 25, 45, 3, 3),
		(40, 200, 1000, 3, '2026-01-01T00:03:00+00:00', '2026-01-01T00:08:00+00:00', 4, 500, 501, 400, 600, 7, 50, 51, 40, 60, 4, 1),
		(50, 200, 2000, 0, '2026-01-01T00:10:00+00:00', '2026-01-01T00:12:00+00:00', 6, 600, 601, 500, 700, 8, 60, 61, 50, 70, 5, 1),
		(60, 400, 1000, 0, '2026-01-01T00:04:00+00:00', '2026-01-01T00:09:00+00:00', 7, 700, 701, 600, 800, 9, 70, 71, 60, 80, 6, NULL);

	INSERT dbo.query_store_runtime_stats_contributor
	(
		RunID, runtime_stats_id, plan_id, runtime_stats_interval_id,
		execution_type, execution_type_desc,
		first_execution_time, last_execution_time, count_executions,
		avg_duration, last_duration, min_duration, max_duration, stdev_duration,
		avg_cpu_time, last_cpu_time, min_cpu_time, max_cpu_time, stdev_cpu_time,
		avg_logical_io_reads, last_logical_io_reads, min_logical_io_reads, max_logical_io_reads, stdev_logical_io_reads,
		avg_logical_io_writes, last_logical_io_writes, min_logical_io_writes, max_logical_io_writes, stdev_logical_io_writes,
		avg_physical_io_reads, last_physical_io_reads, min_physical_io_reads, max_physical_io_reads, stdev_physical_io_reads,
		avg_clr_time, last_clr_time, min_clr_time, max_clr_time, stdev_clr_time,
		avg_dop, last_dop, min_dop, max_dop, stdev_dop,
		avg_query_max_used_memory, last_query_max_used_memory, min_query_max_used_memory, max_query_max_used_memory, stdev_query_max_used_memory,
		avg_rowcount, last_rowcount, min_rowcount, max_rowcount, stdev_rowcount,
		avg_num_physical_io_reads, last_num_physical_io_reads, min_num_physical_io_reads, max_num_physical_io_reads, stdev_num_physical_io_reads,
		avg_log_bytes_used, last_log_bytes_used, min_log_bytes_used, max_log_bytes_used, stdev_log_bytes_used,
		avg_tempdb_space_used, last_tempdb_space_used, min_tempdb_space_used, max_tempdb_space_used, stdev_tempdb_space_used,
		avg_page_server_io_reads, last_page_server_io_reads, min_page_server_io_reads, max_page_server_io_reads, stdev_page_server_io_reads,
		replica_group_id
	)
	SELECT
		@RunID, f.runtime_stats_id, f.plan_id, f.runtime_stats_interval_id,
		f.execution_type, CASE f.execution_type WHEN 0 THEN N'Regular' ELSE N'Aborted' END,
		f.first_execution_time, f.last_execution_time, f.count_executions,
		f.avg_duration, f.last_duration, f.min_duration, f.max_duration, f.stdev_duration,
		f.avg_cpu_time, f.last_cpu_time, f.min_cpu_time, f.max_cpu_time, f.stdev_cpu_time,
		10, 10, 1, 20, 2,
		11, 11, 1, 21, 2,
		12, 12, 1, 22, 2,
		13, 13, 1, 23, 2,
		2, 2, 1, 4, 1,
		14, 14, 1, 24, 2,
		15, 15, 1, 25, 2,
		16, 16, 1, 26, 2,
		17, 17, 1, 27, 2,
		18, 18, 1, 28, 2,
		19, 19, 1, 29, 2,
		f.replica_group_id
	FROM @RuntimeFixture AS f;

	DECLARE @WaitFixture TABLE
	(
		wait_stats_id BIGINT NOT NULL,
		plan_id BIGINT NOT NULL,
		runtime_stats_interval_id BIGINT NOT NULL,
		execution_type TINYINT NOT NULL,
		wait_category SMALLINT NOT NULL,
		total_wait BIGINT NOT NULL,
		source_average FLOAT NOT NULL,
		last_wait BIGINT NOT NULL,
		min_wait BIGINT NOT NULL,
		max_wait BIGINT NOT NULL,
		source_stdev FLOAT NOT NULL,
		replica_group_id BIGINT NULL
	);

	INSERT @WaitFixture VALUES
		(70, 200, 1000, 0, 3, 20, 20, 20, 15, 25, 1, 1),
		(70, 200, 1000, 0, 3, 980, 9.8989898989, 11, 5, 40, 4, 2),
		(71, 200, 1000, 0, 6, 500, 5, 50, 3, 60, 2, 1),
		(72, 200, 1000, 3, 3, 80, 20, 22, 4, 30, 3, 1),
		(73, 200, 2000, 0, 3, 60, 10, 12, 2, 20, 2, 1),
		(74, 400, 1000, 0, 3, 70, 10, 13, 3, 23, 2, NULL);

	INSERT dbo.query_store_wait_stats_contributor
	(
		RunID, wait_stats_id, plan_id, runtime_stats_interval_id,
		wait_category, wait_category_desc, execution_type, execution_type_desc,
		total_query_wait_time_ms, avg_query_wait_time_ms, last_query_wait_time_ms,
		min_query_wait_time_ms, max_query_wait_time_ms, stdev_query_wait_time_ms,
		replica_group_id
	)
	SELECT
		@RunID, f.wait_stats_id, f.plan_id, f.runtime_stats_interval_id,
		f.wait_category, CASE f.wait_category WHEN 3 THEN N'Lock' ELSE N'Buffer IO' END,
		f.execution_type, CASE f.execution_type WHEN 0 THEN N'Regular' ELSE N'Aborted' END,
		f.total_wait, f.source_average, f.last_wait,
		f.min_wait, f.max_wait, f.source_stdev, f.replica_group_id
	FROM @WaitFixture AS f;

	EXEC dbo.usp_MaterializeCanonicalQueryStoreStats
		@RunID = @RunID,
		@ObservationState = N'COMPLETED';

	IF (SELECT COUNT_BIG(*) FROM dbo.query_store_runtime_stats_contributor WHERE RunID = @RunID) <> 8
		THROW 51200, 'A runtime contributor was discarded.', 1;

	IF (SELECT COUNT_BIG(*) FROM dbo.query_store_runtime_stats_canonical WHERE RunID = @RunID) <> 6
		THROW 51201, 'Runtime canonical grouping merged or split a documented grain.', 1;

	IF (SELECT COUNT_BIG(*) FROM dbo.query_store_wait_stats_contributor WHERE RunID = @RunID) <> 6
		THROW 51202, 'A wait contributor was discarded.', 1;

	IF (SELECT COUNT_BIG(*) FROM dbo.query_store_wait_stats_canonical WHERE RunID = @RunID) <> 5
		THROW 51203, 'Wait canonical grouping merged or split a documented grain.', 1;

	DECLARE
		@RuntimeCount DECIMAL(38,0),
		@RuntimeAverage FLOAT,
		@RuntimeLast BIGINT,
		@RuntimeMin BIGINT,
		@RuntimeMax BIGINT,
		@RuntimeStdev FLOAT,
		@RuntimeAmbiguous BIT,
		@RuntimeContributorCount BIGINT,
		@RuntimeReplica BIGINT,
		@RuntimeReplicaCount INT,
		@LastRuntimeContributorID BIGINT,
		@StdevStatus NVARCHAR(64);

	SELECT
		@RuntimeCount = count_executions,
		@RuntimeAverage = avg_duration,
		@RuntimeLast = last_duration,
		@RuntimeMin = min_duration,
		@RuntimeMax = max_duration,
		@RuntimeStdev = stdev_duration,
		@RuntimeAmbiguous = last_value_ambiguous,
		@RuntimeContributorCount = contributor_count,
		@RuntimeReplica = replica_group_id,
		@RuntimeReplicaCount = replica_count,
		@LastRuntimeContributorID = last_runtime_stats_contributor_id,
		@StdevStatus = stdev_aggregation_status
	FROM dbo.query_store_runtime_stats_canonical
	WHERE RunID = @RunID
		AND plan_id = 200
		AND runtime_stats_interval_id = 1000
		AND execution_type = 0;

	IF @RuntimeCount <> 100 OR ABS(@RuntimeAverage - 991.0) > 0.0000001
		THROW 51204, 'Runtime execution sum or weighted mean is incorrect.', 1;
	IF @RuntimeLast <> 999 OR @RuntimeMin <> 90 OR @RuntimeMax <> 1200
		THROW 51205, 'Runtime chronological last value or extrema are incorrect.', 1;
	IF @RuntimeStdev IS NOT NULL OR @StdevStatus <> N'UNAVAILABLE_MULTIPLE_CONTRIBUTORS'
		THROW 51206, 'Runtime multi-contributor stdev claimed unsupported precision.', 1;
	IF @RuntimeAmbiguous <> 0 OR @RuntimeContributorCount <> 2
		THROW 51207, 'Runtime contributor or last-value state is incorrect.', 1;
	IF @RuntimeReplica IS NOT NULL OR @RuntimeReplicaCount <> 2
		THROW 51208, 'Mixed runtime replica provenance was collapsed.', 1;
	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.query_store_runtime_stats_contributor
		WHERE RunID = @RunID
			AND runtime_stats_contributor_id = @LastRuntimeContributorID
			AND runtime_stats_id = 20
			AND replica_group_id = 2
	)
		THROW 51209, 'The chronological runtime last contributor lineage is incorrect.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.query_store_runtime_stats_canonical
		WHERE RunID = @RunID
			AND plan_id = 300
			AND runtime_stats_interval_id = 1000
			AND execution_type = 0
			AND last_execution_time = '2026-01-01T00:07:00+00:00'
			AND last_value_ambiguous = 1
			AND last_duration IS NULL
			AND last_runtime_stats_contributor_id IS NULL
	)
		THROW 51210, 'Equal latest timestamps did not preserve runtime last-value ambiguity.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.query_store_runtime_stats_canonical
		WHERE RunID = @RunID
			AND plan_id = 100
			AND contributor_count = 1
			AND replica_group_id = 7
			AND replica_count = 1
			AND stdev_duration = 10
			AND stdev_aggregation_status = N'NATIVE_SINGLE_CONTRIBUTOR'
	)
		THROW 51211, 'Single-contributor runtime values were not preserved.', 1;

	IF
	(
		SELECT SUM(CONVERT(DECIMAL(38,0), count_executions))
		FROM dbo.query_store_runtime_stats_contributor
		WHERE RunID = @RunID
	) <>
	(
		SELECT SUM(count_executions)
		FROM dbo.query_store_runtime_stats_canonical
		WHERE RunID = @RunID
	)
		THROW 51212, 'Runtime executions were lost during aggregation.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.query_store_wait_stats_canonical
		WHERE RunID = @RunID
			AND plan_id = 200
			AND runtime_stats_interval_id = 1000
			AND execution_type = 0
			AND wait_category = 3
			AND total_query_wait_time_ms = 1000
			AND ABS(avg_query_wait_time_ms - 10.0) < 0.0000001
			AND min_query_wait_time_ms = 5
			AND max_query_wait_time_ms = 40
			AND last_query_wait_time_ms IS NULL
			AND last_value_ambiguous = 1
			AND stdev_query_wait_time_ms IS NULL
			AND stdev_aggregation_status = N'UNAVAILABLE_MULTIPLE_CONTRIBUTORS'
			AND replica_group_id IS NULL
			AND replica_count = 2
	)
		THROW 51213, 'Wait totals, denominator, extrema, ambiguity, stdev, or replica lineage are incorrect.', 1;

	IF NOT EXISTS
	(
		SELECT 1
		FROM dbo.query_store_wait_stats_canonical
		WHERE RunID = @RunID
			AND plan_id = 200
			AND runtime_stats_interval_id = 1000
			AND execution_type = 0
			AND wait_category = 6
			AND total_query_wait_time_ms = 500
			AND ABS(avg_query_wait_time_ms - 5.0) < 0.0000001
			AND last_query_wait_time_ms = 50
			AND last_value_ambiguous = 0
			AND stdev_query_wait_time_ms = 2
	)
		THROW 51214, 'Single-contributor wait values or category isolation are incorrect.', 1;

	IF
	(
		SELECT SUM(CONVERT(DECIMAL(38,0), total_query_wait_time_ms))
		FROM dbo.query_store_wait_stats_contributor
		WHERE RunID = @RunID
	) <>
	(
		SELECT SUM(total_query_wait_time_ms)
		FROM dbo.query_store_wait_stats_canonical
		WHERE RunID = @RunID
	)
		THROW 51215, 'Wait time was lost during aggregation.', 1;

	DECLARE @DuplicateRejected BIT = 0;
	BEGIN TRY
		INSERT dbo.query_store_runtime_stats_canonical
		SELECT *
		FROM dbo.query_store_runtime_stats_canonical
		WHERE RunID = @RunID
			AND plan_id = 100
			AND runtime_stats_interval_id = 1000
			AND execution_type = 0;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IN (2601, 2627)
			SET @DuplicateRejected = 1;
		ELSE
			THROW;
	END CATCH;

	IF @DuplicateRejected = 0
		THROW 51216, 'The canonical runtime key allowed a duplicate archive grain.', 1;

	EXEC dbo.usp_MaterializeCanonicalQueryStoreStats
		@RunID = @RunID,
		@ObservationState = N'PROVISIONAL';

	IF EXISTS
	(
		SELECT 1
		FROM
		(
			SELECT observation_state
			FROM dbo.query_store_runtime_stats_canonical
			WHERE RunID = @RunID
			UNION ALL
			SELECT observation_state
			FROM dbo.query_store_wait_stats_canonical
			WHERE RunID = @RunID
		) AS states
		WHERE observation_state <> N'PROVISIONAL'
	)
		THROW 51217, 'Provisional materialization was not explicitly marked.', 1;

	ROLLBACK TRANSACTION;
	SELECT N'PASS' AS result,
		N'Canonical runtime/wait aggregation, ambiguity, stdev discipline, replica lineage, and losslessness validated.' AS detail;
END TRY
BEGIN CATCH
	IF XACT_STATE() <> 0
		ROLLBACK TRANSACTION;
	THROW;
END CATCH;
GO

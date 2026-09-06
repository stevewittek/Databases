/*
	Transactional regression checks for Query Store canonical aggregation.

	Native contributor rows are lossless. Complete observations are materialized
	at Microsoft's documented runtime and wait grains. Legacy archive rows are
	reported for audit purposes and are not rejected during this additive upgrade.
*/

:on error exit

USE [QueryVaultDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;
GO

:r ..\Tables\QueryStore\query_store_runtime_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_runtime_stats_canonical.sql
:r ..\Tables\QueryStore\query_store_wait_stats_contributor.sql
:r ..\Tables\QueryStore\query_store_wait_stats_canonical.sql
:r ..\StoredProcedures\usp_MaterializeCanonicalQueryStoreStats.sql
:r ..\StoredProcedures\usp_ArchiveQueryStore.sql
GO

BEGIN TRY
	IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%flush_interval_seconds%'
		THROW 51100, 'Capture regression: Query Store flush interval cutoff is missing.', 1;

	IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%i.end_time <= @EndDateTime%'
		THROW 51101, 'Capture regression: completed interval end-time filter is missing.', 1;

	IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%@LookbackMinutes%'
		OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%DATEADD(MINUTE, -@LookbackMinutes, @ActualEndDateTime)%'
		THROW 51109, 'Capture regression: relative lookback period support is missing.', 1;

	IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%query_store_runtime_stats_contributor%'
		OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%query_store_wait_stats_contributor%'
		OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%usp_MaterializeCanonicalQueryStoreStats%'
		THROW 51102, 'Capture regression: contributor capture or canonical materialization is missing.', 1;

	IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_MaterializeCanonicalQueryStoreStats', N'P'))
		NOT LIKE N'%GROUP BY c.RunID, c.plan_id, c.runtime_stats_interval_id, c.execution_type%'
		THROW 51103, 'Runtime canonical grain is missing.', 1;

	IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_MaterializeCanonicalQueryStoreStats', N'P'))
		NOT LIKE N'%w.execution_type, w.wait_category%'
		THROW 51104, 'Wait canonical grain is missing.', 1;

	IF EXISTS
	(
		SELECT 1
		FROM dbo.query_store_runtime_stats_canonical
		GROUP BY RunID, plan_id, execution_type, runtime_stats_interval_id
		HAVING COUNT_BIG(*) > 1
	)
		THROW 51105, 'Canonical runtime data contains duplicate documented-grain groups.', 1;

	IF EXISTS
	(
		SELECT 1
		FROM dbo.query_store_wait_stats_canonical
		GROUP BY RunID, plan_id, runtime_stats_interval_id, execution_type, wait_category
		HAVING COUNT_BIG(*) > 1
	)
		THROW 51106, 'Canonical wait data contains duplicate documented-grain groups.', 1;

	IF EXISTS
	(
		SELECT 1
		FROM dbo.query_store_runtime_stats_contributor AS rs
		LEFT JOIN dbo.query_store_runtime_stats_interval AS i
			ON i.RunID = rs.RunID
			AND i.runtime_stats_interval_id = rs.runtime_stats_interval_id
		WHERE i.runtime_stats_interval_id IS NULL
	)
		THROW 51107, 'Runtime contributor data contains an orphaned interval reference.', 1;

	IF EXISTS
	(
		SELECT 1
		FROM dbo.query_store_wait_stats_contributor AS ws
		LEFT JOIN dbo.query_store_runtime_stats_interval AS i
			ON i.RunID = ws.RunID
			AND i.runtime_stats_interval_id = ws.runtime_stats_interval_id
		WHERE i.runtime_stats_interval_id IS NULL
	)
		THROW 51108, 'Wait contributor data contains an orphaned interval reference.', 1;

	-- Existing pre-upgrade rows can contain native duplicates. Report them; do
	-- not discard or reinterpret them as canonical observations.
	SELECT N'legacy_runtime_duplicate_group' AS audit_issue,
		RunID, plan_id, execution_type, runtime_stats_interval_id,
		COUNT_BIG(*) AS native_row_count
	FROM dbo.query_store_runtime_stats
	GROUP BY RunID, plan_id, execution_type, runtime_stats_interval_id
	HAVING COUNT_BIG(*) > 1;

	SELECT N'legacy_wait_duplicate_group' AS audit_issue,
		RunID, plan_id, runtime_stats_interval_id, execution_type, wait_category,
		COUNT_BIG(*) AS native_row_count
	FROM dbo.query_store_wait_stats
	GROUP BY RunID, plan_id, runtime_stats_interval_id, execution_type, wait_category
	HAVING COUNT_BIG(*) > 1;

	ROLLBACK TRANSACTION;
	SELECT N'PASS' AS result,
		N'Contributor capture, completed-interval cutoff, canonical grains, and uniqueness validated.' AS detail;
END TRY
BEGIN CATCH
	IF XACT_STATE() <> 0
		ROLLBACK TRANSACTION;
	THROW;
END CATCH;
GO

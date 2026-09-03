/*
	Read-only regression checks for the Query Store capture grain.

	Microsoft documents that an active Query Store interval may expose multiple
	runtime rows at (plan_id, execution_type, runtime_stats_interval_id) and
	multiple wait rows at that grain plus wait_category. QueryVault avoids that
	ambiguity by preferring intervals older than one flush interval and rejecting
	repeated documented-grain rows before a new run can complete. Rejection is a
	safety guard, not canonical source aggregation.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P') IS NULL
	OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%flush_interval_seconds%'
	THROW 51100, 'Capture regression: Query Store flush interval cutoff is missing.', 1;

IF OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P') IS NULL
	OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%i.end_time <= @EndDateTime%'
	THROW 51101, 'Capture regression: completed interval end-time filter is missing.', 1;

IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%GROUP BY plan_id, execution_type, runtime_stats_interval_id%'
	THROW 51106, 'Capture regression: runtime duplicate-grain rejection guard is missing.', 1;

IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ArchiveQueryStore', N'P')) NOT LIKE N'%GROUP BY plan_id, runtime_stats_interval_id, execution_type, wait_category%'
	THROW 51107, 'Capture regression: wait duplicate-grain rejection guard is missing.', 1;

IF EXISTS
(
	SELECT 1
	FROM dbo.query_store_runtime_stats
	GROUP BY RunID, plan_id, execution_type, runtime_stats_interval_id
	HAVING COUNT_BIG(*) > 1
)
	THROW 51102, 'Archived runtime data contains duplicate documented-grain groups.', 1;

IF EXISTS
(
	SELECT 1
	FROM dbo.query_store_wait_stats
	GROUP BY RunID, plan_id, runtime_stats_interval_id, execution_type, wait_category
	HAVING COUNT_BIG(*) > 1
)
	THROW 51103, 'Archived wait data contains duplicate documented-grain groups.', 1;

IF EXISTS
(
	SELECT 1
	FROM dbo.query_store_runtime_stats AS rs
	LEFT JOIN dbo.query_store_runtime_stats_interval AS i
		ON i.RunID = rs.RunID
		AND i.runtime_stats_interval_id = rs.runtime_stats_interval_id
	WHERE i.runtime_stats_interval_id IS NULL
)
	THROW 51104, 'Archived runtime data contains an orphaned interval reference.', 1;

IF EXISTS
(
	SELECT 1
	FROM dbo.query_store_wait_stats AS ws
	LEFT JOIN dbo.query_store_runtime_stats_interval AS i
		ON i.RunID = ws.RunID
		AND i.runtime_stats_interval_id = ws.runtime_stats_interval_id
	WHERE i.runtime_stats_interval_id IS NULL
)
	THROW 51105, 'Archived wait data contains an orphaned interval reference.', 1;

-- Boundary violations are reported rather than rejected because installations
-- upgraded from pre-cutoff releases can retain historically partial periods.
SELECT
	rm.RunID AS period_id,
	rm.RunName AS period_name,
	rm.RunStartTime AS archived_at_utc,
	rm.EndDateTime AS recorded_period_end_utc,
	MAX(i.end_time) AS latest_archived_interval_end_utc
FROM dbo.RunMetadata AS rm
INNER JOIN dbo.query_store_runtime_stats_interval AS i
	ON i.RunID = rm.RunID
GROUP BY rm.RunID, rm.RunName, rm.RunStartTime, rm.EndDateTime
HAVING MAX(i.end_time) > rm.EndDateTime
ORDER BY rm.RunID;

SELECT N'PASS' AS result,
	N'Capture cutoff and rejection guards present; no duplicate documented-grain groups or orphaned interval references.' AS detail;

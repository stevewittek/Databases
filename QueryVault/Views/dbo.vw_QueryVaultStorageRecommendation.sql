/* Advisory only. This view never rebuilds or converts archive storage. */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vw_QueryVaultStorageRecommendation
AS
	WITH ranked_run AS
	(
		SELECT
			dc.ConfigID,
			rm.RowsArchived_RuntimeStats,
			rm.RowsArchived_WaitStats,
			ROW_NUMBER() OVER
			(
				PARTITION BY dc.ConfigID
				ORDER BY rm.RunID DESC
			) AS recency_rank
		FROM dbo.DatabaseConfig AS dc
		INNER JOIN dbo.RunMetadata AS rm
			ON rm.SourceDatabaseName = dc.DatabaseName
			AND rm.SourceServerName = dc.ServerName
		WHERE rm.RunStatus = N'Completed'
	),
	recent_metric AS
	(
		SELECT
			r.ConfigID,
			v.FactType,
			COUNT(v.FactRowCount) AS SampledRunCount,
			AVG(CONVERT(DECIMAL(38,2), v.FactRowCount)) AS AverageRowsPerRun
		FROM ranked_run AS r
		CROSS APPLY
		(
			VALUES
				(N'RuntimeStats', r.RowsArchived_RuntimeStats),
				(N'WaitStats', r.RowsArchived_WaitStats)
		) AS v(FactType, FactRowCount)
		WHERE r.recency_rank <= 20
		GROUP BY r.ConfigID, v.FactType
	)
	SELECT
		dc.ConfigID,
		dc.ServerName,
		dc.DatabaseName,
		f.FactType,
		COALESCE(m.SampledRunCount, 0) AS SampledRunCount,
		m.AverageRowsPerRun,
		dc.StorageMode AS ConfiguredStorageMode,
		CONVERT(NVARCHAR(20), N'COLUMNSTORE') AS CurrentPhysicalStorageMode,
		CONVERT(NVARCHAR(20), CASE
			WHEN dc.StorageMode <> N'AUTO' THEN dc.StorageMode
			WHEN COALESCE(m.AverageRowsPerRun, 0) >= 100000 THEN N'COLUMNSTORE'
			ELSE N'ROWSTORE'
		END) AS SuggestedStorageMode,
		CONVERT(NVARCHAR(200), CASE
			WHEN dc.StorageMode <> N'AUTO'
				THEN N'Explicit configuration preference; no automatic conversion is performed.'
			WHEN COALESCE(m.SampledRunCount, 0) = 0
				THEN N'No completed-run sample; start with rowstore and measure.'
			WHEN m.AverageRowsPerRun >= 100000
				THEN N'Average fact volume is at least 100000 rows per recent run.'
			ELSE N'Average fact volume is below 100000 rows per recent run.'
		END) AS RecommendationBasis
	FROM dbo.DatabaseConfig AS dc
	CROSS APPLY
	(
		VALUES (N'RuntimeStats'), (N'WaitStats')
	) AS f(FactType)
	LEFT JOIN recent_metric AS m
		ON m.ConfigID = dc.ConfigID
		AND m.FactType = f.FactType;
GO

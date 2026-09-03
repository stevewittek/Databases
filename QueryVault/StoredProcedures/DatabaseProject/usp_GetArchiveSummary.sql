CREATE PROCEDURE dbo.usp_GetArchiveSummary
	@SourceDatabaseName NVARCHAR(128) = NULL,
	@RunID INT = NULL,
	@StartDate DATETIME2(7) = NULL,
	@EndDate DATETIME2(7) = NULL,
	@RunStatus NVARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT ON;

	SELECT
		rm.RunID,
		rm.RunName,
		rm.SourceDatabaseName,
		rm.SourceServerName,
		rm.StartDateTime,
		rm.EndDateTime,
		rm.RunStartTime,
		rm.RunEndTime,
		rm.RunStatus,
		rm.DoNotDelete,
		rm.RetentionDate,
		rm.RowsArchived_Query,
		rm.RowsArchived_QueryText,
		rm.RowsArchived_Plan,
		rm.RowsArchived_RuntimeStats,
		rm.RowsArchived_RuntimeStatsInterval,
		rm.RowsArchived_WaitStats,
		(ISNULL(rm.RowsArchived_Query, 0) +
		 ISNULL(rm.RowsArchived_QueryText, 0) +
		 ISNULL(rm.RowsArchived_Plan, 0) +
		 ISNULL(rm.RowsArchived_RuntimeStats, 0) +
		 ISNULL(rm.RowsArchived_RuntimeStatsInterval, 0) +
		 ISNULL(rm.RowsArchived_WaitStats, 0)) AS TotalRowsArchived,
		DATEDIFF(SECOND, rm.RunStartTime, ISNULL(rm.RunEndTime, SYSUTCDATETIME())) AS DurationSeconds,
		rm.Comments,
		rm.CreatedBy,
		$PARTITION.PF_RunID(rm.RunID) AS PartitionNumber
	FROM dbo.RunMetadata rm
	WHERE (@SourceDatabaseName IS NULL OR rm.SourceDatabaseName = @SourceDatabaseName)
	  AND (@RunID IS NULL OR rm.RunID = @RunID)
	  AND (@StartDate IS NULL OR rm.StartDateTime >= @StartDate)
	  AND (@EndDate IS NULL OR rm.EndDateTime <= @EndDate)
	  AND (@RunStatus IS NULL OR rm.RunStatus = @RunStatus)
	ORDER BY rm.RunID DESC;

END
GO

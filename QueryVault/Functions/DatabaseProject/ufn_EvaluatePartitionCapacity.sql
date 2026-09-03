CREATE FUNCTION dbo.ufn_EvaluatePartitionCapacity
(
	@ProjectedRetainedRuns INT,
	@MaxRetainedRuns INT,
	@PartitionWarningPct TINYINT,
	@PhysicalPartitionCount INT,
	@PartitionsToAdd INT
)
RETURNS TABLE
AS
RETURN
(
	SELECT
		@ProjectedRetainedRuns AS ProjectedRetainedRuns,
		@MaxRetainedRuns AS MaxRetainedRuns,
		CONVERT(INT, CEILING(@MaxRetainedRuns * @PartitionWarningPct / 100.0))
			AS WarningRunCount,
		CONVERT(BIT, CASE
			WHEN @ProjectedRetainedRuns >=
				CEILING(@MaxRetainedRuns * @PartitionWarningPct / 100.0)
			THEN 1 ELSE 0 END) AS IsAtOrAboveWarning,
		CONVERT(BIT, CASE WHEN @ProjectedRetainedRuns > @MaxRetainedRuns
			THEN 1 ELSE 0 END) AS ExceedsConfiguredRetainedRuns,
		@PhysicalPartitionCount AS PhysicalPartitionCount,
		@PartitionsToAdd AS PartitionsToAdd,
		CONVERT(INT, 15000) AS SqlServerPartitionLimit,
		CONVERT(INT, 10) AS ReservedPartitionHeadroom,
		CONVERT(INT, 14990) AS OperationalPartitionLimit,
		CONVERT(BIT, CASE
			WHEN CONVERT(BIGINT, @PhysicalPartitionCount) + @PartitionsToAdd > 14990
			THEN 1 ELSE 0 END) AS ExceedsOperationalPartitionLimit,
		CONVERT(BIT, CASE
			WHEN @ProjectedRetainedRuns <= @MaxRetainedRuns
				AND CONVERT(BIGINT, @PhysicalPartitionCount) + @PartitionsToAdd <= 14990
			THEN 1 ELSE 0 END) AS CanAllocate
);

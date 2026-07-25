/*
	Partition Scheme for RunID-based Partitioning
	Maps all partitions to PRIMARY filegroup for simplicity
	Can be modified to use multiple filegroups for performance
*/

IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'PS_RunID')
BEGIN
	-- Get the number of partitions from the function
	DECLARE @PartitionCount INT;
	SELECT @PartitionCount = fanout 
	FROM sys.partition_functions 
	WHERE name = 'PF_RunID';

	-- Create partition scheme (all on PRIMARY for initial setup)
	CREATE PARTITION SCHEME PS_RunID
	AS PARTITION PF_RunID
	ALL TO ([PRIMARY]);

	PRINT 'Partition Scheme PS_RunID created with ' + CAST(@PartitionCount AS VARCHAR(10)) + ' partitions on PRIMARY';
END
ELSE
BEGIN
	PRINT 'Partition Scheme PS_RunID already exists';
END
GO

/*
	Partition Function for RunID-based Partitioning
	Creates a partition function using INT for runID with RIGHT range
	Initial setup creates partitions for runIDs 1-100 with room for extension
*/

IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'PF_RunID')
BEGIN
	CREATE PARTITION FUNCTION PF_RunID (INT)
	AS RANGE RIGHT FOR VALUES (
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
		11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
		21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
		31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
		41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
		51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
		61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
		71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
		81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
		91, 92, 93, 94, 95, 96, 97, 98, 99, 100
	);

	PRINT 'Partition Function PF_RunID created with 101 partitions (runID 1-100 + overflow)';
END
ELSE
BEGIN
	PRINT 'Partition Function PF_RunID already exists';
END
GO

/*
    Bounded, read-only QueryVault smoke workload for Voyager 2.
    Expected runtime: about 5 seconds. Targets StackOverflow2013 only.
*/

USE [StackOverflow2013];
GO

SET NOCOUNT ON;
SET DEADLOCK_PRIORITY LOW;
SET LOCK_TIMEOUT 5000;

DECLARE @Iteration INT = 0;
DECLARE @PostID INT;
DECLARE @Sink BIGINT;

WHILE @Iteration < 40
BEGIN
    SET @PostID = 4 + ((@Iteration * 265443) % 21190000);

    SELECT /* QueryVault smoke: StackOverflow point lookup */
        @Sink = CONVERT(BIGINT, p.Id) + p.Score
    FROM dbo.Posts AS p
    WHERE p.Id = @PostID
    OPTION (MAXDOP 1);

    SELECT /* QueryVault smoke: StackOverflow bounded range */
        @Sink = COUNT_BIG(*) + COALESCE(SUM(CONVERT(BIGINT, p.Score)), 0)
    FROM dbo.Posts AS p
    WHERE p.Id BETWEEN @PostID AND @PostID + 500
    OPTION (MAXDOP 1);

    WAITFOR DELAY '00:00:00.050';
    SET @Iteration += 1;
END;
GO

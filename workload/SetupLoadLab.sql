/* Explicit, bounded setup of a NEW lab source. Execute in master as a lab administrator.
   Refuses an existing database to prevent changing an unrelated environment. */
:on error exit
IF DB_ID(N'QueryVaultLoadLab') IS NOT NULL
    THROW 51210, 'QueryVaultLoadLab already exists. Review it rather than rerunning setup.', 1;
CREATE DATABASE QueryVaultLoadLab;
GO
ALTER DATABASE QueryVaultLoadLab SET QUERY_STORE = ON;
ALTER DATABASE QueryVaultLoadLab SET QUERY_STORE
    (OPERATION_MODE=READ_WRITE, QUERY_CAPTURE_MODE=ALL, INTERVAL_LENGTH_MINUTES=1,
     DATA_FLUSH_INTERVAL_SECONDS=60, MAX_STORAGE_SIZE_MB=128);
GO
USE QueryVaultLoadLab;
GO
CREATE TABLE dbo.ProbeData
(
    ID INT NOT NULL CONSTRAINT PK_ProbeData PRIMARY KEY CLUSTERED,
    Bucket INT NOT NULL,
    Amount DECIMAL(12,2) NOT NULL,
    Padding CHAR(200) NOT NULL
);
WITH digits AS (SELECT n FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
numbers AS
(
    SELECT TOP (50000) ROW_NUMBER() OVER (ORDER BY a.n,b.n,c.n,d.n,e.n) AS n
    FROM digits AS a CROSS JOIN digits AS b CROSS JOIN digits AS c CROSS JOIN digits AS d CROSS JOIN digits AS e
)
INSERT dbo.ProbeData(ID,Bucket,Amount,Padding)
SELECT n,n%100,CONVERT(DECIMAL(12,2),n%1000)/10.0,REPLICATE('x',200) FROM numbers;
CREATE NONCLUSTERED INDEX IX_ProbeData_Bucket ON dbo.ProbeData(Bucket) INCLUDE(Amount);
CREATE TABLE dbo.QueryVaultLabMarker (Marker NVARCHAR(100) NOT NULL PRIMARY KEY);
INSERT dbo.QueryVaultLabMarker VALUES(N'QueryVault bounded load lab v1');
GO
CREATE OR ALTER PROCEDURE dbo.qv_lab_probe @Bucket INT, @Variant NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Variant NOT IN (N'baseline',N'regressed') OR @Bucket NOT BETWEEN 0 AND 99
        THROW 51211, 'Invalid bounded workload parameters.', 1;
    /* Both variants return the same answer because Bucket is nonnegative.
       Recompilation simplifies the baseline predicate; ABS impairs the regression predicate.
       Verify actual plans and timing on your engine; the difference is not guaranteed. */
    SELECT SUM(Amount) AS TotalAmount
    FROM dbo.ProbeData
    WHERE CASE WHEN @Variant=N'regressed' THEN ABS(Bucket) ELSE Bucket END=@Bucket
    OPTION(RECOMPILE,MAXDOP 1);
END;
GO
CREATE OR ALTER PROCEDURE dbo.qv_lab_sort @Bucket INT, @Variant NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Variant NOT IN (N'baseline',N'regressed') OR @Bucket NOT BETWEEN 0 AND 99
        THROW 51212, 'Invalid bounded sort parameters.', 1;
    /* Equivalent ordered rows; the expression can require an explicit sort.
       No assertion of tempdb spill or memory pressure is implied. */
    SELECT TOP (1000) ID,Bucket,Amount
    FROM dbo.ProbeData
    WHERE Bucket>=@Bucket
    ORDER BY CASE WHEN @Variant=N'regressed' THEN ABS(Bucket) ELSE Bucket END,ID
    OPTION(RECOMPILE,MAXDOP 1);
END;
GO

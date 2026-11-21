/* Disposable SQL lab only. Prove a NULL preview flag cannot delete an eligible
   archive or damage an existing caller transaction. Fixture changes roll back. */
:on error exit
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

CREATE TABLE #PurgeInputCallerWork (ID int NOT NULL);
BEGIN TRANSACTION;
BEGIN TRY
    INSERT #PurgeInputCallerWork VALUES (1);
    DECLARE @Name sysname=CONCAT(N'__PurgeInput_', @@SPID);
    DECLARE @RunID int;
    DECLARE @Rejected bit=0;
    INSERT dbo.DatabaseConfig(DatabaseName,ServerName,AutoDeleteEnabled,DefaultRetentionDays)
    VALUES (@Name,@@SERVERNAME,1,1);

    SELECT TOP (1) @RunID=CONVERT(int,prv.value)
    FROM sys.partition_range_values AS prv
    JOIN sys.partition_functions AS pf ON pf.function_id=prv.function_id
    WHERE pf.name=N'PF_RunID'
      AND CONVERT(int,prv.value) BETWEEN 20 AND 2147483645
      AND EXISTS (SELECT 1 FROM sys.partition_range_values AS nx
                  WHERE nx.function_id=prv.function_id
                    AND CONVERT(int,nx.value)=CONVERT(int,prv.value)+1)
      AND NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=CONVERT(int,prv.value))
    ORDER BY CONVERT(int,prv.value) DESC;
    IF @RunID IS NULL THROW 51540, 'No unused input-validation boundary.', 1;

    SET IDENTITY_INSERT dbo.RunMetadata ON;
    INSERT dbo.RunMetadata
        (RunID,RunName,SourceDatabaseName,StartDateTime,EndDateTime,RunStatus,DoNotDelete,RetentionDate)
    VALUES (@RunID,N'Purge NULL flag fixture',@Name,'1899-01-01','1899-01-02',N'Completed',0,'1900-01-01');
    SET IDENTITY_INSERT dbo.RunMetadata OFF;

    BEGIN TRY
        EXEC dbo.usp_PurgeExpiredArchives @AsOfDateTime='1900-01-02', @DryRun=NULL;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE N'%DryRun cannot be NULL;%'
            THROW;
        SET @Rejected=1;
    END CATCH;
    IF @Rejected=0 THROW 51541, 'Purge accepted NULL DryRun.', 1;
    IF @@TRANCOUNT<>1 OR XACT_STATE()<>1
        THROW 51542, 'NULL rejection damaged the caller transaction.', 1;
    IF (@@OPTIONS & 16384)=0
        THROW 51546, 'NULL rejection did not restore caller XACT_ABORT ON.', 1;
    IF NOT EXISTS (SELECT 1 FROM #PurgeInputCallerWork WHERE ID=1)
        THROW 51543, 'NULL rejection rolled back earlier caller work.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID)
        THROW 51544, 'NULL flag deleted an eligible run.', 1;

    EXEC dbo.usp_PurgeExpiredArchives @AsOfDateTime='1900-01-02', @DryRun=1;
    IF NOT EXISTS (SELECT 1 FROM dbo.RunMetadata WHERE RunID=@RunID)
        THROW 51545, 'Explicit preview deleted an eligible run.', 1;

    ROLLBACK;
    SELECT N'PASS' AS TestResult, N'NULL purge flag fails closed; explicit preview preserves data' AS Validated;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    BEGIN TRY SET IDENTITY_INSERT dbo.RunMetadata OFF; END TRY BEGIN CATCH END CATCH;
    THROW;
END CATCH;

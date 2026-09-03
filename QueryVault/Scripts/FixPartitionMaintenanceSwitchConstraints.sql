/*
    Removes legacy tautological RunID check constraints from maintenance
    tables. SQL Server cannot semantically validate those constraints during
    ALTER TABLE ... SWITCH, so they prevent retention cleanup.
*/

SET NOCOUNT ON;

DECLARE @Constraints TABLE
(
    TableName SYSNAME NOT NULL,
    ConstraintName SYSNAME NOT NULL
);

INSERT @Constraints (TableName, ConstraintName)
VALUES
    (N'query_store_query', N'CK_query_store_query_PartitionMaintenance'),
    (N'query_store_query_text', N'CK_query_store_query_text_PartitionMaintenance'),
    (N'query_store_plan', N'CK_query_store_plan_PartitionMaintenance'),
    (N'query_store_runtime_stats', N'CK_query_store_runtime_stats_PartitionMaintenance'),
    (N'query_store_runtime_stats_interval', N'CK_query_store_runtime_stats_interval_PartitionMaintenance'),
    (N'query_store_wait_stats', N'CK_query_store_wait_stats_PartitionMaintenance');

DECLARE @TableName SYSNAME;
DECLARE @ConstraintName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

DECLARE constraint_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT TableName, ConstraintName
FROM @Constraints;

OPEN constraint_cursor;
FETCH NEXT FROM constraint_cursor INTO @TableName, @ConstraintName;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(
            N'dbo.' + QUOTENAME(@TableName + N'_PartitionMaintenance')
        )
          AND name = @ConstraintName
    )
    BEGIN
        SET @Sql = N'ALTER TABLE dbo.'
            + QUOTENAME(@TableName + N'_PartitionMaintenance')
            + N' DROP CONSTRAINT ' + QUOTENAME(@ConstraintName) + N';';
        EXEC sys.sp_executesql @Sql;
    END;

    FETCH NEXT FROM constraint_cursor INTO @TableName, @ConstraintName;
END;

CLOSE constraint_cursor;
DEALLOCATE constraint_cursor;

SELECT COUNT(*) AS RemainingLegacyConstraintCount
FROM sys.check_constraints
WHERE name LIKE N'CK_query_store%_PartitionMaintenance';
GO

/*
    Bounded, read-only QueryVault smoke workload for Voyager 2.
    Expected runtime: about 5 seconds. Targets WideWorldImporters only.
*/

USE [WideWorldImporters];
GO

SET NOCOUNT ON;
SET DEADLOCK_PRIORITY LOW;
SET LOCK_TIMEOUT 5000;

DECLARE @Iteration INT = 0;
DECLARE @OrderID INT;
DECLARE @CustomerID INT;
DECLARE @Sink BIGINT;

WHILE @Iteration < 80
BEGIN
    SET @OrderID = 1 + ((@Iteration * 997) % 73595);
    SET @CustomerID = 1 + ((@Iteration * 31) % 1000);

    SELECT /* QueryVault smoke: WWI order and customer lookup */
        @Sink = CONVERT(BIGINT, o.OrderID) + c.CustomerID
    FROM Sales.Orders AS o
    INNER JOIN Sales.Customers AS c
        ON c.CustomerID = o.CustomerID
    WHERE o.OrderID = @OrderID;

    SELECT /* QueryVault smoke: WWI order-line aggregate */
        @Sink = COUNT_BIG(*) + COALESCE(SUM(CONVERT(BIGINT, ol.Quantity)), 0)
    FROM Sales.OrderLines AS ol
    WHERE ol.OrderID = @OrderID;

    SELECT /* QueryVault smoke: WWI customer order history */
        @Sink = COUNT_BIG(*)
    FROM Sales.Orders AS o
    WHERE o.CustomerID = @CustomerID
      AND o.OrderDate >= DATEFROMPARTS(2015, 1, 1)
      AND o.OrderDate < DATEFROMPARTS(2016, 1, 1);

    WAITFOR DELAY '00:00:00.050';
    SET @Iteration += 1;
END;
GO

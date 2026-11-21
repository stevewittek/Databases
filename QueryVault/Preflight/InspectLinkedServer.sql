/*
    Local catalog inspection only: SQL Server 2016+ or Azure SQL Managed Instance.
    Supply @LinkedServerName as an nvarchar(max) command parameter in this batch.
    Do not substitute it into SQL text. This script has no default target and no GO.
    No remote connection is attempted. See docs/LINKED_SERVER_PREFLIGHT.md.
*/
IF @LinkedServerName IS NULL
   OR DATALENGTH(@LinkedServerName) = 0
   OR DATALENGTH(@LinkedServerName) > 256
   OR DATALENGTH(@LinkedServerName) <> DATALENGTH(LTRIM(RTRIM(@LinkedServerName)))
BEGIN
    ;THROW 51650, 'Supply one exact linked-server name of 1 to 128 UTF-16 code units, without surrounding spaces.', 1;
END;

-- Snapshot only the requested entry and only fields approved for this report.
DECLARE @Link TABLE
(
    ServerID INT NOT NULL,
    Product NVARCHAR(128) NULL,
    Provider NVARCHAR(128) NULL,
    DataAccessEnabled BIT NULL,
    IncomingRpcEnabled BIT NULL,
    OutgoingRpcEnabled BIT NULL,
    CollationCompatible BIT NULL,
    UsesRemoteCollation BIT NULL,
    LazySchemaValidation BIT NULL,
    ConnectTimeoutSeconds INT NULL,
    QueryTimeoutSeconds INT NULL
);

INSERT INTO @Link
SELECT server_id, product, provider,
       is_data_access_enabled, is_remote_login_enabled, is_rpc_out_enabled,
       is_collation_compatible, uses_remote_collation, lazy_schema_validation,
       connect_timeout, query_timeout
FROM sys.servers
WHERE name COLLATE Latin1_General_100_BIN2 = @LinkedServerName COLLATE Latin1_General_100_BIN2
  AND DATALENGTH(name) = DATALENGTH(@LinkedServerName)
  AND server_id > 0
  AND is_linked = 1;

IF (SELECT COUNT(*) FROM @Link) <> 1
BEGIN
    ;THROW 51651, 'Exactly one visible standard linked server was not found. Check the exact name and metadata visibility; no remote test was performed.', 1;
END;

DECLARE @ServerID INT = (SELECT ServerID FROM @Link);
DECLARE @VisibleMappings INT,
        @VisiblePublicMappings INT,
        @VisibleSelfMappings INT,
        @VisibleStoredCredentialMappings INT;

-- Counts describe visible catalog rows, never effective identity or credential validity.
SELECT @VisibleMappings = COUNT(*),
       @VisiblePublicMappings = COALESCE(SUM(CASE WHEN local_principal_id = 0 THEN 1 ELSE 0 END), 0),
       @VisibleSelfMappings = COALESCE(SUM(CASE WHEN uses_self_credential = 1 THEN 1 ELSE 0 END), 0),
       @VisibleStoredCredentialMappings = COALESCE(SUM(CASE WHEN uses_self_credential = 0 THEN 1 ELSE 0 END), 0)
FROM sys.linked_logins
WHERE server_id = @ServerID;

SELECT
    N'LOCAL_CATALOG_ONLY' AS InspectionScope,
    CAST(0 AS BIT) AS CanStartCollection,
    CASE WHEN DataAccessEnabled = 0 THEN N'BLOCKED_DATA_ACCESS_DISABLED'
         WHEN @VisibleMappings = 0 THEN N'BLOCKED_NO_VISIBLE_MAPPING'
         ELSE N'REQUIRES_REMOTE_VALIDATION' END AS InspectionStatus,
    Product, Provider,
    DataAccessEnabled, IncomingRpcEnabled, OutgoingRpcEnabled,
    CollationCompatible, UsesRemoteCollation, LazySchemaValidation,
    ConnectTimeoutSeconds, QueryTimeoutSeconds,
    CASE WHEN ConnectTimeoutSeconds = 0 THEN N'INSTANCE_DEFAULT_NOT_READ' ELSE N'LINK_VALUE' END AS ConnectTimeoutSource,
    CASE WHEN QueryTimeoutSeconds = 0 THEN N'INSTANCE_DEFAULT_NOT_READ' ELSE N'LINK_VALUE' END AS QueryTimeoutSource,
    @VisibleMappings AS VisibleMappingCount,
    @VisiblePublicMappings AS VisiblePublicMappingCount,
    @VisibleSelfMappings AS VisibleSelfCredentialMappingCount,
    @VisibleStoredCredentialMappings AS VisibleStoredCredentialMappingCount,
    N'MAY_BE_FILTERED' AS MappingVisibility,
    CASE WHEN @VisiblePublicMappings > 0 THEN N'REVIEW_WILDCARD_MAPPING'
         ELSE N'NO_VISIBLE_WILDCARD_IS_NOT_PROOF_OF_ABSENCE' END AS MappingRisk,
    N'NOT_TESTED' AS RemoteConnectivity,
    N'NOT_ASSESSED' AS TlsValidation,
    N'NOT_ASSESSED' AS EffectiveExecutionIdentity,
    N'NOT_TESTED' AS QueryStoreAccess
FROM @Link;

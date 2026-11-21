/* Explicit DNS/IP and TCP port, not a connection string or named-instance discovery. */
CREATE TABLE dbo.CollectionEndpoint
(
    EndpointID INT IDENTITY(1,1) NOT NULL,
    ServerAddress NVARCHAR(255) NOT NULL,
    Port INT NOT NULL CONSTRAINT DF_CollectionEndpoint_Port DEFAULT 1433,
    CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_CollectionEndpoint_Created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CollectionEndpoint PRIMARY KEY CLUSTERED (EndpointID),
    CONSTRAINT UQ_CollectionEndpoint_AddressPort UNIQUE (ServerAddress, Port),
    CONSTRAINT CK_CollectionEndpoint_Port CHECK (Port BETWEEN 1 AND 65535),
    CONSTRAINT CK_CollectionEndpoint_Address CHECK
    (
        LEN(ServerAddress) > 0
        AND DATALENGTH(ServerAddress) = DATALENGTH(LTRIM(RTRIM(ServerAddress)))
        AND ServerAddress COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^-a-zA-Z0-9.:]%'
    )
);
GO

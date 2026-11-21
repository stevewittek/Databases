/* Additive remote source registry. Existing dbo.DatabaseConfig remains the V1 contract.
   SourceID identifies the registration; SourceEpoch changes after a confirmed reset/restore.
   No source is enabled by deployment. Password/token modes cannot be enabled yet. */
CREATE TABLE dbo.CollectionSource
(
    SourceID UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CollectionSource_ID DEFAULT NEWID(),
    SourceEpoch UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CollectionSource_Epoch DEFAULT NEWID(),
    EndpointID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    AuthenticationMode VARCHAR(16) NOT NULL CONSTRAINT DF_CollectionSource_Auth DEFAULT 'INTEGRATED',
    CredentialID UNIQUEIDENTIFIER NULL,
    PolicyID INT NULL,
    CollectionWindowMinutes INT NOT NULL CONSTRAINT DF_CollectionSource_Window DEFAULT 1440,
    IsEnabled BIT NOT NULL CONSTRAINT DF_CollectionSource_Enabled DEFAULT 0,
    CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_CollectionSource_Created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CollectionSource PRIMARY KEY CLUSTERED (SourceID),
    CONSTRAINT UQ_CollectionSource_Database UNIQUE (EndpointID, DatabaseName),
    CONSTRAINT FK_CollectionSource_Endpoint FOREIGN KEY (EndpointID) REFERENCES dbo.CollectionEndpoint(EndpointID),
    CONSTRAINT FK_CollectionSource_Credential FOREIGN KEY (CredentialID) REFERENCES dbo.CollectionCredential(CredentialID),
    CONSTRAINT FK_CollectionSource_Policy FOREIGN KEY (PolicyID) REFERENCES dbo.CollectionRetentionPolicy(PolicyID),
    CONSTRAINT CK_CollectionSource_Database CHECK (LEN(LTRIM(RTRIM(DatabaseName))) > 0),
    CONSTRAINT CK_CollectionSource_Auth CHECK (AuthenticationMode IN ('INTEGRATED', 'ENTRA', 'SQL')),
    CONSTRAINT CK_CollectionSource_Credential CHECK
    (
        (AuthenticationMode = 'SQL' AND CredentialID IS NOT NULL)
        OR (AuthenticationMode IN ('INTEGRATED', 'ENTRA') AND CredentialID IS NULL)
    ),
    CONSTRAINT CK_CollectionSource_Enrollment CHECK (IsEnabled = 0 OR AuthenticationMode = 'INTEGRATED'),
    CONSTRAINT CK_CollectionSource_Window CHECK (CollectionWindowMinutes BETWEEN 1 AND 525600)
);
GO

/* Proposed policy configuration. Not wired to the legacy purge procedure.
   NULL retention means no automatic expiry; no deletion enabled by installation. */
CREATE TABLE dbo.CollectionRetentionPolicy
(
    PolicyID INT IDENTITY(1,1) NOT NULL,
    PolicyName NVARCHAR(128) NOT NULL,
    RetentionDays INT NULL,
    AutoDeleteEnabled BIT NOT NULL CONSTRAINT DF_CollectionRetentionPolicy_Delete DEFAULT 0,
    CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_CollectionRetentionPolicy_Created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CollectionRetentionPolicy PRIMARY KEY CLUSTERED (PolicyID),
    CONSTRAINT UQ_CollectionRetentionPolicy_Name UNIQUE (PolicyName),
    CONSTRAINT CK_CollectionRetentionPolicy_Name CHECK (LEN(LTRIM(RTRIM(PolicyName))) > 0),
    CONSTRAINT CK_CollectionRetentionPolicy_Days CHECK (RetentionDays IS NULL OR RetentionDays BETWEEN 1 AND 36500),
    CONSTRAINT CK_CollectionRetentionPolicy_Delete CHECK (AutoDeleteEnabled = 0 OR RetentionDays IS NOT NULL)
);
GO

/* Credential enrollment metadata only. No secret or decryption key is stored here.
   Password enrollment is blocked until the per-installation AE setup in #49 exists. */
CREATE TABLE dbo.CollectionCredential
(
    CredentialID UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CollectionCredential_ID DEFAULT NEWID(),
    CredentialName NVARCHAR(128) NOT NULL,
    EnrollmentState VARCHAR(16) NOT NULL CONSTRAINT DF_CollectionCredential_State DEFAULT 'PENDING',
    CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_CollectionCredential_Created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CollectionCredential PRIMARY KEY CLUSTERED (CredentialID),
    CONSTRAINT UQ_CollectionCredential_Name UNIQUE (CredentialName),
    CONSTRAINT CK_CollectionCredential_Name CHECK (LEN(LTRIM(RTRIM(CredentialName))) > 0),
    CONSTRAINT CK_CollectionCredential_State CHECK (EnrollmentState IN ('PENDING', 'REVOKED'))
);
GO

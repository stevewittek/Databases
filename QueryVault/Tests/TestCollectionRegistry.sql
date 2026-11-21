/* Disposable database only. All valid fixture rows are rolled back. */
SET NOCOUNT ON;
SET XACT_ABORT OFF;
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @Suffix NVARCHAR(36) = CONVERT(NVARCHAR(36), NEWID());
    INSERT dbo.CollectionEndpoint(ServerAddress, Port) VALUES (N'registry-' + @Suffix, 14330);
    DECLARE @Endpoint INT = SCOPE_IDENTITY();
    INSERT dbo.CollectionEndpoint(ServerAddress, Port) VALUES
        (N'2001:db8::1', 14330), (N'sql.example.test', 14331), (N'192.0.2.1', 14332);
    INSERT dbo.CollectionRetentionPolicy(PolicyName) VALUES (N'test-' + @Suffix);
    DECLARE @Policy INT = SCOPE_IDENTITY();
    INSERT dbo.CollectionSource(EndpointID, DatabaseName, PolicyID) VALUES (@Endpoint, N'Example DB', @Policy);
    IF NOT EXISTS (SELECT 1 FROM dbo.CollectionSource WHERE EndpointID=@Endpoint AND IsEnabled=0
                   AND CollectionWindowMinutes=1440 AND SourceID<>SourceEpoch AND CredentialID IS NULL)
        THROW 51201, 'Source defaults are unsafe or identity is missing.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.CollectionRetentionPolicy WHERE PolicyID=@Policy AND AutoDeleteEnabled=0 AND RetentionDays IS NULL)
        THROW 51202, 'Retention was activated by default.', 1;

    BEGIN TRY
        INSERT dbo.CollectionEndpoint(ServerAddress,Port) VALUES (N'bad-port',65536);
        THROW 51203, 'Invalid port accepted.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    BEGIN TRY
        INSERT dbo.CollectionEndpoint(ServerAddress) VALUES (N'host;Password=bad');
        THROW 51204, 'Connection-string fragment accepted as host.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    BEGIN TRY
        INSERT dbo.CollectionSource(EndpointID,DatabaseName) VALUES (@Endpoint,N'   ');
        THROW 51205, 'Blank database accepted.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    BEGIN TRY
        INSERT dbo.CollectionSource(EndpointID,DatabaseName) VALUES (@Endpoint,N'Example DB');
        THROW 51206, 'Duplicate source registration accepted.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER() NOT IN (2601,2627) THROW; END CATCH;
    BEGIN TRY
        UPDATE dbo.CollectionRetentionPolicy SET AutoDeleteEnabled=1 WHERE PolicyID=@Policy;
        THROW 51207, 'Automatic expiry without retention accepted.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    BEGIN TRY
        UPDATE dbo.CollectionRetentionPolicy SET RetentionDays=0 WHERE PolicyID=@Policy;
        THROW 51208, 'Zero-day retention accepted.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    DECLARE @Credential UNIQUEIDENTIFIER=NEWID();
    INSERT dbo.CollectionCredential(CredentialID,CredentialName) VALUES (@Credential,N'pending-'+@Suffix);
    INSERT dbo.CollectionSource(EndpointID,DatabaseName,AuthenticationMode,CredentialID)
        VALUES (@Endpoint,N'Password DB','SQL',@Credential);
    BEGIN TRY
        UPDATE dbo.CollectionSource SET IsEnabled=1 WHERE EndpointID=@Endpoint AND DatabaseName=N'Password DB';
        THROW 51209, 'Unprovisioned password source enabled.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    BEGIN TRY
        INSERT dbo.CollectionSource(EndpointID,DatabaseName,AuthenticationMode,IsEnabled)
            VALUES (@Endpoint,N'Entra DB','ENTRA',1);
        THROW 51210, 'Unimplemented Entra mode enabled.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    BEGIN TRY
        UPDATE dbo.CollectionSource SET CredentialID=@Credential WHERE EndpointID=@Endpoint AND DatabaseName=N'Example DB';
        THROW 51211, 'Integrated source accepted password reference.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    BEGIN TRY
        UPDATE dbo.CollectionCredential SET EnrollmentState='READY' WHERE CredentialID=@Credential;
        THROW 51212, 'Unimplemented secret enrollment marked ready.', 1;
    END TRY BEGIN CATCH IF ERROR_NUMBER()<>547 THROW; END CATCH;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id IN
        (OBJECT_ID(N'dbo.CollectionCredential'),OBJECT_ID(N'dbo.CollectionEndpoint'),OBJECT_ID(N'dbo.CollectionSource'))
        AND name IN (N'Password',N'ConnectionString',N'PrivateKey',N'AccessToken'))
        THROW 51213, 'Registry unexpectedly contains a secret column.', 1;
    ROLLBACK;
    SELECT N'PASS' AS result, N'Registry defaults, constraints, identity and credential enrollment gates' AS validated;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
GO

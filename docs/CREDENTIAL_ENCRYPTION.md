# Credential encryption bootstrap

Credentials belong in QueryVault, encrypted. The installer generates a unique
column encryption key on the collector computer and wraps it with a private key
in that collector identity's Windows certificate store. SQL Server receives the
wrapped key and randomized ciphertext. There is no shared key in the download.

This increment includes a **Windows-first installer candidate**, not a verified
cross-platform credential subsystem. The archive may be SQL Server or Azure SQL
Database; the certificate-store collector must run on Windows. No certificate,
SQL credential, cloud resource or production connection was created during
development on the Mac.

## What deploys

Downloaded bundles include these scripts under `setup/`. Keep that directory
beside `QueryVault.dacpac` and `manifest.json`; in a source checkout they remain
under `QueryVault/Security/`. The initializer detects either layout and refuses a
backup path inside that installation. Schema deployment and encryption setup are
still separate explicit steps; a single-command installer orchestration is not
implemented yet.

The ordinary SQL/DACPAC deployment creates `dbo.CollectionCredential` registration
metadata and the connection/source tables. It contains no password column. The
separate initializer creates `dbo.CollectionCredentialSecret` with both `UserName`
and `SecretValue` encrypted using randomized Always Encrypted from their first
creation. There is no intermediate plaintext table or fallback to SQL-side
decryption. `QV_CredentialCMK` and `QV_CredentialCEK` are metadata names, not shared
key values.

Until initialization succeeds, credential enrollment fails. Enrollment does not
mark a registration ready or enable a source. Collector consumption, authentication
and native acceptance remain tracked by #49 and #39. The existing metadata
`PENDING` state intentionally continues to mean not yet accepted for production
collection, even when encrypted secret material has been enrolled.

## Installer contract

1. Inventory Windows PowerShell/PowerShell and the `SqlServer` module first. These
   scripts require module 22 or newer with `Microsoft.Data.SqlClient`; they never
   install modules themselves. Check current module/driver support before release.
2. Run a separate provisioning PowerShell process as the actual collector Windows
   account with its user profile loaded. Pass that account's SID explicitly; a
   different SID fails before connecting. Use a dedicated account, not an ordinary
   interactive administrator account. Temporary archive schema/key permissions are
   needed for bootstrap and must be removed after installation.
3. Deploy the registry to an authorized archive with a trusted TLS certificate.
   There is no `TrustServerCertificate` bypass. SQL Server integrated authentication
   is the default for the archive connection. `-ArchiveCredential (Get-Credential)`
   supports a separately authorized SQL account, including Azure SQL. Entra access
   tokens for installer authentication are not implemented in this increment.
4. Initialize encryption with a **new, absolute backup directory outside the
   repository**. Its parent must exist and may not traverse reparse points. The
   new directory receives an ACL for the collector SID and LocalSystem before key
   material is written. The generated CurrentUser CSP private-key file also gets
   an explicit protected ACL for those identities. Supply a separate recovery PFX password as a SecureString,
   or answer the secure prompt; never put a plaintext password in a command.
5. Initialization exports an AES-256/SHA-256 password-protected PFX and verifies that it contains
   the generated private key. Move/copy this backup to independently protected
   recovery storage and keep the PFX password separately. A backup beside the
   collector on its only disk is not disaster recovery.
6. Keep the nonsecret `installation.json` receipt securely. It contains the
   expected certificate thumbprint and collector SID. Enrollment trusts this
   locally approved thumbprint, not a key path supplied by the database.

Example commands, **for a separately authorized test environment only**:

```powershell
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
./QueryVault/Security/InitializeCollectorEncryption.ps1 `
  -Server 'tcp:sql.example.internal,1433' -Database 'QueryVaultTest' `
  -CollectorSid $sid -BackupDirectory 'D:\ProtectedRecovery\QueryVault-Test-01'

# First register a pending CredentialID in dbo.CollectionCredential.
# Use the receipt's real certificate thumbprint and the registration's real ID.
$sourceCredential = Get-Credential -Message 'Read-only source database credential'
./QueryVault/Security/SetCollectorCredential.ps1 `
  -Server 'tcp:sql.example.internal,1433' -Database 'QueryVaultTest' `
  -CollectorSid $sid -CertificateThumbprint '<40-character thumbprint>' `
  -CredentialID '<registration UUID>' -SourceCredential $sourceCredential
```

The enrollment script uses typed parameters with `ForceColumnEncryption=true`
for username and password, plus a client-side trusted master-key-path allowlist.
The allowlist is bound to the opened connection's effective `DataSource` before
any encrypted command, so a supplied server alias cannot leave the actual lookup
without a trust entry. Idle connection recovery is disabled for these short
provisioning connections; retry requires a fresh process and a fresh trust binding.
Unexpected plaintext schema or a different key path fails instead of transmitting
plaintext. It never writes a password into SQL text, connection strings, arguments,
reports or generated files. The collector must follow the same trust and logging
rules. Plaintext necessarily exists briefly in the authorized client process;
the script clears the unmanaged password buffer, but managed .NET string memory
cannot be guaranteed wiped immediately.

## Failure, recovery and rotation

The initializer refuses any preexisting encryption object or secret table. It
does not replace keys on retry. Database key metadata and the encrypted table are
created in one transaction. If provisioning fails, keep the protected local
certificate/PFX for inspection; do not delete them based on an ambiguous network
result. Inspect database state before deciding whether to resume or restore.

Restore the archive together with the matching key backup into the authorized
collector identity's certificate store before decrypting credentials. Loss of the
key and its backup makes encrypted credentials unrecoverable; they must then be
re-entered from their original authority. Automatic key rotation, credential
replacement, multi-host key distribution and account migration are **not**
implemented. They require separate tested procedures before general release.

Always Encrypted protects a database reader who lacks the key, including a
database-only administrator. It does not make the application unhackable: a host
administrator or attacker controlling the collector account/process or recovery
key can reach plaintext. Ordinary endpoint/database configuration remains visible
to principals with table read permission; only the credential fields are encrypted.

## Acceptance still required on Windows

- Unique keys across two fresh installations; exact collector identity and
  private-key ACL checks, including denial to an unrelated standard user.
- SQL Server and Azure SQL archive initialization; trusted-TLS rejection tests.
- Insert synthetic credentials, read ciphertext without keys, decrypt with the
  authorized client, and prove wrong key/identity/schema cannot enroll plaintext.
- Restore the PFX and archive on an isolated replacement host; test missing or
  wrong backup password/key and interrupted provisioning.
- Least-privilege post-install grants, rotation and retention of key backups.
- Collector fetch/use and redacted error handling; sources remain disabled until
  this entire path is accepted.
- Verify actual private-key use under the intended identity, not merely
  `HasPrivateKey` metadata. Exercise backup recovery with a cryptographic roundtrip
  on the replacement host; test server aliases and trusted-key-path lookup.
- Reject malicious schema/key substitution. Bind each credential to a locally
  approved endpoint before a collector uses it: encrypted storage alone cannot
  prevent an archive administrator from remapping a credential to another server.

The offline test `QueryVault/Tests/TestCollectorEncryptionScripts.ps1` validates
PowerShell parsing and fail-closed preflight only. It is not cryptographic or
database integration evidence, so #49 must remain open.

References: [Always Encrypted key management](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/overview-of-key-management-for-always-encrypted),
[SqlClient Always Encrypted, certificate provider, forced parameter encryption and trusted key paths](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql/sqlclient-support-always-encrypted).

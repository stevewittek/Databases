# Connection registry foundation

The default schema now includes four additive tables. The existing
`DatabaseConfig` table and local T-SQL collector remain separate during migration.

| Table | Stores |
| --- | --- |
| `CollectionEndpoint` | DNS/IP address and explicit TCP port, shared by registered databases |
| `CollectionSource` | Exact database name, stable source UUID, epoch UUID, authentication mode, credential reference, policy and collection-window length |
| `CollectionCredential` | Credential label and enrollment metadata; never a password or key |
| `CollectionRetentionPolicy` | Configurable retention days and explicit automatic-delete opt-in |

Source registrations start disabled. The initial window length is 1,440 minutes;
this field is a collection-window setting, not an installed scheduler. The registry
does not yet drive the experimental exporter or legacy archive procedure (#39).
SQL and Entra source modes cannot be enabled in this increment. Credential enrollment
metadata cannot be marked ready before the collector integration has been validated.

Passwords and usernames belong in an Always Encrypted companion table installed
by the per-installation credential bootstrap (#49), not in these four tables.
The encrypted table must never be created in plaintext and encrypted afterward.
No private key or sample password is distributed in the DACPAC. See
`CREDENTIAL_ENCRYPTION.md` for implementation and remaining native-platform checks.

Explicit addresses accept DNS names, IPv4 and unbracketed IPv6. Named instances
must be resolved to an address and fixed port during enrollment. This avoids SQL
Browser discovery and opaque connection strings. Each connection must still use
a driver connection-string builder, validated TLS and parameterized SQL. Database
names are exact identifiers and must never be concatenated into executable SQL.

The registry is not granted to the Grafana reporting role. Administrators must
grant collector/configuration permissions separately from reporting permissions.
Metadata is not a password vault and is not itself encrypted by Always Encrypted.
Database users may see endpoint names according to their normal database access.

## Installation and tests

Both canonical SQL project manifests and the SQL/PowerShell deployment paths
include these tables. Portable DACPACs remain fresh-install-only. Existing archive
table changes still require explicit migrations (#55); the new protection-note migration
only adds a nullable column and does not alter pins or expiry dates.

`TestCollectionRegistry.sql` checks invalid ports, connection-string fragments,
blank/duplicate databases, authentication consistency, disabled defaults and
blocked secret enrollment in a disposable database. It does not prove live
connections, key provisioning, decryption or Azure runtime compatibility.

Retention tables are configuration only until the new ingestion/policy bridge is
implemented. No new purge schedule is installed. Pin/unpin uses
`dbo.usp_SetRunProtection` with a required explanatory note, preserving prior
`Comments` and expiry. Current pin notes record the latest reason, not an audit
history. Full history and retrospective policy changes remain explicit follow-ups.

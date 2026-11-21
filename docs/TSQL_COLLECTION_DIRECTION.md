# T-SQL-first collection direction

Owner decision recorded November 21, 2026: keep collection entirely in T-SQL
using linked servers/OPENQUERY first; revisit Azure archive limitations. This
supersedes the proposed separate collector application for the first release.
Implementation is tracked in #57 under #7/#10/#39. This document is a design
update, not evidence that remote collection or linked-server setup is implemented.

## Initial topology

A local SQL Server instance executes collection stored procedures. SQL Server
Agent is the proposed scheduler. Sources are explicit databases on that instance
or reachable configured linked servers; no automatic scan of every database.
QueryVault retains the registry, source identity, archived periods and per-source
retention configuration. Existing pin/expiry/concurrency fixes remain applicable.

The recommended first archive is on that SQL Server instance. Azure SQL Database
cannot host linked servers. SQL Server can act as the collection host for remote
sources; Azure SQL source compatibility must be proven independently in #38.
Azure SQL as an archive is still under review: retaining that destination may
require a separate SQL Server execution host and a different ingestion/transaction
contract. Do not confuse an Azure source with an Azure-hosted collector/archive,
or infer support from a compiled Azure DACPAC. Managed Instance is a distinct
product with its own constraints, not an implicit substitute for Azure SQL Database.

## Credential decision awaiting owner

The prior design put Always Encrypted credentials in QueryVault and the private
key in a client collector's certificate store. Always Encrypted depends on an
AE-capable client; T-SQL cannot decrypt those columns to supply a linked login.
The existing Windows bootstrap/enrollment scripts are therefore deferred
experimental work, not the credential solution for the selected T-SQL path.

Recommendation: keep source passwords in SQL Server's encrypted linked-server
login mappings and store the approved link reference in QueryVault. SQL Server
protects linked passwords with its service master key. This avoids duplicating
password material, but changes the owner's earlier password-table requirement.
The owner has been asked to confirm it; no acceptance is inferred from choosing
T-SQL. SQL Server administrators are trusted in this design.

Alternative: retain encrypted password material in QueryVault using a reviewed
SQL-side key hierarchy and restricted provisioning procedures. This is a different
security boundary from Always Encrypted and does not inherently hide plaintext
from privileged SQL Server/host administrators. Linked-server authentication still
requires a configured login mapping; it cannot directly consume an arbitrary
ciphertext column. Design key backup/recovery, rotation, provisioning permissions
and potential duplication before implementing this alternative.

Neither option is currently implemented or approved by this document. No plaintext
fallback, credential creation, link changes or real-source connections are allowed
as a side effect of this planning update. Credential and endpoint policy remain
#49/#54; real installation and recovery tests are required for the selected design.

## Transport and acceptance plan

- Extend the registry to distinguish same-instance and approved linked-server
  routes. Existing four tables are a foundation; no linked-server binding exists
  yet. Define the database/catalog and execution identity unambiguously.
- Verify the link's actual endpoint, provider, TLS configuration, catalog and login
  mapping against the registration. Limit who can change either side. No default
  remote login for unrelated local users or automatic permission broadening.
- Discover source catalog capabilities, select explicit fields, and push complete
  interval predicates to the remote query. Bound batches, bytes and duration.
- OPENQUERY's query string is limited to 8 KB and its arguments cannot be variables.
  Use fixed reviewed templates, quoted validated identifiers and typed predicate
  literals. Never accept arbitrary SQL or interpolate passwords. Test complete
  Unicode query text and plan XML without truncation across the selected provider.
- Stage remote reads before the local archive commit. Do not assume remote reads
  form one consistent snapshot or that distributed transaction promotion is safe.
  Source resets/cleanup, changing metadata and coverage gaps need explicit handling.
- Preserve contributor multiplicity. Atomically commit validated facts, receipt
  and checkpoint locally; interruption must neither lose intervals nor double-count
  successful retries. One failed source must not stop every other source.
- Test separate disposable SQL instances with the intended provider and scoped
  identity. Record memory/log cost, network bytes, source CPU/reads, timeout/failure
  behavior and pin safety. Loopback and prior local-capture tests are insufficient.
- Scheduler day boundaries, missed windows, scalable physical partitioning and
  legacy retention migration remain separate decisions. Do not activate jobs yet.

## Work retained and work deferred

PR #56's source registry, reporting integration, retention safety and prior SQL
validation remain useful. Its recorded checks describe commit 0c0b80a and do not
prove linked-server transport. The Python exporter and Windows AE scripts remain
available as experimental artifacts; no additional final collector runtime work
should proceed from their earlier plans. The updated Codex packet 3 routes work
to this T-SQL design and explicitly blocks credential-dependent implementation.

## Primary references

- [Linked-server availability and providers](https://learn.microsoft.com/en-us/sql/relational-databases/linked-servers/linked-servers-database-engine)
- [OPENQUERY command limits](https://learn.microsoft.com/en-us/sql/t-sql/functions/openquery-transact-sql)
- [Always Encrypted client and key boundary](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/always-encrypted-database-engine)
- [SQL Server key hierarchy and linked-server passwords](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/sql-server-and-database-encryption-keys-database-engine)

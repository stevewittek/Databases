# Local linked-server inspection (#57)

`QueryVault/Preflight/InspectLinkedServer.sql` inspects one explicitly named link on the local SQL Server instance. It makes no connection through the link and changes no server configuration, login, permissions, data, or deployment objects. Its only insert populates an in-memory table variable. It is separate from the direct source readiness check and does not resolve credential enrollment (#49).

Use an existing authorized connection to SQL Server 2016 or later, or Azure SQL Managed Instance. Azure SQL Database is not a supported host for this inspection. The script reads `sys.servers` and `sys.linked_logins`, restricted to the requested link; it does not inventory other links. These catalog views and their documented columns apply to SQL Server and Managed Instance. [Microsoft: sys.servers](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-servers-transact-sql), [Microsoft: sys.linked_logins](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-linked-logins-transact-sql).

## Supplying the name

Bind `@LinkedServerName` as an `nvarchar(max)` command parameter and execute the file as one batch. Using a wide input preserves the script's overlength rejection instead of silently truncating the requested name. Do not use SQLCMD text substitution or concatenate a supplied name into SQL. In a query editor, a trusted operator can place a declaration immediately before the file contents, in the same batch:

```sql
DECLARE @LinkedServerName NVARCHAR(MAX) = N'ExistingLinkAlias';
-- Paste InspectLinkedServer.sql below this line; do not insert GO.
```

The name must match exactly, including case and accents. Empty, null, overlength, and surrounding-space input is rejected. SQL syntax characters inside a bound value remain data; they cannot invoke commands. The local server, old-style remote-server entries, missing entries, invisible entries, and an ambiguous match cannot produce a report. Errors 51650 and 51651 contain no supplied name or connection details. Other catalog permission failures propagate; a runner must treat every error or missing result as an unsuccessful inspection. Run this standalone, outside an application transaction; it is not a transaction-management procedure.

## Reading the report

The report includes the product/provider labels, distributed-query and RPC flags, collation flags, lazy schema validation, configured timeouts, and counts of visible mapping categories. A zero timeout inherits an instance setting; the script deliberately does not read that setting or interpret zero as unlimited. [Microsoft: linked-server option semantics](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-serveroption-transact-sql).

`CanStartCollection` is always false. Disabled data access and no visible mappings produce blocking statuses. Other configurations still require an independently authorized remote validation. RPC flags are observations, not requirements or recommendations to enable RPC. Provider labels do not prove that a provider is installed, loadable, current, or securely configured.

Mapping counts concern only rows visible to the inspecting identity. A wildcard/public mapping deserves review; it does not establish that every login can connect. Self-credential mapping does not prove delegation works. Stored-credential mapping does not prove a valid password exists or identify the effective remote user. The script does not retrieve connection strings, remote usernames, passwords, endpoint addresses, catalog names, or local principal names. TLS, effective execution identity, connectivity, and Query Store access remain explicitly unassessed or untested.

Catalog permissions can hide entries. Microsoft documents that removing a default/public mapping restricts linked-server visibility; elevated permissions or fixed server roles can reveal additional entries. SQL Server 2022 and later require `VIEW SERVER SECURITY STATE` for these views. This tool does not grant permissions or request elevation automatically. A missing visible link or mapping is not proof that it does not exist. [Microsoft: sys.servers permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-servers-transact-sql#permissions), [Microsoft: sys.linked_logins permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-linked-logins-transact-sql#permissions).

The two catalog reads are observations made during this execution, not an atomic configuration snapshot or authorization for later collection. Configuration and permissions can change afterward. Any future collector must validate its actual execution context separately. This inspection neither changes transaction promotion/DTC settings nor performs impersonation or remote authentication.

## Validation scope

Run `python3 -m unittest discover -s tests -p 'test_linked_server_preflight.py' -v` for static safety-contract checks. These enforce the restricted catalog reads, absence of remote execution or persistent changes, omission of sensitive fields, exact-name filtering, and explicit unverified outcomes. They are not SQL engine, catalog permission, or remote connectivity tests. A later authorized SQL lab can exercise invalid names, hidden entries, and visible mappings; this implementation task does not create links or logins to obtain those fixtures.

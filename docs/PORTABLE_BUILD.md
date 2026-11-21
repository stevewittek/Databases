# Portable build and local collector

These commands are run from the repository root. Building requires Python 3.9+
and a current .NET SDK; Microsoft.Build.Sql and system DACPAC packages are pinned
and restored from NuGet. No database connection is made during build.

```sh
python3 -m unittest discover -s tests -v
pwsh -NoProfile -File QueryVault/Tests/TestRepositoryContracts.ps1
python3 tools/package_queryvault.py --target 2016 --storage rowstore
python3 tools/package_queryvault.py --target 2022 --storage columnstore
python3 tools/package_queryvault.py --target azure --storage rowstore
```

Targets are `2016`, `2017`, `2019`, `2022`, `2025`, `azure`. Storage defaults to
rowstore. SQL 2016 columnstore is rejected because of MAX-valued text/plan columns.
Packages (including the required adjacent `master.dacpac`) and source/content hash manifests appear under
`artifacts/<target>-<storage>/`. Each ZIP contains the archive DACPAC, required system reference DACPAC and manifest.
Generated model sources are included for review; do not edit them. The canonical SSDT manifest remains the source of build inputs.
Build repeatability means pinned tooling and the same source model; binary hashes
may vary with build metadata and are not claimed to be byte-identical across hosts.

## Disposable SQL regression harness

`tools/test_local_sql.py` only accepts Docker container names beginning with the
specific `queryvault-compat-test` pattern. Supply a generated lab-only password
through `QV_TEST_SQL_PASSWORD`. It never uses a production connection configuration.
The container must have SQL Server running and `/opt/mssql-tools18/bin/sqlcmd`.
The SQLCMD certificate override is confined to this disposable local test harness.

Create the sample source with `QueryVault/Tests/SetupLocalQueryStoreSource.sql`
inside that container, then allow at least three minutes for its one-minute
interval and flush delay to close. Build the target model first. Run:

```sh
python3 tools/test_local_sql.py --container queryvault-compat-test \
  --initialize --capture-fixture
```

`--initialize` refuses to overwrite an existing QueryVaultDB. Omit it after a
DACPAC installation. `--capture-fixture` leaves two lab archive periods for the
reporting assertions and exercises a deliberately reduced source capability
catalog, restoring the procedure definition afterward. This is not a substitute
for running an actual older engine. The harness expands existing SQLCMD includes
and omits historical table-bootstrap includes because the full fresh schema is
already present. It otherwise runs the existing SQL assertions unchanged.

## CLI deployment

Install Microsoft SqlPackage separately (the local validation used 170.5.96).
The wrapper defaults to **DeployReport**, which reads a target to calculate the
deployment plan. Script generates SQL; Publish changes the target. Even report
generation requires an authorized connection. No external command was run in this
task. The wrapper supports integrated authentication or SqlClient's Entra Default
authentication without putting passwords/tokens in arguments.

```sh
python3 tools/deploy_queryvault.py \
  --package artifacts/2022-columnstore/QueryVault.dacpac \
  --server localhost --database QueryVaultDemo

python3 tools/deploy_queryvault.py \
  --package artifacts/2022-columnstore/QueryVault.dacpac \
  --server localhost --database QueryVaultDemo \
  --action Script --output artifacts/install.sql

# Only after reviewing the report/script, against an approved empty database:
python3 tools/deploy_queryvault.py \
  --package artifacts/2022-columnstore/QueryVault.dacpac \
  --server localhost --database QueryVaultDemo \
  --action Publish --empty-database
```

TLS verification is required. Provision the local server with a trusted certificate
for this wrapper. A generated package also has a predeployment guard that rejects
any database already containing user tables. This prevents a fresh-install
partition definition from overwriting a live archive lifecycle. Repeated Publish
to an existing installation intentionally fails; it is not an upgrade path.
The existing PowerShell deployment path remains available for previously supported
procedural deployments. New nullable plan-column changes require a reviewed
migration; storage conversion and partition-boundary replacement are not automatic.

## Experimental exporter

`collector/queryvault_collect.py` connects to one explicitly configured source,
reads available Query Store fields, and writes a local review batch. It never
connects to a destination or changes a source. It does not ingest batches into
QueryVault yet. Install `pyodbc` and Microsoft ODBC Driver 18 separately before
using it. The offline tests do not require either dependency.

Copy `collector/source.example.json` to a private local configuration. Generate
distinct UUIDs for `source_id` and `source_epoch`; change the epoch after Query Store
reset/restore/reseed. Do not reuse the example IDs. For SQL authentication use
`authentication: "sql"`, `user`, and `password_env` naming a secret environment
variable. No password belongs in JSON. Integrated authentication is the default.

```sh
python3 collector/queryvault_collect.py \
  --config artifacts/source.local.json \
  --start 2026-11-01T00:00:00Z --end 2026-11-01T01:00:00Z \
  --spool artifacts/spool
```

Choose an explicitly authorized source and a window older than the source's flush
delay. The collector rejects a later endpoint instead of silently changing batch
identity. Intervals are selected by `end_time > start AND end_time <= end`; a
boundary interval can start earlier than the requested start. Auxiliary metadata
is a current observation, not historical metadata for the requested window.
`--include-capacity` includes available Azure resource/service-objective views;
it does not grant access, query billing or change resources.

Batches are bounded to 100,000 rows / 64 MiB of serialized data in aggregate;
in-memory Python overhead is additional. Smaller windows are required on overflow.
Available columns and SQL types are included. Binary and decimal values are tagged
for lossless decoding; datetimeoffset is projected as an ISO string. Identical
rows are preserved as multiple contributors, not deduplicated. Matching retries
reuse the batch directory; changed content for the same identity is rejected.
Concurrent writers to the same identity may fail and require retry; there is no
lease service. Local spool durability is process-level atomic rename, not an
fsync-backed recovery guarantee. Secure the disk and do not share query text publicly.

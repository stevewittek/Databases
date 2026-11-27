# QueryVault compatibility and product audit

Audit date: November 20, 2026. Repository: `stevewittek/Databases`, baseline
`0687cfe`. Local work: `codex/queryvault-compatibility-foundation`.
This report supersedes broad compatibility statements in older documentation.
The September lab reports remain historical evidence, not verification of this change.

## What exists

The previously empty Mac workspace now contains the complete repository. The
authoritative SQL model is the 40 `Build` entries in `QueryVault/QueryVault.sqlproj`.
Root-level duplicate SQL files and old repair scripts are not the supported build input.
The original project requires Visual Studio SSDT and fails under `dotnet build` on
this Mac. The new portable builder uses those same model entries and a pinned
Microsoft.Build.Sql SDK and system database package.

The existing product archives **same-instance** databases using three-part names.
`ServerName` is configuration metadata, not a remote connection implementation.
Archive runs retain completed intervals, native contributors and canonical metrics;
the canonical calculation preserves counts and execution-weighted means. Ten fact
tables and their ten maintenance mirrors have aligned RunID partitions. Retention
has dry-run and protected-run checks. Four Grafana dashboards already consume the
`qv_report` interface. There is no separate web application.

## Priority findings and this increment

| Priority | Finding | Action/status |
| --- | --- | --- |
| P1 | Newer plan fields, log/tempdb/page-server metrics and wait views were selected unconditionally | Source catalog discovery now controls typed NULL projections and wait collection; version-number replica checks removed |
| P1 | Four newer plan fields were NOT NULL, making unknown values impossible | Both aligned model tables now allow NULL; existing archives require an explicit reviewed schema migration |
| P1 | SQL 2016 cannot store MAX text/plan data in clustered columnstore | Added a fresh-install rowstore package preserving all columns, keys and partition schemes |
| P1 | Static DACPAC partition definitions can conflict with boundaries created at runtime | Portable packages reject databases containing user tables; use them for empty databases only |
| P1 | Cross-server/Azure DB source collection is absent | Added an experimental read-only export collector; central ingestion remains unimplemented |
| P1 | Repeating the existing T-SQL archive creates another run | No change to baseline snapshot semantics; deterministic batch retry/conflict checks apply only to the new exporter |
| P1 | Archive CATCH could roll back a caller's transaction | Archive entry now rejects ambient transactions before modifying anything |
| P2 | Compression delay, batch size and parallel-copy configuration are not effective execution controls | Documented; do not advertise them as implemented |
| P2 | CI previously checked files but did not compile DACPACs | Added a portable target build matrix and offline collector tests |
| P2 | Query Store cleanup can change catalogs between statements | Exporter validates observed relationships; atomic source snapshots and gap detection remain open |
| P2 | Azure cost/capacity recommendations lack supporting telemetry | Exporter can include available capacity DMV snapshots; no automated sizing or pricing claims |

Unavailable fields are NULL, never fabricated zero values. Successful legacy
captures record missing-column names and wait-view availability in
`RunMetadata.Comments` as JSON. Older deployments with incompatible NOT NULL
columns fail before creating a run when those fields are absent at the source.
The existing PowerShell deployer skips existing tables; running it alone does
**not** apply this nullable-column migration. Do not use the old repair scripts
to infer an upgrade. A migration must preserve indexes, switch-table symmetry,
dynamic partition boundaries, stored facts and reporting contracts.

## Compatibility boundary

Source support and archive-host support are separate decisions. A successful
target-model compile does not execute the collector's dynamic SQL or certify an
edition, service tier, authentication mode, retention switch or production workload.

| Environment | Candidate path | Acceptance still required |
| --- | --- | --- |
| SQL Server 2016 SP1+ | Rowstore archive package; core runtime collection; no Query Store waits | Real 2016 source, permissions, capture and retention |
| SQL Server 2017 | Rowstore or columnstore archive; optional newer fields NULL | Real 2017 integration |
| SQL Server 2019 | Rowstore or columnstore archive | Revalidate current changes; historical lab evidence predates them |
| SQL Server 2022 | Rowstore or columnstore archive | Local test evidence below; native supported-host acceptance still needed |
| SQL Server 2025 | Version 170 model; discover available fields | Real 2025 integration; advanced metadata retained only by exporter when present |
| Azure SQL Database | Azure target package; external collector for other databases | Live Azure ingestion, service-tier limits, Entra authentication, networking and cost telemetry |
| Azure SQL Managed Instance | Matching SQL Server model and external agent where needed | Live MI capture, permissions and retention |
| Express/Standard | Prefer rowstore for small archives; external scheduler where Agent is absent | Version/edition storage limits and representative volume testing |

SQL 2016 SP1 is the minimum candidate for the idempotent `CREATE OR ALTER` script
path and broadly available partitioning features. This project does not claim
support for SQL 2016 RTM. Azure SQL Database cannot use the existing procedure's
cross-database three-part reads. Building an Azure DACPAC does not solve that.

## Recommended multi-server architecture

```text
Source databases (SQL 2016–2025 / Azure SQL DB / MI)
        ^ independent TLS connections, read-only credentials
        |
Outbound agent on a host with access to sources and archive
        | bounded durable spool, retries, source capability manifest
        v independent TLS connection
Central configurable QueryVault database
        | staging -> validation -> transactional receipt + facts + checkpoint
        v
qv_report -> existing Grafana; optional web application later
```

Place the agent inside the network that can reach both endpoints: Voyager can
read an authorized Azure database and write locally; a suitably networked agent
can read local SQL Server and write an Azure archive. Neither database needs to
initiate an inbound connection to the other. No linked-server, CLR, public inbound
listener or database-held plaintext credential is required. Scheduling belongs to
the agent host so Express and Azure SQL Database do not depend on SQL Agent.

The archive should own a `Source` registry with stable UUID, source epoch,
display server/database, enabled flag, retention policy and a credential
**reference**. Credentials belong to the host's credential store or managed
identity, not the config table. The agent should resolve central configuration
and enforce an allowlist before connecting. Current exporter configuration is
per-source local JSON; central configuration resolution is not implemented.

Use a new source epoch after restore, Query Store clear or reseeding of source
identifiers. Endpoint names alone do not establish stable identity. Automatic
epoch detection needs corroborating database identity and lineage checks; the
prototype requires explicit operator-supplied source/epoch UUIDs.

The next receiver should stage a validated batch keyed by `(SourceId, Epoch,
BatchId)`, verify payload hashes, schema/version, source authorization, foreign
references and bounded sizes, then commit facts, receipt and checkpoint in one
transaction. An exact retry returns the existing receipt. Same identity with
different content fails for explicit reconciliation. Do not use `MERGE` or
blind `DISTINCT` as a substitute for this protocol. Keep every contributor;
materialize aggregate values from the retained contributor set.

The exporter implements local batch identity, multiset hashes and retry conflict
rejection. **It does not implement database ingestion, checkpoints, a scheduler,
leases, transport authentication or end-to-end exactly-once behavior.** Current
options/metadata/capacity snapshots can change between attempts and intentionally
cause a conflict; the receiver design must separate immutable interval facts from
mutable observation revisions before unattended operation.

Record expected interval coverage and visible oldest/newest source interval.
Do not advance a receiver checkpoint across missing coverage merely because a
request succeeded. Query Store is a finite, potentially lossy source; a safe
flush delay does not guarantee recovery after downtime or source cleanup.

## Retention, partitioning and compression

One partition per retained run is already implemented. Keep it for named
baselines and coarse historical periods, but avoid minute-by-minute unbounded
runs: 1,000 default retained runs fill in about 16.7 hours at one run/minute,
or 41.7 days hourly. Protected runs still consume capacity. The existing physical
guard reserves headroom beneath SQL Server's 15,000-partition limit.

For continuous ingestion, prefer daily/monthly fact partitions with separate
logical period membership. Deduplicate immutable text/plans by verified content
hash plus source identity outside switchable facts, with explicit reference-aware
garbage collection. Do not switch/drop shared data with one run's partition.

Rowstore suits small captures; columnstore needs enough rows per partition to
justify its overhead. `COMPRESSION_DELAY=0` does not mean every small insert is
immediately compressed. Benchmark actual rowgroup sizes and delta stores. A cold
`COLUMNSTORE_ARCHIVE` policy and configurable compression transition remain
future work. Preserve symmetric source/maintenance indexes when changing storage.
The generated rowstore package is a new-install profile, not a conversion tool.

## Security and diagnostics

Use separate deployment, source-read, ingest and reporting identities. Query
Store typically needs VIEW DATABASE STATE on older engines and VIEW DATABASE
PERFORMANCE STATE on SQL 2022+; Azure DMV grants can vary by tier. Verify the
specific source and principal rather than granting sysadmin to get around errors.
The prototype's secure connection construction requires certificate validation;
it supports integrated authentication or an environment-referenced SQL account.
Entra token refresh and managed identity are not implemented in that ODBC client.

SQL text and Showplan can contain sensitive literals. Local batches use private
directories/files, but filesystem permissions are not encryption. Define encrypted
spool storage, retention, tenant access and redaction policy before real customer
collection. Do not publish batches, connection configuration or customer queries.
The existing Grafana reporting grant exposes the entire reporting schema; separate
tenant access policies are needed before offering it as a shared hosted service.

For Azure, retain database resource usage, service objective, CPU/data IO/log IO,
workers/sessions, storage, pool context and throttling alongside query/wait data.
`dm_db_resource_stats` is a short retention source, so capture it more frequently
than historical Query Store archives. Add Azure Monitor/Cost Management adapters
only with explicit resource/API authorization. A high CPU percentage alone is
not evidence to buy vCores: first correlate query regressions, concurrency, waits,
IO/log limits and peak windows. Downsize only after representative peak coverage,
service objectives, storage limits and estimated costs are reviewed. No automatic
resize or dollar-savings claim is implemented.

Retain Grafana as the first UI. Add ingestion health, source capability, missing
coverage and Azure capacity panels after stable reporting views exist. An optional
web UI should start with source registration and collection health, with SSO and
tenant isolation. It should not expose arbitrary SQL execution or database secrets.

## Verification and next release gates

See `LOCAL_VALIDATION_2026_11_20.md` for executed checks and limitations.
Nothing in this work was pushed, externally deployed or connected to production.
The existing `master` production workflow deploys QueryVault changes to Voyager2;
this branch must not be pushed/merged into that release path without approval.

1. Review the new models and nullable-metric upgrade strategy; test migration on
   a restored archive with existing partitions and protected runs.
2. Implement source registry, transactional staging/receipt/checkpoint ingestion
   and failure/restart/concurrency tests before enabling remote ingestion.
3. Run native SQL 2016/2017/2019/2022/2025 integration tests and approved Azure DB/MI
   tests with least-privilege accounts. Include empty/disabled Query Store,
   unsupported columns, identity reset, cleanup races, replay and retention.
4. Add scheduled capacity sampling, reporting views and Grafana health panels.
5. Benchmark retention and rowstore/columnstore on representative volumes; then
   consider a web UI and a supported release rather than calling this production-ready.

## Primary references checked

- [Query Store runtime catalog, aggregation and permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql)
- [Query Store plan catalog and versioned fields](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-plan-transact-sql)
- [Columnstore supported types and version restrictions](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-columnstore-index-transact-sql)
- [SQL project target platforms](https://learn.microsoft.com/en-us/sql/tools/sql-database-projects/concepts/target-platform)
- [SQL project package references](https://learn.microsoft.com/en-us/sql/tools/sql-database-projects/concepts/package-references)
- [Azure SQL resource monitoring DMVs](https://learn.microsoft.com/en-us/azure/azure-sql/database/monitoring-with-dmvs)

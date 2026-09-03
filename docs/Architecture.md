# QueryVault Architecture

## System boundary

```mermaid
flowchart LR
    QS[Source SQL Server\nQuery Store] -->|completed intervals| CAP[dbo.usp_ArchiveQueryStore]
    CAP --> INT[(QueryVault internal dbo tables)]
    INT --> API[qv_report views and procedure]
    API --> GF[Grafana OSS\nnative MSSQL datasource]
    API --> SSMS[SSMS / sqlcmd]
    API --> FUT[Future reporting clients]
    SSMS --> PLAN[Native Showplan XML / .sqlplan]
```

Only `qv_report` is a supported visualization/reporting contract. `dbo` tables
and partition-maintenance tables are implementation details and may not be used
by dashboards or future clients as a shortcut.

## Capture flow

```mermaid
sequenceDiagram
    participant Job as Operator or SQL Agent
    participant QV as QueryVault
    participant QS as Source Query Store
    Job->>QV: usp_ArchiveQueryStore(source, window)
    QV->>QS: Read flush_interval_seconds
    QV->>QV: safe end = min(requested end, now - flush interval)
    QV->>QS: Read intervals where end_time <= safe end
    QV->>QS: Read queries, text, plans, runtime, waits for those intervals
    QV->>QV: Store all entities under one RunID
    QV->>QV: Mark period Completed and record counts
```

The cutoff is essential: an active Query Store interval can contain separate
persisted and in-memory rows at the same documented aggregation grain. Current
capture also fails closed if repeated grains are observed. This prevents a bad
completed run but does not implement canonical source aggregation; reporting is
valid only for archive periods that pass these safeguards or are independently
reconciled.

## Reporting flow and trust

```mermaid
flowchart TB
    DBO[(dbo archive tables)] -->|same owner / ownership chain| REPORT[qv_report]
    LOGIN[queryvault_grafana login] --> USER[queryvault_grafana database user]
    USER -->|SELECT on schema| REPORT
    USER -->|EXECUTE one procedure| XML[usp_GetShowplanXml]
    USER -. no grant .-> DBO
    GRAFANA[Grafana native MSSQL datasource] --> LOGIN
```

`qv_report` must be owned by `dbo`. The reporting reader receives schema-level
`SELECT` and object-level `EXECUTE`, not internal table permissions. Credentials
come from the Grafana environment or an external secret manager and are never
stored in Git.

## Contract evolution

V1 objects and column semantics are documented in
[the reporting plan](GRAFANA_REPORTING_PLAN.md). Changes should be additive.
When a dashboard needs unavailable data, change and document the contract first;
do not hide a dependency on internal objects inside dashboard JSON.

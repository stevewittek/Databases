# Grafana Setup for QueryVault

## Prerequisites

- A deployed QueryVault database, normally `QueryVaultDB`, with at least one completed archive run.
- Grafana OSS with the Microsoft SQL Server data source available.
- Network reachability from the Grafana server to SQL Server.
- A SQL Server certificate trusted by the Grafana host when encryption is enabled.
- A database administrator for the one-time reporting-contract and login deployment.

Grafana's Microsoft SQL Server data source is the supported integration. Do not install or build a QueryVault-specific datasource plugin.

## 1. Deploy the reporting contract

For a full QueryVault deployment, run the repository's normal SSDT deployment or:

```powershell
sqlcmd -S "<sql-server>" -E -b -i "QueryVault/Scripts/Deploy.sql" -v ProjectDir="QueryVault/"
```

For an existing QueryVault database, deploy these files in order:

1. `QueryVault/Schemas/qv_report.sql`
2. `QueryVault/Views/qv_report.periods.sql`
3. `QueryVault/Views/qv_report.query_period_metrics.sql`
4. `QueryVault/Views/qv_report.period_metrics.sql`
5. `QueryVault/Views/qv_report.wait_period_metrics.sql`
6. `QueryVault/Views/qv_report.query_wait_period_metrics.sql`
7. `QueryVault/Views/qv_report.query_plans.sql`
8. `QueryVault/StoredProcedures/qv_report.usp_GetShowplanXml.sql`

The reporting objects are also included in `QueryVault.sqlproj` and `QueryVault_Fixed.sqlproj`.

## 2. Create the read-only SQL principal

Have a DBA create the `queryvault_grafana` SQL login through the organization's approved secret-management process. The login should use password policy and must have no server-level role memberships beyond `public`.

The administrative operation is equivalent to the following, with the placeholder supplied interactively or by the approved deployment system rather than saved in a file:

```sql
USE [master];
CREATE LOGIN [queryvault_grafana]
    WITH PASSWORD = '<secret supplied at execution time>',
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = ON;
```

`QueryVault/Security/ProvisionGrafanaReader.sql` then creates the mapped database user. It deliberately does not accept, generate, or store a password. It grants only:

```sql
GRANT SELECT ON SCHEMA::qv_report TO [queryvault_grafana];
GRANT EXECUTE ON OBJECT::qv_report.usp_GetShowplanXml TO [queryvault_grafana];
```

Run the user/grant script as a database administrator:

```powershell
sqlcmd -S "<sql-server>" -E -b -i "QueryVault/Security/ProvisionGrafanaReader.sql"
```

The script defaults to database `QueryVaultDB` and login `queryvault_grafana`. Override `QueryVaultDatabase` or `QueryVaultGrafanaLogin` as SQLCMD variables if necessary.

Verify least privilege while connected as the Grafana login:

```sql
SELECT TOP (1) * FROM qv_report.periods;
SELECT HAS_PERMS_BY_NAME(N'qv_report', N'SCHEMA', N'SELECT') AS can_read_reporting;
SELECT HAS_PERMS_BY_NAME(N'dbo.RunMetadata', N'OBJECT', N'SELECT') AS can_read_internal;
```

Expected results are `can_read_reporting = 1` and `can_read_internal = 0`. Also review any permissions inherited from `public` in your environment.

## 3. Configure datasource secrets

Set these values in the Grafana service/container environment:

| Variable | Example | Purpose |
| --- | --- | --- |
| `QV_SQLSERVER_HOST` | `sql.example.internal` | SQL Server host resolvable from Grafana |
| `QV_SQLSERVER_PORT` | `1433` | SQL Server TCP port |
| `QV_SQLSERVER_DATABASE` | `QueryVaultDB` | QueryVault database |
| `QV_GRAFANA_SQL_USER` | `queryvault_grafana` | Dedicated read-only SQL login |
| `QV_GRAFANA_SQL_PASSWORD` | secret value | Login password supplied by the secret manager |

The provisioned datasource uses TLS encryption and validates the server certificate. For a private CA, add that CA to the Grafana host/container trust store. Do not disable certificate validation in production. A local lab may temporarily set `tlsSkipVerify: true` in an uncommitted override.

The password is stored under Grafana's `secureJsonData`; the repository contains only an environment-variable reference. The provisioning file intentionally uses Grafana's `$QV_GRAFANA_SQL_PASSWORD` form, which avoids a second variable-expansion pass when a password itself contains `$`.

## 4. Mount or copy provisioning files

Grafana must see the repository paths at its conventional locations:

| Repository path | Grafana path |
| --- | --- |
| `grafana/provisioning/datasources/` | `/etc/grafana/provisioning/datasources/` |
| `grafana/provisioning/dashboards/` | `/etc/grafana/provisioning/dashboards/` |
| `grafana/dashboards/` | `/var/lib/grafana/dashboards/queryvault/` |

For containers, mount these directories read-only. For a package installation, copy them into the equivalent configured paths. Restart Grafana after adding the datasource provisioning file. Dashboard provisioning polls every 30 seconds.

The four provisioned dashboards appear in the `QueryVault` folder:

- QueryVault Overview
- QueryVault Period Comparison
- QueryVault Wait Analysis
- QueryVault Query Detail

## 5. Test the datasource and dashboards

In Grafana, open **Connections > Data sources > QueryVault SQL Server** and select **Save & test**. Then open QueryVault Overview and select a source server, source database, and completed archived period.

If variables are empty:

- confirm that `qv_report.periods` returns completed rows;
- confirm the datasource database is the QueryVault database;
- confirm the Grafana login has schema-level `SELECT`;
- inspect Grafana server logs for TLS, login, or SQL errors.

Empty wait panels are valid when the selected archive has no archived wait rows.

## Native Showplan XML

QueryVault does not render execution plans. `qv_report.query_plans.showplan_xml` and `qv_report.usp_GetShowplanXml` return native SQL Server Showplan XML.

In SSMS:

```sql
EXEC qv_report.usp_GetShowplanXml
    @PeriodID = 42,
    @QueryID = 12345;
```

The procedure requires either `@QueryID` or `@PlanID`. Click the XML value in the SSMS results grid to open SQL Server's graphical plan viewer. To export, open the XML result and use **File > Save As**, choosing a `.sqlplan` filename. The saved file can be reopened directly in SSMS.

For a specific plan:

```sql
EXEC qv_report.usp_GetShowplanXml
    @PeriodID = 42,
    @PlanID = 67890;
```

The Query Detail dashboard lists the period ID, query ID, and plan ID needed for retrieval but intentionally omits the potentially large XML payload.

## Upgrade rule

Dashboard SQL may use only `qv_report` objects. If a new panel requires data not present in that schema, extend and document the reporting contract first. Do not point a dashboard at internal `dbo` tables as a shortcut.

## References

- [Grafana Microsoft SQL Server datasource configuration](https://grafana.com/docs/grafana/latest/datasources/mssql/configure/)
- [Grafana file provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)

# QueryVault Installation

## Requirements

- SQL Server 2016 or later; validate behavior on the exact target version.
- Query Store enabled in every source database.
- PowerShell 7 plus the `SqlServer` module for the production-safe script path.
- SQL Server Agent only when scheduled capture is required.
- A DBA for database/schema/login bootstrap and a restricted deployment identity
  for repeat releases.

## Non-production first

Deploy to an isolated SQL Server, register a test source, archive a small
completed window, and run:

```powershell
sqlcmd -S "<test-server>" -E -b -i "QueryVault/Tests/TestQueryStoreAggregationGrain.sql" -d QueryVaultDB
```

Then install the reporting boundary as described below and run
`QueryVault/Tests/TestReportingContract.sql`.

## Reporting schema bootstrap

The `qv_report` schema is a security boundary and must be owned by `dbo`. A DBA
runs the idempotent bootstrap once:

```powershell
sqlcmd -S "<server>" -E -b -i "QueryVault/Security/ProvisionReportingSchema.sql"
```

Do not grant the restricted deployer `IMPERSONATE dbo` or broad internal table
permissions. Pre-deployment validation and `DeployQueryVault.ps1` verify this
prerequisite before backup/object deployment work proceeds.

## Supported production sequence

From a reviewed commit, load the deployment credential from the approved secret
location and run:

```powershell
pwsh -NoLogo -NoProfile -File QueryVault/Scripts/InvokeQueryVaultProductionDeployment.ps1 `
  -ServerInstance "<server>" `
  -DatabaseName QueryVaultDB `
  -GitSha "<reviewed-commit>"
```

The sequence captures a pre-deployment baseline, creates and verifies a
checksummed backup, preserves existing tables, deploys repeatable modules, and
compares post-deployment data/configuration/job state. Trust-server-certificate
is a lab exception; production should use a trusted SQL Server certificate.

On Voyager2, the production GitHub Actions workflow accepts manual dispatches
from `master` and automatically runs for pushes to `master` that modify
`QueryVault/**`. Both paths use the protected `queryvault-production`
environment and the guarded production sequence. Pull requests use a separate
GitHub-hosted static-validation workflow and never use the Voyager2 runner.

## Grafana reader and package

After the API is deployed, have a DBA create `queryvault_grafana` as a SQL login
using a password supplied by an external secret manager. Run:

```powershell
sqlcmd -S "<server>" -E -b -i "QueryVault/Security/ProvisionGrafanaReader.sql"
```

Set the five `QV_*` environment variables described in
[Grafana Setup](Grafana-Setup.md), mount `grafana/provisioning` and
`grafana/dashboards` read-only, and start/restart the approved Grafana instance.
No custom datasource plugin is required.

## Acceptance

Installation is not complete until:

- core and reporting tests pass against populated data;
- the Grafana identity can read `qv_report` and cannot read `dbo.RunMetadata`;
- all four dashboards load with working variables;
- at least one period reconciles to an administrator's direct aggregate; and
- one exported `.sqlplan` opens in SSMS.

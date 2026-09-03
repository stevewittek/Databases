# QueryVault production deployment handoff

This document covers the Voyager 2 machine side only. It intentionally contains
no GitHub Actions workflow YAML.

## Fixed deployment values

- Repository: `stevewittek/Databases`
- Default branch: `master`
- Source path filter: `QueryVault/**`
- Production server: `localhost` on Voyager 2
- Production database: `QueryVaultDB`
- GitHub Environment: `queryvault-production`
- Runner labels: `self-hosted`, `Linux`, `X64`, `voyager2`, `queryvault-prod`
- Runner directory: `/home/nasa/actions-runner-queryvault`
- Runner work directory: `/home/nasa/actions-runner-queryvault/_work-queryvault`
- Local credential file: `/home/nasa/.config/queryvault-production/sql.env`
- Baseline directory: `/home/nasa/queryvault-production/baselines`
- Backup directory: `/var/opt/mssql/userlog/backups/voyager2/QueryVaultDB/FULL`

SQL Server remains local. The runner polls GitHub over outbound HTTPS and does
not require SQL Server to be exposed publicly.

## Local credential loading

The protected credential file is owned by `nasa`, has mode `0600`, and exports:

```text
QUERYVAULT_SQL_USER=queryvault_deployer
QUERYVAULT_SQL_PASSWORD=<stored only on Voyager 2>
```

It is provisioned once on Voyager 2 with:

```bash
QueryVault/Scripts/InitializeQueryVaultDeployer.sh
```

The initializer generates the password locally, provisions the restricted SQL
login, and stores the credential without printing it.

Load it without printing the password:

```bash
set -a
source /home/nasa/.config/queryvault-production/sql.env
set +a
```

These can instead be supplied by GitHub Environment secrets named
`QUERYVAULT_SQL_USER` and `QUERYVAULT_SQL_PASSWORD`. Do not use both sources.

## Local production command

Run from the repository root after loading the credential environment:

```bash
pwsh -NoLogo -NoProfile -File QueryVault/Scripts/InvokeQueryVaultProductionDeployment.ps1 \
  -ServerInstance localhost \
  -DatabaseName QueryVaultDB \
  -TrustServerCertificate \
  -GitSha "$(git rev-parse HEAD)"
```

The command stops on the first failure and performs:

1. database/object/config/archive/Agent pre-deployment verification;
2. baseline capture outside the repository;
3. copy-only, compressed, checksummed full backup;
4. `RESTORE VERIFYONLY WITH CHECKSUM`;
5. production-safe deployment from canonical folders;
6. post-deployment comparison, procedure compilation, and a read-only smoke test.

Existing tables and their data are preserved. The deployer refreshes the five
core stored procedures, six `qv_report` views, and the Showplan retrieval
procedure, and executes only the idempotent partition scripts. It never runs SQL
Agent job scripts or retention/purge procedures.

The core procedures include identity-jump partition growth, shared-partition
switch/truncate rejection, owned-transaction safeguards, and fail-closed
runtime/wait duplicate-grain detection. The last safeguard does not implement
canonical source aggregation; see `docs/Query-Store-Correctness.md` before
authorizing capture changes.

Before the sequence can run, a DBA must execute the idempotent
`Security/ProvisionReportingSchema.sql` bootstrap once. The deployment identity
cannot create a `dbo`-owned schema. Deployment preflights this condition before
any DDL and stops safely when it is not met.

## Individual commands

Pre-deployment baseline:

```bash
pwsh -NoLogo -NoProfile -File QueryVault/Scripts/TestQueryVaultDeployment.ps1 \
  -Mode Pre -ServerInstance localhost -DatabaseName QueryVaultDB \
  -BaselinePath /home/nasa/queryvault-production/baselines/manual.json \
  -TrustServerCertificate
```

Backup and verification:

```bash
pwsh -NoLogo -NoProfile -File QueryVault/Scripts/BackupQueryVault.ps1 \
  -ServerInstance localhost -DatabaseName QueryVaultDB -TrustServerCertificate
```

Deployment only:

```bash
pwsh -NoLogo -NoProfile -File QueryVault/Scripts/DeployQueryVault.ps1 \
  -ServerInstance localhost -DatabaseName QueryVaultDB \
  -TrustServerCertificate -GitSha "$(git rev-parse HEAD)"
```

Post-deployment verification uses the same baseline file with `-Mode Post`.

## Runner registration boundary

The runner files may be prepared locally, but repository registration requires
a short-lived token generated in GitHub. In GitHub, open:

`Settings` → `Actions` → `Runners` → `New self-hosted runner` → `Linux` → `x64`.

Run the displayed registration command from
`/home/nasa/actions-runner-queryvault` and include:

```text
--name voyager2-queryvault-prod
--labels voyager2,queryvault-prod
--work _work-queryvault
```

Do not use `--ephemeral`. After registration, install the runner as a persistent
service using GitHub's displayed service commands. This last service installation
requires `sudo` and should run as the `nasa` account unless a dedicated OS account
is created by an administrator.

## Workflow contract

The production workflow:

1. trigger for `master` changes limited to `QueryVault/**`, plus manual dispatch;
2. use the `queryvault-production` environment;
3. use concurrency group `queryvault-production` without canceling a deployment;
4. select all five runner labels listed above;
5. check out the exact triggering commit;
6. verify `hostname` is `voyager2` and required tools are present;
7. load the local credential file or map the two Environment secrets;
8. call the single local production command above;
9. preserve logs and the baseline path even when a step fails;
10. rely on the command's nonzero exit status to fail the job.

Pull requests use `.github/workflows/queryvault-ci.yml` on `ubuntu-latest` for
repository-contract, PowerShell-parser, dashboard JSON, and provisioning YAML
checks. That workflow has no production environment, self-hosted runner, SQL
credential, remote host, or database connection.

Never place a SQL password, GitHub token, or runner registration token in the
workflow file or repository.

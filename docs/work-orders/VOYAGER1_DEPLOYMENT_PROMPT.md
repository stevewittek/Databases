# Voyager 1 GitHub deployment setup

Paste the block below into Codex on `DESKTOP-CLVE7DV`. The GitHub source is `stevewittek/Databases`. This machine is both the worker host and the only SQL target. The fixed database is `QueryVaultDB`.

```text
Set up the QueryVault Voyager 1 deployment worker on this Windows desktop.
Use the clean pipeline revision Steve gives you, preferably after it is merged
to master. Do not set up a self-hosted runner on the public repository. Do not
deploy database code yet. First prove the read-only path and inspect the root.

1. Verify COMPUTERNAME, PowerShell 7, SqlServer module 22+, and the actual local
   SQL instance. Use the existing Windows-integrated login and the DNS name
   matching the trusted SQL certificate. Do not bypass TLS, change firewalls or
   expose SQL to GitHub. If trust fails, report the exact certificate/name gap.
2. Run tools/inspect_queryvault_archives.sql if present, or equivalent SELECTs.
   Identify all archive names, the actual daily Agent step target, newest
   schema, latest completed capture and most recent job outcome. Confirm the
   root really is QueryVaultDB. Run tools/voyager1/Inspect-RootArchive.sql in
   that database. Report PF_RunID boundary and whether the rightmost partition
   is populated on aligned clustered columnstore tables. Do not change or
   retry the job, run a workload, or change the root database.
3. Prepare a private state folder C:\ProgramData\QueryVault\Voyager1. Restrict
   its ACL to the agreed task identity and local Administrators/SYSTEM. Install
   tools/voyager1/Invoke-Voyager1DeploymentWorker.ps1 there from the reviewed
   revision. Run tools/voyager1/Test-Voyager1DeploymentWorker.ps1 locally.
   Create config.json with server_instance (the verified TLS SQL endpoint),
   deployment_enabled=false, backup_root (the SQL Server-side directory on
   independent healthy recovery storage), and baseline_root (an existing
   private local directory). Do not store passwords in config.json.
4. The GitHub result callback needs a fine-grained PAT issued by stevewittek
   for just stevewittek/Databases. Grant only Commit statuses Read and write
   plus automatic read-only Metadata. No Contents or Actions write and no
   classic repo token. If it's not already available, finish other setup and
   ask Steve to enter it locally in PowerShell under the task identity:

   $root = 'C:\ProgramData\QueryVault\Voyager1'
   Read-Host 'GitHub status token' -AsSecureString | ConvertFrom-SecureString |
     Set-Content -LiteralPath (Join-Path $root 'github-status.dpapi')

   Do not print the token or file. Verify the task identity can decrypt it.
5. Register a Scheduled Task running pwsh.exe -NoProfile -NonInteractive
   -File <installed worker path> every 2 minutes with overlaps ignored. Start
   with the same logged-in identity that wrote the DPAPI file. This avoids
   storing its Windows password but requires that account to remain logged
   in. For unattended startup use an already approved dedicated identity and
   recreate the DPAPI file under that identity. Do not run as SYSTEM to bypass
   login constraints. Confirm outbound HTTPS to api.github.com and
   codeload.github.com from the task account.
6. Once on master, have Steve start Actions > QueryVault | Voyager 1 >
   Run workflow > inspect, or use his already authorized GitHub session.
   Verify GitHub received the desktop result. Return the run URL, SHA,
   local receipt path, target identity and blockers. Keep raw job commands,
   backups, query text and private logs off GitHub.
7. If overflow exists, leave deployment_enabled=false. Prepare the verified
   backup and isolated restore, and test a reviewed lossless repair with a
   bounded clone capture under #55/#58. Preserve RunIDs, pins, retention and
   reports. Do not install a fresh DACPAC on the root. Return recovery and
   reconciliation evidence plus the exact candidate SHA before any live fix.

Complete checks that do not require my input. Report exactly what I still need
to do. Do not touch Voyager 2 or Azure.
```

## Operating the pipeline

- Only `stevewittek` can dispatch this workflow on `master`. GitHub validates and waits for the desktop result. The worker validates the GitHub request, exact master SHA, Windows host and SQL target. It rejects stale requests and does not replay interrupted work.
- `inspect` performs no SQL writes. `deploy` also requires local release readiness, no legacy overflow, a verified copy-only backup, and postchecks. It does not run Agent jobs or repair the partition layout.
- Canceling or timing out the hosted job does not undo SQL work already started. Check the private `run-*.json` receipt and `run-*.log` before dispatching again. Retain receipts when cleaning extracted source and ZIPs.
- Unmerged code and local ZIPs do not become deployment payloads. Test the selected database changes on the restored clone, merge the reviewed revision and dispatch `master` again if it advances before deployment.
- Use separate controllers, status contexts and target checks for Voyager 2 and Azure. This change does not activate them.

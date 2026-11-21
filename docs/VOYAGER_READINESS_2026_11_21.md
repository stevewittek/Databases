# Voyager readiness — November 21, 2026

Owner authorized coordination with Voyager1/Voyager2 while QueryVault work
continues. Findings below come from the existing Voyager1 chat, **Assess Voyager
Two readiness**, plus a bounded Mac SSH attempt. No QueryVault candidate was
deployed to either host. Existing schedules, links, provider settings, credentials,
permissions and source/archive data were left unchanged.

## Voyager1 observed evidence

- Local SQL Server 2019 Developer Edition 15.0.2210.4 and SQL Server Agent running.
  Existing QueryVault databases are online at compatibility 150. These are existing
  installations; they do not establish deployment of PR #56.
- PowerShell 7.6.10, SqlServer module 22.4.5.1, SqlPackage 170.4.83.3, legacy sqlcmd
  15.0.2000.5, ODBC 18.6.2.1 and OLE DB 18.7.4/19.4.1 present. SQL Server enumerates
  MSOLEDBSQL and MSOLEDBSQL19. Azure CLI and the modern Az module are absent.
- Windows 10 Pro 22H2 build 19045.6466; current support/patch readiness and ESU
  entitlement are not established. No OS or tool update was performed.
- D: is an internal approximately 1-TB SSD with approximately 582 GB free. Historical
  System events record 18,047 Disk 153 I/O retries on the physical disk mapped to
  D: during August 19–21. Current SMART/reliability evidence was unavailable.
  This is a capacity candidate, not verified healthy storage; historical events
  alone do not prove current failure. C: has approximately 4.3 GB free. Other
  volumes/devices also had historical NTFS/USB errors.
- Strict certificate validation to the loopback IP failed with a name mismatch.
  Local metadata was obtained using a temporary client trust setting; the SQL
  certificate/server settings were not changed. A correctly named endpoint with
  strict TLS still needs verification. The IP mismatch alone does not prove the
  configured certificate is invalid for its intended DNS name.
- An enabled daily QueryVault archive job last failed on November 20. Eleven
  synthetic QueryVault jobs are enabled without schedules. No job was rerun or
  changed. Bounded diagnosis of the existing failure is tracked in #58.

Host suitability and stable recovery storage remain unproven (#29). An independent
backup target and restore evidence remain missing (#30). The observed Developer
Edition must be evaluated against the intended test versus operational use before
choosing the final host; no production hosting approval is implied.

## Local inspector execution

Voyager1 reviewed and ran `QueryVault/Preflight/InspectLinkedServer.sql` from commit
`805dbaa2e452fdd66cca542cfa827c4e347e6ce8` against the existing Voyager2 link's LOCAL
catalog entries. It returned:

- `InspectionScope = LOCAL_CATALOG_ONLY`
- `CanStartCollection = 0`
- `InspectionStatus = REQUIRES_REMOTE_VALIDATION`
- Provider `SQLNCLI` (legacy), one visible stored-credential mapping and no visible
  wildcard mapping.
- Remote connectivity/Query Store access untested; TLS/effective identity unassessed.

This proves successful execution of the inspection batch on SQL Server 2019, not
remote authentication. The new code performed no OPENQUERY/RPC. Separate bounded
metadata attempts reported by the Voyager task were rejected locally with error
7411 and returned no Voyager2 database data. No link options were changed to make
them succeed. Missing-alias rejection and restricted-metadata visibility remain
runtime test cases; the repository's six inspector tests are static contracts.

## Voyager2 access

Voyager1 reported reachable SSH/SQL ports. A subsequent Mac SSH attempt used the
known documented account and existing key material with BatchMode, strict host-key
checking and a five-second connect bound. SSH rejected authentication; no password
was requested, host trust bypassed or remote command executed.

Current Voyager2 SQL version, database state, backup history, file placement and
integrity therefore remain UNVERIFIED. September records are historical, not
current recovery evidence. Do not mark #30 complete from reachable ports, a failed
linked query or old reports. A usable existing authenticated route is needed for
the remaining read-only inventory; restore/integrity testing is separate work.

## Next work

1. Review the narrow job-failure diagnosis in #58 before any retry or fix.
2. Establish current disk health and an independent recovery target (#29/#30).
3. Verify OS support/patch readiness and strict TLS using the intended hostname.
4. Resolve source credential policy (#49), then choose a scoped unattended identity
   and test a modern provider in an isolated environment (#57).
5. Motion Relay's Azure metadata connection succeeded from the Mac separately;
   see AZURE_SOURCE_READINESS_2026_11_21.md. It does not establish Voyager access.

No new server, database, firewall access or paid service was provisioned. Original
working copies were preserved; all implementation remains in draft PR #56.

## Existing job diagnosis (#58)

A second bounded Voyager1 pass read the single November 20 failure and deployed
procedure metadata. Step 1 reported wrapper error 50000/severity 16. The underlying
message matches engine error 35346: a clustered-columnstore split was attempted
against a populated partition. Four attempted RunIDs (6204–6207) failed at partition
allocation while the recorded maximum partition boundary was 120; no capture
completed for those attempts.

The installed partition procedure dates to July 26 and lacks the reviewed legacy
overflow guard. Current source explicitly rejects unsafe allocation with 51073.
This establishes a stale deployment plus legacy partition-layout failure; it does
not attribute this particular job failure to the separately observed disk/TLS
readiness issues. The new candidate was not installed and did not cause it.

Installing the guard alone would give a controlled rejection, not migrate old
rows. #55 must include a verified backup of this affected **Voyager1** archive,
an isolated restore, catalog-based boundary/layout inventory, and a reviewed
migration preserving aligned tables, RunIDs, protected periods and reporting.
Voyager2 recovery in #30 is separate and cannot substitute for this backup.
Test the repair and bounded synthetic capture on the clone before any live
migration or schedule decision. No retry, schedule change or migration was run.
The enabled daily schedule remains as found; diagnosis is complete, repair is not.

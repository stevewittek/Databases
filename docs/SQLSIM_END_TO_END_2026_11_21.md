# QueryVault and sqlsim demonstration results

**Passed on Voyager 1, November 21, 2026.** A small synthetic workload ran through sqlsim, appeared in the source database's Query Store, and was captured into a separate QueryVault archive. The workload's execution count, CPU, duration, logical reads and plan count matched exactly in QueryVault reporting.

## What ran

| Item | Observed result |
| --- | --- |
| Source database | `QueryVaultSqlsimSource_20261121` |
| QueryVault archive | `QueryVaultSqlsimArchive_20261121` |
| Synthetic data | 5,000 deterministic rows |
| Workload | `dbo.usp_QV_SQLSIM_DEMO_20261121`, two sqlsim workers, 50 iterations each |
| sqlsim outcome | 100 executions, zero errors, zero warnings; client result rows suppressed |
| Client wall time | 0.758 seconds |
| Captured period | November 21, 2026, 19:43–19:44 UTC / 2:43–2:44 PM Eastern |
| Archive run | RunID 1, `Completed`, observation state `COMPLETED` |
| Capture elapsed time | Approximately 2.175 seconds, from archive run timestamps |
| Protection | Pinned with an explanatory note; automatic deletion disabled |

## Source versus saved results

These are the metrics for the workload statement, Query ID 6, Plan ID 6. They exclude the setup and inspection statements also present in the source Query Store.

| Metric | Source Query Store | QueryVault reporting | Difference |
| --- | ---: | ---: | ---: |
| Executions | 100 | 100 | 0 |
| Total CPU time | 594.549 ms | 594.549 ms | 0 |
| Total query duration | 916.017 ms | 916.017 ms | 0 |
| Logical reads | 5,900 | 5,900 | 0 |
| Plans | 1 | 1 | 0 |

The saved averages are 5.94549 ms CPU, 9.16017 ms duration and 59 logical reads per execution. Total query duration adds executions across two concurrent workers; it is different from client wall time. This short functional test does not measure collection overhead or establish a sustainable throughput limit.

One native runtime contributor containing all 100 executions became one archived contributor and one canonical reporting row. Query text and plan text were present. Source intervals were closed and beyond the configured 60-second flush allowance before capture.

The whole archive period includes six queries, six query texts, six plans, six runtime contributor rows, six canonical runtime rows, one interval, two wait contributor rows and two canonical wait rows. Inspection statements explain why whole-period counts exceed the single workload query. The run summary's 27 archived rows covers its six tracked catalog/statistics categories; it is not a count of every physical lineage-table row.

## Review the saved period yourself

Both lab databases remain online on Voyager 1. In SSMS, connect to that instance with Windows authentication and validated encryption, then open [ReviewSqlsimDemo.sql](examples/ReviewSqlsimDemo.sql). It only reads the saved run and workload metrics. It does not regenerate load or change retention. The optional last command retrieves the saved plan XML.

RunID 1 is protected with the note:

> Pinned local sqlsim end-to-end demonstration captured 2026-11-21; retain for review.

Its existing retention timestamp is November 28 at 19:44 UTC, but the protection flag and disabled automatic deletion preserve this review period. No SQL Agent job was created. The source and archive are separate databases on the same shared SQL Server instance; this is database isolation, not dedicated hardware isolation.

## Deployment and limits

The SQL Server 2019 columnstore package was built locally on Voyager 1 from clean commit `37771847908f602af5cf373ea9e5a8a93850761c`. The deployment plan contained 137 create-only items and zero alerts; the new archive was verified empty before publishing. Package SHA-256: `cddb1b14347cb9ff0395c425fe023f17eb2f50ace9bde1aac431cc1c0f6b49bc`.

Connections used Windows authentication, ODBC Driver 18 and mandatory encryption with certificate validation. The workload used five-second login/query limits, no retries and a 30-second outer limit. Query Store settings were changed only on the new source: capture all, one-minute intervals, 60-second flush and 32 MB maximum.

Both databases use SIMPLE recovery. Final allocated files were source 32 MB data / 16 MB log and archive 192 MB data / 64 MB log; each database is capped at 512 MB data / 128 MB log. Allocated file sizes include free/preallocated space and are not the size of the captured payload or a compression-efficiency measurement.

The data drive had approximately 541.55 GiB free afterward. No storage warning/error events were found in the specified pre/post windows, and no matching 823/824/825 or long-I/O errors were found in the inspected current SQL log. These bounded checks do not establish full disk health or restore readiness.

Existing archives, jobs, linked servers, MotionRelay and Voyager 2 were unchanged. This demonstrates current same-instance capture and SQL reporting. It does not validate remote ingestion, job scheduling, Grafana rendering, a large load test or archive recovery.

## Evidence and execution notes

Voyager 1 task folder:

```text
C:\Users\switt\.codex\.chatgpt-projects\g-p-69415e6aee10819180ff3f1553171773\work\queryvault-sqlsim-e2e-20261121
```

It retains `RESULTS.md`, the isolated `candidate` checkout/package, setup and verification scripts in `scripts`, logs in `logs`, and `results/50_sqlsim_workload.json`. Key evidence is `logs/71_verify_end_to_end_refined.log`, `logs/60_archive_and_pin.log`, `logs/30_queryvault_deploy_report.xml` and `logs/80_postcheck.log`. The repository review script above uses the verified schema and IDs; it is a convenient read-only extract, not a replacement for those executed reconciliation scripts.

Execution corrections were retained in the logs: the old ODBC 17 sqlcmd path failed before switching to ODBC 18; a fixture batch-formatting error was corrected before workload execution; a text-marker filter was narrowed to the procedure/query identity to exclude inspection statements. No QueryVault source-code change was needed for the successful capture. The capture emitted two null-eliminated aggregate warnings and completed without errors; sqlsim's workload itself reported no warnings.

The .NET build's first-run initialization reported creating an untrusted user-scoped ASP.NET development certificate. It was neither trusted nor used for this test; SQL Server's certificate configuration was not changed.

Tracked demonstration: [59](https://github.com/stevewittek/Databases/issues/59). Broader performance work remains [12](https://github.com/stevewittek/Databases/issues/12), following the [functional and load test plan](TEST_AND_LOAD_REVIEW.md).

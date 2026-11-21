# Bob Ward sqlsimtools evaluation

Reviewed November 21, 2026 for QueryVault test work in [ticket 12](https://github.com/stevewittek/Databases/issues/12).

## Tool identification and fit

The tool is **sqlsimtools**. Bob Ward introduced it on October 14, 2026 as a newer approach to the workload testing he previously did with ostress. The suite contains native `sqlsim`, Python `sqlpysim`, and the visual `sqlsim Studio`. [Bob Ward's announcement](https://techcommunity.microsoft.com/blog/sqlserver/introducing-sqlsimtools/4563955).

The public release inspected is **v1.0.0**. Windows x64 is a public-preview route; the Mac ARM64 builds are invitation-only private preview. The native Windows tool uses ODBC Driver 18. It is open source under MIT and community supported. [Repository](https://github.com/microsoft/sqlsimtools), [release](https://github.com/microsoft/sqlsimtools/releases/tag/v1.0.0), [installation guide](https://github.com/microsoft/sqlsimtools/blob/main/INSTALL.md).

Use Voyager 1 for the first executable evaluation. Native sqlsim is the proposed workload generator; QueryVault still performs the archiving. This does not change the selected T-SQL collection architecture or solve remote ingestion.

sqlsim supports controlled concurrent queries/scripts, mixed workloads, timeouts, JSON results and optional query statistics. These are useful starting points for reproducible QueryVault tests. Resource monitoring, exact period reconciliation, pin checks and collection coordination remain our responsibility. Do not infer request latency percentiles from average timings; verify the emitted sample data first. [Versioned native manual](https://github.com/microsoft/sqlsimtools/blob/v1.0.0/sqlsim/sqlsim.md).

## Evaluation scope

The first execution was limited to version/help and a single `SELECT 1` connection against Voyager 1's explicitly selected local `tempdb`, using existing integrated authentication, one worker, one iteration, timeouts and certificate validation. This verifies executable and connection readiness only. It created no database or workload tables and did not test QueryVault capture.

Voyager 1's previously unresolved storage-health concerns still prevent treating this check as authorization for a heavy benchmark on its existing archive. No application workload is run against MotionRelay or Voyager 2.

## Observed execution results

| Check | November 21 result |
| --- | --- |
| Installation | Native Windows x64 sqlsim 1.0.0 installed in a new user-owned folder; no PATH or dependency changes |
| Download integrity | Official ZIP SHA-256 matched GitHub's published digest |
| Version and help | Both returned exit code 0 |
| SQL connection | Success using the local computer name and port 1433, Windows authentication, ODBC 18.06.0002 |
| Encryption | Mandatory encryption with certificate validation; no `-C` bypass |
| Query | One `SELECT 1` returned 1; exit code 0; tool-reported total runtime 0.085 seconds |
| Bounds | One worker, one iteration, five-second login/query timeouts, zero retries, twenty-second outer timeout; no timeout occurred |
| Load benchmark | Not run; this result is not a throughput or QueryVault performance measurement |

Release asset: `sqlsim-1.0.0-win-x64.zip` (781,523 bytes).
SHA-256: `ac459de10555318bf0a02e58e79a92580bbedf7d355a8a69b61285969e159def`.
The executable is unsigned, as documented for the preview release.

The executable is under `%USERPROFILE%\Tools\sqlsimtools\v1.0.0\package\sqlsim\x64\sqlsim.exe` on Voyager 1. Evidence remains in the sibling `logs` folder: `sqlsim-local-strict-tls-smoke.txt`, `sqlsim-help-corrected.txt` and `sqlsim-version-corrected.txt`. An initial offline wrapper omitted its help/version arguments; that was corrected, and the earlier logs were retained. No connection occurred in that initial invocation.

The executed arguments were `-S <local-computer-name>,1433 -d tempdb -E -N m -Q "SELECT 1" -n 1 -r 1 -l 5 -t 5 -retry 0`, inside a twenty-second process wrapper. `-N m` is mandatory encryption, not the separate TDS Strict mode.

This validates the local hostname route on Voyager 1. It does not establish that an IP-address route, Mac client, remote linked server or unattended collector identity passes the same checks. It narrows the earlier unresolved hostname-TLS question in the [Voyager readiness report](VOYAGER_READINESS_2026_11_21.md), without changing that report's historical observations.

## Next experiment after readiness

1. Use an isolated synthetic database and separate test archive on a verified host.
2. Run a small repeatable sqlsim workload; wait for its Query Store intervals to close.
3. Capture those intervals into QueryVault and reconcile the results.
4. Repeat the identical workload with collection idle and active; measure the difference.
5. Increase workers gradually and test retention/protection while measuring resource use.

Use the limits and result records in the [test plan](TEST_AND_LOAD_REVIEW.md). Studio is an optional later visual interface; its browser app is not required for automated CLI experiments. The initial evaluation does not install a hosted service, change SQL Server settings or replace the existing collector.

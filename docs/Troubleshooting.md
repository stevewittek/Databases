# QueryVault Troubleshooting

## Deployment stops before DDL

Message: `Required dbo-owned schema 'qv_report' is missing or has the wrong owner.`

Have a DBA run `QueryVault/Security/ProvisionReportingSchema.sql`, verify
`USER_NAME(principal_id) = 'dbo'` in `sys.schemas`, then rerun the complete
deployment sequence. Do not broaden the deployer or grant reporting users
internal table access.

## Grafana datasource fails

- Confirm host/port reachability from the Grafana container or service.
- Confirm `QV_SQLSERVER_*` and `QV_GRAFANA_SQL_*` variables are supplied without
  printing their values.
- Use a SQL Server certificate trusted by the Grafana host. Keep encryption on
  and certificate validation enabled in production.
- Confirm the user exists in `QueryVaultDB` and has `SELECT` on schema
  `qv_report`.
- Confirm the datasource UID is `queryvault-mssql`.

## Dashboard variables are empty

Run as the Grafana identity:

```sql
SELECT TOP (10) *
FROM qv_report.periods
WHERE period_status = N'Completed'
ORDER BY period_end_utc DESC;
```

If this fails, fix deployment/permissions. If it returns no rows, archive a
safely completed period. Never repoint variables to `dbo.RunMetadata`.

## Wait panels are empty

An archive can legitimately contain no wait rows. Check
`archived_wait_stats_rows` in `qv_report.periods` and confirm Query Store wait
statistics are available for the source/version/window.

## Comparison looks misleading

- Verify baseline and comparison use the same source server/database and similar
  duration.
- Avoid the nine known pre-safeguard Voyager2 periods.
- Determine whether Query Store was reset between periods; source-native
  `query_id` is not durable across resets.
- Compare absolute workload changes as well as percentages and plan counts.

## Showplan does not open

Retrieve it in SSMS with `qv_report.usp_GetShowplanXml`, click the XML result,
and save as `.sqlplan`. A null plan can be a valid Query Store condition; an
XML value whose root is not the Microsoft Showplan namespace fails the reporting
test. Grafana intentionally does not render plans.

## Capture-grain validation fails

Stop using affected runs for analysis. Run
`Tests/TestQueryStoreAggregationGrain.sql` as a read-only diagnostic, confirm the
procedure still applies the flush cutoff and completed-interval predicate, and
inspect duplicate/orphan results. Do not delete or rewrite archive rows during
diagnosis.

## Production workflow will not run from the branch

This is expected: the current Voyager2 workflow is manual-dispatch and gates the
job to `master`. Review and reconcile the branch, merge only after approval, and
then manually dispatch the reviewed commit. Do not bypass the branch gate.

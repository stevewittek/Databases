/* Investigation leads, not automatic diagnoses or tuning instructions. */
DECLARE @RunID INT=NULL;
IF @RunID IS NULL THROW 51242,'Set an explicit @RunID.',1;
SELECT * FROM qv_report.run_quality WHERE period_id=@RunID;
-- Workload concentration: cumulative worker time does not measure server utilization.
SELECT TOP (30) q.query_id,q.execution_count,q.total_cpu_ms,q.avg_cpu_ms,q.avg_duration_ms,
    100.0*q.total_cpu_ms/NULLIF(m.total_cpu_ms,0) AS workload_cpu_share_pct,
    q.plan_count,q.query_text_preview
FROM qv_report.query_period_metrics AS q
INNER JOIN qv_report.period_metrics AS m ON m.period_id=q.period_id
WHERE q.period_id=@RunID ORDER BY q.total_cpu_ms DESC,q.query_id;
-- Plan multiplicity is a lead. Multiple plans can be intentional (including SQL 2022 PSP).
SELECT query_id,plan_count,avg_duration_ms,total_duration_ms,query_text_preview
FROM qv_report.query_period_metrics WHERE period_id=@RunID AND plan_count>1
ORDER BY total_duration_ms DESC,query_id;
-- Non-success outcomes warrant application/timeout correlation; no blocking claim is inferred.
SELECT query_id,execution_type,execution_type_desc,SUM(execution_count) AS executions,SUM(total_duration_ms) AS duration_ms
FROM qv_report.query_interval_metrics WHERE period_id=@RunID AND execution_type<>0
GROUP BY query_id,execution_type,execution_type_desc ORDER BY executions DESC,query_id;
-- Wait categories support investigation, not exact wait type or blocker attribution.
SELECT TOP (50) query_id,wait_category_desc,total_wait_ms,query_text_preview
FROM qv_report.query_wait_period_metrics WHERE period_id=@RunID ORDER BY total_wait_ms DESC,query_id;

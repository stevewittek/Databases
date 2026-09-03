/*
	Plan inventory. showplan_xml remains native SQL Server Showplan XML; QueryVault
	does not interpret or render it.
*/

CREATE VIEW qv_report.query_plans
AS
	SELECT
		p.RunID AS period_id,
		pr.source_server_name,
		pr.source_database_name,
		p.query_id,
		p.plan_id,
		CONVERT(VARCHAR(18), p.query_plan_hash, 1) AS query_plan_hash_hex,
		p.engine_version,
		p.compatibility_level,
		p.is_parallel_plan,
		p.is_forced_plan,
		p.is_trivial_plan,
		p.plan_forcing_type_desc,
		p.plan_type_desc,
		p.initial_compile_start_time,
		p.last_compile_start_time,
		p.last_execution_time,
		TRY_CONVERT(XML, p.query_plan) AS showplan_xml
	FROM dbo.query_store_plan AS p
	INNER JOIN qv_report.periods AS pr
		ON pr.period_id = p.RunID;
GO

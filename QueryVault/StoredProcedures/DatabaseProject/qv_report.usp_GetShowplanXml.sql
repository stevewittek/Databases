CREATE PROCEDURE qv_report.usp_GetShowplanXml
	@PeriodID INT,
	@QueryID BIGINT = NULL,
	@PlanID BIGINT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF @QueryID IS NULL AND @PlanID IS NULL
		THROW 51020, 'Specify @QueryID or @PlanID.', 1;

	SELECT
		period_id,
		query_id,
		plan_id,
		query_plan_hash_hex,
		showplan_xml
	FROM qv_report.query_plans
	WHERE period_id = @PeriodID
		AND (@QueryID IS NULL OR query_id = @QueryID)
		AND (@PlanID IS NULL OR plan_id = @PlanID)
	ORDER BY plan_id;
END
GO

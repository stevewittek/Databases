// Power Query function. Invoke from Power BI Desktop or Excel Power Query.
// Authenticate through the host credential dialog. No passwords belong in M.
(Server as text, Database as text, BaselineRunID as number, CandidateRunID as number) as record =>
let
    Source = Sql.Database(Server, Database, [CreateNavigationProperties=false]),
    Parameters = [b=Int32.From(BaselineRunID), c=Int32.From(CandidateRunID)],
    Quality = Value.NativeQuery(Source, "SELECT * FROM qv_report.fn_CompareRunQuality(@b,@c)", Parameters),
    Runs = Value.NativeQuery(Source, "SELECT * FROM qv_report.run_quality WHERE period_id IN (@b,@c)", Parameters),
    Queries = Value.NativeQuery(Source, "SELECT * FROM qv_report.fn_CompareRuns(@b,@c)", Parameters),
    Waits = Value.NativeQuery(Source, "SELECT * FROM qv_report.fn_CompareWaits(@b,@c)", Parameters)
in
    [Quality=Quality, Runs=Runs, Queries=Queries, Waits=Waits]

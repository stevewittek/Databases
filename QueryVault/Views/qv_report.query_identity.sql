SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Stronger evidence than query_id or query_hash alone. Text digest never exposes restricted text. */
CREATE OR ALTER VIEW qv_report.query_identity
AS
SELECT q.RunID AS period_id, q.query_id, q.context_settings_id, q.object_id, q.query_hash,
    q.initial_compile_start_time,
    CASE WHEN t.is_part_of_encrypted_module=0 AND t.has_restricted_text=0
        THEN HASHBYTES('SHA2_256', t.query_sql_text) ELSE NULL END AS text_digest
FROM dbo.query_store_query AS q
INNER JOIN dbo.query_store_query_text AS t ON t.RunID=q.RunID AND t.query_text_id=q.query_text_id;
GO

import argparse
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


collector = load("collector", "collector/queryvault_collect.py")
package = load("package", "tools/package_queryvault.py")
deploy = load("deploy", "tools/deploy_queryvault.py")


class CollectorTests(unittest.TestCase):
    def fake_connection(self):
        data = {
            "query_store_runtime_stats_interval": [{"runtime_stats_interval_id": 5}],
            "query_store_runtime_stats": [{"plan_id": 3, "runtime_stats_interval_id": 5, "new_metric": 17}],
            "query_store_plan": [{"plan_id": 3, "query_id": 2}],
            "query_store_query": [{"query_id": 2, "query_text_id": 1}],
            "query_store_query_text": [{"query_text_id": 1}],
        }

        class Connection:
            def cursor(self):
                return self

            def execute(self, sql, *parameters):
                self.sql = sql
                if "FROM sys.[" in sql:
                    view = re.search(r"FROM sys\.\[(\w+)\]", sql)[1]
                    self.rows = data[view][:]
                    self.description = [(name,) for name in self.rows[0]]
                return self

            def fetchone(self):
                return dt.datetime(2026, 11, 20), 900

            def fetchall(self):
                return [(view, name, "bigint") for view, rows in data.items() for name in rows[0]]

            def fetchmany(self, size):
                rows, self.rows = self.rows, []
                return [tuple(row.values()) for row in rows]

        return Connection()

    def test_collect_missing_waits_retains_new_metric(self):
        config = {"source_id": "11111111-1111-4111-8111-111111111111", "source_epoch": "22222222-2222-4222-8222-222222222222", "server": "lab", "database": "db"}
        with tempfile.TemporaryDirectory() as temp:
            batch = collector.collect(self.fake_connection(), config, collector.utc("2026-11-01T00:00:00Z"), collector.utc("2026-11-01T01:00:00Z"), Path(temp))
            manifest = json.loads((batch / "manifest.json").read_text())
            self.assertIn("query_store_wait_stats", manifest["metadata"]["unavailable_views"])
            record = json.loads((batch / "query_store_runtime_stats.jsonl").read_text())
            self.assertEqual(record["new_metric"], 17)

    def test_collect_limit_and_future_end_leave_no_batch(self):
        config = {"source_id": "11111111-1111-4111-8111-111111111111", "source_epoch": "22222222-2222-4222-8222-222222222222", "server": "lab", "database": "db"}
        with tempfile.TemporaryDirectory() as temp:
            for end, limit in [("2026-11-01T01:00:00Z", 0), ("2027-01-01T00:00:00Z", 100)]:
                with self.assertRaises(ValueError):
                    collector.collect(self.fake_connection(), config, collector.utc("2026-11-01T00:00:00Z"), collector.utc(end), Path(temp), max_rows=limit)
                self.assertEqual(list(Path(temp).iterdir()), [])

    def test_window_requires_offset_and_normalizes(self):
        self.assertEqual(collector.utc("2026-11-20T01:00:00-05:00"), collector.utc("2026-11-20T06:00:00Z"))
        with self.assertRaises(ValueError):
            collector.utc("2026-11-20T00:00:00")

    def test_odbc_fields_cannot_override_tls(self):
        value = collector.connection_string({"server": "x};Encrypt=no;", "database": "test"})
        self.assertIn("Server={x}};Encrypt=no;}", value)
        self.assertIn("TrustServerCertificate={no}", value)
        self.assertIn("Encrypt={yes}", value)

    def test_no_secret_literal_in_config(self):
        with patch.dict(os.environ, {"QV_TEST_PASSWORD": "a}b;c"}):
            value = collector.connection_string({"server": "lab", "database": "lab", "authentication": "sql", "user": "reader", "password_env": "QV_TEST_PASSWORD"})
        self.assertIn("PWD={a}}b;c}", value)

    def test_projection_keeps_new_columns_and_offsets(self):
        result = collector.projection([{"name": "new_metric", "type": "bigint"}, {"name": "end_time", "type": "datetimeoffset"}])
        self.assertIn("v.[new_metric]", result)
        self.assertIn("CONVERT(nvarchar(48),v.[end_time],127)", result)

    def test_query_boundaries_and_allowlist(self):
        for view in collector.CORE:
            sql = collector.query(view, [{"name": "id", "type": "int"}])
            self.assertEqual(sql.count("?"), 2)
            self.assertIn("end_time > ?", sql)
            self.assertIn("end_time <= ?", sql)
        with self.assertRaises(ValueError):
            collector.query("objects]; DROP DATABASE x;--", [])

    def test_duplicate_contributors_survive_idempotent_retry(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            metadata = {"columns": {}}
            first = collector.write_batch(root, {"source": "one"}, {"runtime": [{"n": 1}, {"n": 2}, {"n": 1}]}, metadata)
            retry = collector.write_batch(root, {"source": "one"}, {"runtime": [{"n": 1}, {"n": 1}, {"n": 2}]}, metadata)
            self.assertEqual(first, retry)
            self.assertEqual(len((first / "runtime.jsonl").read_text().splitlines()), 3)
            with self.assertRaises(ValueError):
                collector.write_batch(root, {"source": "one"}, {"runtime": [{"n": 3}]}, metadata)
            self.assertEqual(len(list(root.iterdir())), 1)

    def test_source_epoch_changes_batch_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            a = collector.write_batch(Path(temp), {"epoch": "a"}, {}, {"columns": {}})
            b = collector.write_batch(Path(temp), {"epoch": "b"}, {}, {"columns": {}})
            self.assertNotEqual(a, b)

    def test_same_identity_cannot_silently_change_source_endpoint(self):
        with tempfile.TemporaryDirectory() as temp:
            collector.write_batch(Path(temp), {"source": "same"}, {}, {"columns": {}, "source_server": "one"})
            with self.assertRaises(ValueError):
                collector.write_batch(Path(temp), {"source": "same"}, {}, {"columns": {}, "source_server": "two"})

    def test_orphan_rejected(self):
        data = {v: [] for v in collector.CORE}
        data["query_store_runtime_stats"] = [{"plan_id": 1, "runtime_stats_interval_id": 2}]
        with self.assertRaises(ValueError):
            collector.validate_relations(data)


class PackageTests(unittest.TestCase):
    def test_rowstore_preserves_lob_and_partitioning(self):
        sql = (ROOT / "QueryVault/Tables/QueryStore/query_store_plan.sql").read_text()
        converted = package.rowstore_model(sql)
        self.assertNotIn("CREATE CLUSTERED COLUMNSTORE", converted)
        self.assertIn("PRIMARY KEY CLUSTERED (RunID, plan_id)", converted)
        self.assertIn("query_plan NVARCHAR(MAX)", converted)
        self.assertIn("ON PS_RunID(RunID)", converted)

    def test_invalid_2016_columnstore_rejected(self):
        with self.assertRaises(ValueError):
            package.prepare("2016", "columnstore")

    def test_all_switch_pairs_convert_equally(self):
        for path in (ROOT / "QueryVault/Tables/QueryStore").glob("*.sql"):
            for source in (path, ROOT / "QueryVault/Tables/PartitionMaintenance" / (path.stem + "_PartitionMaintenance.sql")):
                converted = package.rowstore_model(source.read_text())
                self.assertNotIn("CREATE CLUSTERED COLUMNSTORE", converted, str(source))
                self.assertIn("PRIMARY KEY CLUSTERED", converted, str(source))

    def test_legacy_optional_projection_tokens_complete(self):
        sql = (ROOT / "QueryVault/StoredProcedures/usp_ArchiveQueryStore.sql").read_text()
        self.assertNotRegex(sql, r"\]_\w+")
        for view, alias, name, sql_type, target in re.findall(r"\(N'(query_store_\w+)', N'(\w+)', N'(\w+)', N'([^']+)', N'(\w+)'\)", sql):
            self.assertIn(alias + ".[" + name + "]", sql)
        self.assertNotIn("SERVERPROPERTY('ProductMajorVersion')", sql)
        self.assertIn("IF @HasWaitStats = 1", sql)
        self.assertIn("@@TRANCOUNT <> 0", sql)

    def test_publish_requires_explicit_empty_target(self):
        with tempfile.NamedTemporaryFile(suffix=".dacpac") as f:
            args = argparse.Namespace(package=Path(f.name), database="TestVault", server="localhost", authentication="integrated", sqlpackage="sqlpackage", action="Publish", empty_database=False)
            with self.assertRaises(ValueError):
                deploy.command(args)
            args.empty_database = True
            cmd = deploy.command(args)
            self.assertIn("/p:BlockOnPossibleDataLoss=True", cmd)
            args.database = "master"
            with self.assertRaises(ValueError):
                deploy.command(args)


if __name__ == "__main__":
    unittest.main()

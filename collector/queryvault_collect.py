#!/usr/bin/env python3
"""Experimental read-only outbound collector. Creates a local batch; does not ingest it."""
import argparse
import datetime as dt
import decimal
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import uuid

UTC = dt.timezone.utc
CORE = ("query_store_runtime_stats_interval", "query_store_runtime_stats",
        "query_store_plan", "query_store_query", "query_store_query_text")
OPTIONAL = ("query_store_wait_stats", "query_context_settings", "database_query_store_options",
            "query_store_query_variant", "query_store_query_hints", "query_store_replicas",
            "query_store_plan_forcing_locations")
CAPACITY = ("dm_db_resource_stats", "database_service_objectives")
ALLOWED = CORE + OPTIONAL + CAPACITY


def utc(value):
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("A UTC offset is required on every window endpoint.")
    return parsed.astimezone(UTC)


def odbc_value(value):
    return "{" + str(value).replace("}", "}}") + "}"


def connection_string(config):
    """Construct from separate fields: never accept an executable/opaque connection string."""
    parts = {"Driver": "ODBC Driver 18 for SQL Server", "Server": config["server"],
             "Database": config["database"], "Encrypt": "yes", "TrustServerCertificate": "no",
             "Application Name": "QueryVault read-only collector"}
    auth = config.get("authentication", "integrated")
    if auth == "sql":
        parts.update(UID=config["user"], PWD=os.environ[config["password_env"]])
    elif auth == "entra-default":
        raise ValueError("ODBC has no ActiveDirectoryDefault mode. Use integrated or an explicitly configured SQL lab account; token authentication is pending.")
    elif auth == "integrated":
        parts["Trusted_Connection"] = "yes"
    else:
        raise ValueError("Unsupported authentication mode")
    return ";".join(k + "=" + odbc_value(v) for k, v in parts.items())


def encoded(value):
    if isinstance(value, bytes):
        return {"$binary_hex": value.hex()}
    if isinstance(value, decimal.Decimal):
        return {"$decimal": str(value)}
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat()
    raise TypeError("Unsupported SQL value type: " + type(value).__name__)


def json_bytes(value):
    return json.dumps(value, default=encoded, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def projection(columns):
    result = []
    for column in columns:
        name = "[" + column["name"].replace("]", "]]") + "]"
        # pyodbc does not natively decode SQL_SS_TIMESTAMPOFFSET on every platform.
        result.append("CONVERT(nvarchar(48),v." + name + ",127) AS " + name
                      if column["type"] == "datetimeoffset" else "v." + name)
    return ",".join(result)


def query(view, columns):
    if view not in ALLOWED:
        raise ValueError("View is outside the collector allowlist")
    window = "i.end_time > ? AND i.end_time <= ?"
    plans = ("SELECT r.plan_id FROM sys.query_store_runtime_stats r "
             "JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id=r.runtime_stats_interval_id WHERE " + window)
    queries = "SELECT p.query_id FROM sys.query_store_plan p WHERE p.plan_id IN (" + plans + ")"
    where = {
        "query_store_runtime_stats_interval": "v.end_time > ? AND v.end_time <= ?",
        "query_store_runtime_stats": "v.runtime_stats_interval_id IN (SELECT i.runtime_stats_interval_id FROM sys.query_store_runtime_stats_interval i WHERE " + window + ")",
        "query_store_wait_stats": "v.runtime_stats_interval_id IN (SELECT i.runtime_stats_interval_id FROM sys.query_store_runtime_stats_interval i WHERE " + window + ")",
        "query_store_plan": "v.plan_id IN (" + plans + ")",
        "query_store_query": "v.query_id IN (" + queries + ")",
        "query_store_query_text": "v.query_text_id IN (SELECT q.query_text_id FROM sys.query_store_query q WHERE q.query_id IN (" + queries + "))",
        "query_context_settings": "v.context_settings_id IN (SELECT q.context_settings_id FROM sys.query_store_query q WHERE q.query_id IN (" + queries + "))",
    }
    return "SELECT " + projection(columns) + " FROM sys.[" + view + "] v" + (" WHERE " + where[view] if view in where else "")


def validate_relations(data):
    """Reject observed catalog-cleanup races; this does not claim an atomic source snapshot."""
    intervals = {r["runtime_stats_interval_id"] for r in data[CORE[0]]}
    plans = {r["plan_id"] for r in data["query_store_plan"]}
    queries = {r["query_id"] for r in data["query_store_query"]}
    texts = {r["query_text_id"] for r in data["query_store_query_text"]}
    for view in ("query_store_runtime_stats", "query_store_wait_stats"):
        for row in data.get(view, []):
            if row["plan_id"] not in plans or row["runtime_stats_interval_id"] not in intervals:
                raise ValueError("Source changed during capture: orphan statistic; retry the window")
    if any(r["query_id"] not in queries for r in data["query_store_plan"]):
        raise ValueError("Source changed during capture: orphan plan")
    if any(r["query_text_id"] not in texts for r in data["query_store_query"]):
        raise ValueError("Source changed during capture: orphan query text")


def write_batch(root, identity, data, metadata):
    """Deterministic multiset payloads preserve duplicate contributors and detect conflicts."""
    batch_id = hashlib.sha256(json_bytes(identity)).hexdigest()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    staging = Path(tempfile.mkdtemp(prefix=".pending-", dir=root))
    try:
        files = {}
        for view, rows in sorted(data.items()):
            payload = b"".join(row + b"\n" for row in sorted(json_bytes(r) for r in rows))
            path = staging / (view + ".jsonl")
            path.write_bytes(payload)
            path.chmod(0o600)
            files[path.name] = {"rows": len(rows), "sha256": hashlib.sha256(payload).hexdigest()}
        manifest = {"format_version": 1, "batch_id": batch_id, "identity": identity,
                    "files": files, "metadata": metadata, "state": "READY_FOR_REVIEW_NOT_INGESTED"}
        target = root / batch_id
        if target.exists():
            previous = json.loads((target / "manifest.json").read_text())
            # A repeated window is not automatically a new run or a silent overwrite.
            identity_fields = ("columns", "source_server", "source_database")
            if previous["files"] != files or any(previous["metadata"].get(key) != metadata.get(key) for key in identity_fields):
                raise ValueError("Conflicting retry for the same source epoch/window; preserve the original batch and reconcile explicitly")
            return target
        (staging / "manifest.json").write_bytes(json_bytes(manifest) + b"\n")
        (staging / "manifest.json").chmod(0o600)
        staging.rename(target)
        return target
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def collect(connection, config, start, end, root, include_capacity=False, max_rows=100000, max_bytes=67108864):
    if start >= end:
        raise ValueError("Start must precede end")
    source_id, epoch = str(uuid.UUID(config["source_id"])), str(uuid.UUID(config["source_epoch"]))
    cursor = connection.cursor()
    cursor.timeout = 60
    now, flush = cursor.execute("SELECT SYSUTCDATETIME(), flush_interval_seconds FROM sys.database_query_store_options").fetchone()
    cutoff = now.replace(tzinfo=UTC) - dt.timedelta(seconds=flush or 900)
    if end > cutoff:
        raise ValueError("End exceeds the source's safely flushed cutoff; select an earlier explicit endpoint")
    catalog = cursor.execute("SELECT o.name,c.name,t.name FROM sys.all_objects o JOIN sys.all_columns c ON c.object_id=o.object_id JOIN sys.types t ON t.user_type_id=c.user_type_id JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE s.name=N'sys' ORDER BY o.name,c.column_id").fetchall()
    columns = {}
    for view, name, sql_type in catalog:
        if view in ALLOWED:
            columns.setdefault(view, []).append({"name": name, "type": sql_type})
    if any(view not in columns for view in CORE):
        raise ValueError("Required Query Store catalog is missing or inaccessible")
    selected = CORE + OPTIONAL + (CAPACITY if include_capacity else ())
    data, total_rows, total_bytes = {}, 0, 0
    for view in selected:
        if view not in columns:
            continue
        statement = query(view, columns[view])
        params = (start.replace(tzinfo=None), end.replace(tzinfo=None)) if "?" in statement else ()
        cursor.execute(statement, *params)
        names = [c[0] for c in cursor.description]
        data[view] = []
        while True:
            rows = cursor.fetchmany(500)
            if not rows:
                break
            for row in rows:
                record = dict(zip(names, row))
                total_rows += 1
                total_bytes += len(json_bytes(record))
                if total_rows > max_rows or total_bytes > max_bytes:
                    raise ValueError("Batch limit exceeded; use a smaller window")
                data[view].append(record)
    validate_relations(data)
    identity = {"source_id": source_id, "source_epoch": epoch, "start_utc": start.isoformat(), "end_utc": end.isoformat(),
                "include_capacity": include_capacity}
    metadata = {"source_server": config["server"], "source_database": config["database"],
                "captured_utc": dt.datetime.now(UTC).isoformat(), "columns": {v: columns[v] for v in data},
                "unavailable_views": [v for v in selected if v not in columns],
                "consistency": "Sequential catalog reads with relation checks; not a transactionally consistent Query Store snapshot",
                "auxiliary_scope": "Options, hints, variants, replicas, forcing locations and capacity are current snapshots, not historic window facts"}
    return write_batch(root, identity, data, metadata)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--start", type=utc, required=True)
    parser.add_argument("--end", type=utc, required=True)
    parser.add_argument("--spool", type=Path, default=Path("artifacts/spool"))
    parser.add_argument("--include-capacity", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    try:
        import pyodbc
        with pyodbc.connect(connection_string(config), timeout=15, autocommit=True) as connection:
            print(collect(connection, config, args.start, args.end, args.spool, args.include_capacity))
    except Exception as error:
        # Driver exceptions can echo endpoints, SQL text or authentication details.
        print("Collection failed (" + type(error).__name__ + "). No destination writes were attempted. Check configuration, permissions, window and batch limits.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

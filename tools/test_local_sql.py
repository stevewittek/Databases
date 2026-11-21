#!/usr/bin/env python3
"""Run existing SQL assertions only in an explicitly named disposable Docker lab."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def expand_test(path):
    result = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith(":r "):
            include = (path.parent / line[3:].strip().replace("\\", "/")).resolve()
            # Fresh full schema already contains these tables; preserve the SQL
            # assertions but omit the historical additive table bootstrap.
            if "/Tables/" not in str(include):
                result.append(expand_test(include))
        else:
            result.append(line)
    return "\n".join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--schema", type=Path, default=ROOT / "artifacts/2022-columnstore/model")
    parser.add_argument("--database", choices=["QueryVaultDB", "QueryVaultRowstoreLab"], default="QueryVaultDB")
    parser.add_argument("--initialize", action="store_true")
    parser.add_argument("--capture-fixture", action="store_true", help="Capture completed workload from existing QueryVaultLabSource")
    args = parser.parse_args()
    if not re.fullmatch(r"queryvault-compat-test(?:-[a-z0-9]+)?", args.container):
        raise ValueError("Only disposable queryvault-compat-test container names are accepted")
    env = dict(os.environ, SQLCMDPASSWORD=os.environ["QV_TEST_SQL_PASSWORD"])
    command = ["docker", "exec", "-i", "-e", "SQLCMDPASSWORD", args.container,
               "/opt/mssql-tools18/bin/sqlcmd", "-S", "localhost", "-U", "sa", "-C", "-I", "-b", "-l", "30"]
    log = ROOT / "artifacts/local-sql-tests.log"

    def execute(name, sql):
        sql = sql.replace("QueryVaultDB", args.database)
        result = subprocess.run(command, input=sql, env=env, capture_output=True, text=True)
        with log.open("a") as file:
            file.write("\n" + name + "\n" + result.stdout + result.stderr)
        if result.returncode:
            print(result.stdout[-3000:] + result.stderr)
            raise RuntimeError(name + " failed; see artifacts/local-sql-tests.log")
        print(name + ": PASS", flush=True)

    if args.initialize:
        manifest = ET.parse(ROOT / "QueryVault/QueryVault.sqlproj")
        paths = [i.attrib["Include"].replace("\\", "/") for i in manifest.findall(".//{http://schemas.microsoft.com/developer/msbuild/2003}Build")]
        order = {"Partitions": 0, "Tables": 1, "Functions": 2, "Schemas": 3, "StoredProcedures": 4, "Views": 5}
        paths.sort(key=lambda x: order[x.split("/")[0]])
        sql = "IF DB_ID(N'QueryVaultDB') IS NOT NULL THROW 51091, 'Lab database already exists; refusing overwrite.', 1;\nGO\nCREATE DATABASE QueryVaultDB;\nGO\nUSE QueryVaultDB;\nGO\n"
        sql += "\nGO\n".join((args.schema / p).read_text(encoding="utf-8-sig") for p in paths)
        execute("Fresh schema", sql)

    if args.capture_fixture:
        execute("Live source capture", """USE QueryVaultDB;
EXEC dbo.usp_InitializeDatabase @DatabaseName=N'QueryVaultLabSource';
DECLARE @End datetime2=DATEADD(MINUTE,-2,SYSUTCDATETIME());
EXEC dbo.usp_ArchiveQueryStore @SourceDatabaseName=N'QueryVaultLabSource',
 @RunName=N'Compatibility live source', @StartDateTime='2026-01-01', @EndDateTime=@End;
IF NOT EXISTS (SELECT 1 FROM dbo.query_store_runtime_stats_contributor)
 THROW 51990, 'Lab workload has no safely closed runtime data yet.', 1;
""")
        execute("Capability fallback fixture", (ROOT / "QueryVault/Tests/TestSourceCapabilityFallback.sql").read_text())

    for name in ["TestCanonicalQueryStoreAggregation", "TestPartitionSafetyGuards", "TestRunPartitionLifecycle", "TestPurgeExpiredArchives", "TestReportingContract", "TestReportingCanonicalRegression", "TestPlanIntervalReporting", "TestCollectionRegistry", "TestRunProtection", "TestRetentionPeriodExpiry", "TestPurgeInputValidation"]:
        execute(name, "USE QueryVaultDB;\nGO\n" + expand_test(ROOT / "QueryVault/Tests" / (name + ".sql")))

    execute("Ambient transaction guard", """USE QueryVaultDB;
SET XACT_ABORT ON;
BEGIN TRAN;
BEGIN TRY
 EXEC dbo.usp_ArchiveQueryStore @SourceDatabaseName=N'none', @RunName=N'guard';
 THROW 51999, 'Expected ambient transaction rejection.', 1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER() <> 51006 THROW;
 IF @@TRANCOUNT <> 1 OR XACT_STATE() <> 1
  THROW 51998, 'Caller transaction was rolled back or made uncommittable.', 1;
 IF (@@OPTIONS & 16384) = 0
  THROW 51997, 'Caller XACT_ABORT ON was not restored.', 1;
END CATCH;
ROLLBACK;
""")


if __name__ == "__main__":
    main()

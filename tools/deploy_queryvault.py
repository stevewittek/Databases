#!/usr/bin/env python3
"""SqlPackage CLI wrapper. Default: deployment report. Publish is explicit, empty databases only."""
import argparse
from pathlib import Path
import subprocess


def command(args):
    if args.database.lower() in {"master", "model", "msdb", "tempdb"}:
        raise ValueError("A dedicated QueryVault database is required")
    if not args.package.is_file():
        raise ValueError("Build the DACPAC first")
    # Integrated/Entra authentication avoids placing passwords or tokens on the command line.
    def quoted(value):
        return '"' + value.replace('"', '""') + '"'
    connection = "Server=" + quoted(args.server) + ";Database=" + quoted(args.database) + ";Encrypt=True;TrustServerCertificate=False;"
    connection += "Authentication=Active Directory Default;" if args.authentication == "entra" else "Integrated Security=True;"
    result = [args.sqlpackage, "/Action:" + args.action, "/SourceFile:" + str(args.package.resolve()),
              "/TargetConnectionString:" + connection,
              "/p:BlockOnPossibleDataLoss=True", "/p:DropObjectsNotInSource=False",
              "/p:ScriptDatabaseOptions=False"]
    if args.action != "Publish":
        result.append("/OutputPath:" + str(args.output.resolve()))
    elif not args.empty_database:
        raise ValueError("Publish requires --empty-database; upgrades use reviewed migration scripts")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--authentication", choices=["integrated", "entra"], default="integrated")
    parser.add_argument("--action", choices=["DeployReport", "Script", "Publish"], default="DeployReport")
    parser.add_argument("--output", type=Path, default=Path("artifacts/deployment-report.xml"))
    parser.add_argument("--empty-database", action="store_true")
    parser.add_argument("--sqlpackage", default="sqlpackage")
    args = parser.parse_args()
    argv = command(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(argv, check=True)


if __name__ == "__main__":
    main()

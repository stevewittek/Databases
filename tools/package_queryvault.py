#!/usr/bin/env python3
"""Build a portable DACPAC from the authoritative SSDT manifest; never connects to SQL."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NS = {"m": "http://schemas.microsoft.com/developer/msbuild/2003"}
TARGETS = {
    "2016": ("Sql130", "130.0.2"),
    "2017": ("Sql140", "140.0.4"),
    "2019": ("Sql150", "150.1.2"),
    "2022": ("Sql160", "160.2.8"),
    "2025": ("Sql170", "170.0.4"),
    "azure": ("SqlAzureV12", "170.0.4"),
}


def rowstore_model(sql):
    """Fresh-install profile only. Preserve every column, key and partition scheme."""
    sql = re.sub(r"CREATE CLUSTERED COLUMNSTORE INDEX\b[^;]*;", "", sql, flags=re.I)
    return sql.replace("PRIMARY KEY NONCLUSTERED", "PRIMARY KEY CLUSTERED")


def source_provenance(root):
    if (root / ".git").exists():
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip())
        return {"git_revision": revision, "working_tree_dirty": dirty}

    manifest = root / "HANDOFF_MANIFEST.json"
    if not manifest.is_file():
        raise ValueError("Use a Git checkout or a verified QueryVault handoff snapshot.")
    raw = manifest.read_bytes()
    snapshot = json.loads(raw)
    verified = set()
    for item in snapshot["files"]:
        relative = Path(item["path"])
        source = root / relative
        if relative.is_absolute() or ".." in relative.parts or not source.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"Invalid handoff path: {relative}")
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError(f"Handoff file missing or changed: {relative}. Extract a fresh copy or build edits in a Git worktree.")
        verified.add(relative.as_posix())

    project_file = "QueryVault/QueryVault.sqlproj"
    required = {project_file}
    project = ET.parse(root / project_file)
    required.update("QueryVault/" + item.attrib["Include"].replace("\\", "/")
                    for item in project.findall(".//m:Build", NS))
    if not required.issubset(verified):
        raise ValueError("Handoff manifest does not cover all SQL project build inputs.")
    return {"git_revision": snapshot["git_revision"], "working_tree_dirty": None,
            "source_kind": "verified handoff (git_revision is the snapshot base)",
            "handoff_manifest_sha256": hashlib.sha256(raw).hexdigest()}


def prepare(target, storage):
    if target == "2016" and storage != "rowstore":
        raise ValueError("SQL Server 2016 cannot store MAX text/plan columns in clustered columnstore; use rowstore.")
    out = ROOT / "artifacts" / (target + "-" + storage)
    model = out / "model"
    if model.exists():
        shutil.rmtree(model)
    model.mkdir(parents=True)
    manifest = ET.parse(ROOT / "QueryVault/QueryVault.sqlproj")
    files = []
    for item in manifest.findall(".//m:Build", NS):
        relative = item.attrib["Include"].replace("\\", "/")
        source = ROOT / "QueryVault" / relative
        destination = model / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        text = source.read_text(encoding="utf-8-sig")
        destination.write_text(rowstore_model(text) if storage == "rowstore" else text)
        files.append({"path": relative, "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    provider, version = TARGETS[target]
    package = "Microsoft.SqlServer.Dacpacs." + ("Azure.Master" if target == "azure" else "Master")
    project = model / "QueryVault.sqlproj"
    # A static partition model must never reset a live archive's dynamic boundaries.
    (model / "FreshInstallGuard.sql").write_text("""IF EXISTS (SELECT 1 FROM sys.tables WHERE is_ms_shipped = 0)
    THROW 51090, 'This package is for an empty database only. Existing archives require a reviewed migration.', 1;
GO
""")
    project.write_text(f'''<Project DefaultTargets="Build">
  <Sdk Name="Microsoft.Build.Sql" Version="2.3.0" />
  <PropertyGroup>
    <Name>QueryVault</Name>
    <DSP>Microsoft.Data.Tools.Schema.Sql.{provider}DatabaseSchemaProvider</DSP>
    <ModelCollation>1033, CI</ModelCollation>
    <TreatTSqlWarningsAsErrors>true</TreatTSqlWarningsAsErrors>
  </PropertyGroup>
  <ItemGroup>
    <Build Remove="FreshInstallGuard.sql" />
    <PreDeploy Include="FreshInstallGuard.sql" />
    <PackageReference Include="{package}" Version="{version}">
      <DatabaseVariableLiteralValue>master</DatabaseVariableLiteralValue>
    </PackageReference>
  </ItemGroup>
</Project>
''')
    return out, project, files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=TARGETS, default="2019")
    parser.add_argument("--storage", choices=["rowstore", "columnstore"], default="rowstore")
    args = parser.parse_args()
    provenance = source_provenance(ROOT)
    out, project, files = prepare(args.target, args.storage)
    subprocess.run(["dotnet", "build", str(project), "-c", "Release", "--nologo"], check=True)
    artifact = out / "QueryVault.dacpac"
    dependencies = {}
    for built in (project.parent / "bin/Release").glob("*.dacpac"):
        shutil.copyfile(built, out / built.name)
        dependencies[built.name] = hashlib.sha256(built.read_bytes()).hexdigest()
    receipt = {"target": args.target, "storage": args.storage, **provenance,
               "sdk": "Microsoft.Build.Sql/2.3.0",
               "deployment_scope": "Empty databases only; predeployment guard rejects existing user tables",
               "package_files": dependencies,
               "files": files, "dacpac_sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
               "validation": "Compiled only. Live deployment and collection require integration tests."}
    (out / "manifest.json").write_text(json.dumps(receipt, indent=2) + "\n")
    bundle = out / ("QueryVault-" + args.target + "-" + args.storage + ".zip")
    with zipfile.ZipFile(bundle, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(dependencies):
            archive.write(out / name, name)
        archive.write(out / "manifest.json", "manifest.json")
    print(bundle)


if __name__ == "__main__":
    main()

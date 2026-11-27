#!/usr/bin/env python3
"""Package the current source snapshot for Voyager work orders. Excludes secrets and runtime artifacts."""
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
ALLOWED_ROOTS={'QueryVault','docs','grafana','reports','workload','tools','tests','collector','.github'}
ALLOWED_EXTENSIONS={'.md','.sql','.py','.ps1','.sh','.json','.yaml','.yml','.sqlproj','.pq','.txt'}


def main():
    paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
    files=[]
    for relative in sorted(set(paths)):
        if not relative:continue
        path=Path(relative)
        if path.parts[0] not in ALLOWED_ROOTS and relative!='README.md':continue
        if path.suffix.lower() not in ALLOWED_EXTENSIONS:continue
        if any(part in {'bin','obj','__pycache__','node_modules'} for part in path.parts):continue
        source=ROOT/path
        if not source.is_file() or source.is_symlink():continue
        files.append((relative,source))
    if not files:raise SystemExit('No source files selected')
    out=ROOT/'artifacts/QueryVault-Analytics-Source.zip';out.parent.mkdir(exist_ok=True)
    manifest=dict(git_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                  snapshot_kind='Current working tree including uncommitted compatibility and analytics changes',
                  note='Source only. No test results, compiled packages, credentials or live database contents are included.',
                  files=[dict(path=p,sha256=hashlib.sha256(s.read_bytes()).hexdigest()) for p,s in files])
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for relative,source in files:z.write(source,relative)
        z.writestr('HANDOFF_MANIFEST.json',json.dumps(manifest,indent=2)+'\n')
    with zipfile.ZipFile(out) as z:
        if z.testzip():raise RuntimeError('ZIP integrity check failed')
        check=json.loads(z.read('HANDOFF_MANIFEST.json'))
        for f in check['files']:
            if hashlib.sha256(z.read(f['path'])).hexdigest()!=f['sha256']:raise RuntimeError('Snapshot checksum mismatch')
    print(f'{out}: {len(files)} source files; ZIP and SHA-256 checks passed')


if __name__=='__main__':main()

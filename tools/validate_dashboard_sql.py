"""Compile generated dashboard SELECTs against an existing portable SQL model. No SQL connections."""
import argparse
import json,re,shutil,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source-model',type=Path,default=R/'artifacts/2022-columnstore/model')
p.add_argument('--nuget-source',type=Path)
args=p.parse_args()
source=args.source_model.resolve()
if not (source/'QueryVault.sqlproj').is_file():p.error('Prepare the portable SQL model first')
model=R/'artifacts/analytics-sql-validation/model'
if source==model.resolve():p.error('Source model cannot be the validation output')
if model.exists():shutil.rmtree(model)
shutil.copytree(source,model,ignore=shutil.ignore_patterns('bin','obj'))
values=dict(server="N'fixture'",database="N'fixture'",baseline="N'1'",candidate="N'2'",run="N'2'",query="N'-1'",experiment="N'fixture'",min_executions="N'10'",regression_pct="N'20'")
count=0
for f in (R/'grafana/dashboards').glob('*.json'):
 d=json.loads(f.read_text())
 if not d['uid'].startswith('qv-'):continue
 queries=[v['query'] for v in d['templating']['list'] if v['type']=='query']+[t['rawSql'] for p in d['panels'] for t in p.get('targets',[])]
 for sql in queries:
  sql=re.sub(r'\$\{(\w+):sqlstring\}',lambda m:values[m[1]],sql).replace('$__timeFrom()',"'2026-01-01T00:00:00Z'").replace('$__timeTo()',"'2026-02-01T00:00:00Z'")
  sql=re.sub(r'\s+ORDER BY [^;]*;?\s*$','',sql.rstrip(';'))
  count+=1
  (model/f'Panel{count:03}.sql').write_text(f'CREATE VIEW qv_report.__validate_panel_{count:03} AS\n'+sql+';\n')
print('Validating',count,'dashboard queries against the full SQL model',flush=True)
log=R/'artifacts/analytics-sql-validation/semantic.log'
with log.open('w') as out:
 a=subprocess.run(['dotnet','restore',str(model/'QueryVault.sqlproj'),'--disable-build-servers','--nologo']+(['--source',str(args.nuget_source)] if args.nuget_source else []),stdout=out,stderr=subprocess.STDOUT)
 b=subprocess.run(['dotnet','build',str(model/'QueryVault.sqlproj'),'-c','Release','--no-restore','--disable-build-servers','--nologo'],stdout=out,stderr=subprocess.STDOUT) if a.returncode==0 else a
print(log.read_text()[-10000:])
raise SystemExit(b.returncode)

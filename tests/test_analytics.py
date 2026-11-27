"""Analytics package contracts and bounded workload behavior without a SQL server."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('qv_load',ROOT/'workload/run_load.py')
load=importlib.util.module_from_spec(spec);spec.loader.exec_module(load)


class DashboardContracts(unittest.TestCase):
    def test_dashboards_use_public_contract_and_defined_variables(self):
        uids=set()
        for file in sorted((ROOT/'grafana/dashboards').glob('*.json')):
            d=json.loads(file.read_text());self.assertNotIn(d['uid'],uids);uids.add(d['uid'])
            variables={v['name'] for v in d['templating']['list']}
            ids=set()
            statements=[v['query'] for v in d['templating']['list'] if v['type']=='query']
            for p in d['panels']:
                self.assertNotIn(p['id'],ids);ids.add(p['id'])
                for t in p.get('targets',[]):
                    self.assertEqual(t.get('datasource',p['datasource'])['uid'],'queryvault-mssql')
                    statements.append(t['rawSql'])
            for sql in statements:
                self.assertNotRegex(sql,r'(?i)\b(?:FROM|JOIN)\s+dbo\.')
                self.assertNotRegex(sql,r'(?i)\b(?:INSERT|UPDATE|DELETE|DROP|ALTER|EXEC)\s')
                for name in re.findall(r'\$\{(\w+)(?::[^}]+)?\}',sql):
                    self.assertIn(name,variables)
            if d['uid'].startswith('qv-'):
                for sql in statements:
                    self.assertNotIn(':raw}',sql)
                    self.assertNotIn(':csv}',sql)
        self.assertEqual(len(uids),7)

    def test_no_panel_collisions_in_generated_dashboards(self):
        for file in (ROOT/'grafana/dashboards').glob('*.json'):
            if not json.loads(file.read_text())['uid'].startswith('qv-'):continue
            panels=json.loads(file.read_text())['panels']
            for i,a in enumerate(panels):
                a=a['gridPos']
                for b in panels[i+1:]:
                    b=b['gridPos']
                    self.assertFalse(a['x']<b['x']+b['w'] and b['x']<a['x']+a['w'] and a['y']<b['y']+b['h'] and b['y']<a['y']+a['h'])

    def test_both_models_include_same_analytics_and_deployment_mirrors(self):
        manifests=[]
        for name in ['QueryVault.sqlproj','QueryVault_Fixed.sqlproj']:
            xml=ET.parse(ROOT/'QueryVault'/name)
            paths={n.attrib['Include'].replace('\\','/') for n in xml.findall('.//{http://schemas.microsoft.com/developer/msbuild/2003}Build')}
            manifests.append(paths)
        self.assertEqual(*manifests)
        self.assertEqual(len(manifests[0]),48)
        for path in manifests[0]:
            if '/DatabaseProject/qv_report.' not in path:continue
            model=(ROOT/'QueryVault'/path).read_text().strip()
            operational=(ROOT/'QueryVault'/path.replace('/DatabaseProject/','/')).read_text()
            start=operational.index('CREATE OR ALTER ')
            self.assertEqual(model,operational[start:].replace('CREATE OR ALTER ','CREATE ',1).strip())

    def test_generator_is_reproducible(self):
        spec=importlib.util.spec_from_file_location('qv_dashboards',ROOT/'tools/build_analytics_dashboards.py')
        gen=importlib.util.module_from_spec(spec);spec.loader.exec_module(gen)
        for d in [gen.comparison(),gen.comparison(True),gen.timeline()]:
            file=ROOT/'grafana/dashboards'/('queryvault-'+d['uid'][3:]+'.json')
            self.assertEqual(json.loads(file.read_text()),d)


class BoundedWorkload(unittest.TestCase):
    def args(self,**overrides):
        a=dict(server='localhost',database='QueryVaultLoadLab',driver='ODBC Driver 18 for SQL Server',user=None,
               password_env='QV_LOAD_TEST_PASSWORD',workers=1,duration_seconds=1,query_timeout=1,pause_ms=0,
               max_requests_per_worker=3,experiment='fixture',scenario='predicate',seed=1,variant='baseline',epoch='test-epoch')
        a.update(overrides);return argparse.Namespace(**a)

    def test_requires_named_lab_and_resource_limits(self):
        for override in [dict(database='QueryVaultDB'),dict(database='master'),dict(workers=9),dict(duration_seconds=901),dict(query_timeout=0),dict(max_requests_per_worker=0),dict(scenario='injected-procedure')]:
            with self.assertRaises(ValueError):load.validate(self.args(**override))

    def test_percentiles_are_client_observations_and_empty_is_null(self):
        m=load.summarize([3,1,2,100],0,2)
        self.assertEqual(m['client_p50_ms'],2)
        self.assertEqual(m['client_p95_ms'],100)
        self.assertEqual(m['successful_requests_per_second'],2)
        self.assertIsNone(load.summarize([],1,1)['client_p99_ms'])

    def test_connection_fields_cannot_override_tls(self):
        cs=load.connection_string(self.args(server='host};Encrypt=no;'))
        self.assertIn('SERVER={host}};Encrypt=no;}',cs)
        self.assertIn('Encrypt={yes}',cs)
        self.assertIn('TrustServerCertificate={no}',cs)

    def fake_connect(self,marker=load.MARKER,fail=False):
        outer=self
        class Connection:
            timeout=None
            description=None
            def __enter__(self):return self
            def __exit__(self,*a):return False
            def cursor(self):return self
            def execute(self,sql,*parameters):
                if sql.startswith('EXEC'):
                    outer.calls.append(parameters)
                    if fail:raise RuntimeError('redacted')
                return self
            def fetchone(self):return [marker]
            def fetchall(self):return []
            def nextset(self):return False
        return lambda *a,**kw:Connection()

    def test_marker_gate_rejects_unrecognized_database(self):
        self.calls=[]
        with self.assertRaises(ValueError):load.run(self.args(),self.fake_connect(marker='unrelated'))
        self.assertEqual(self.calls,[])

    def test_request_cap_and_bound_parameters(self):
        self.calls=[]
        r=load.run(self.args(),self.fake_connect())
        self.assertEqual(r['metrics']['successes'],3)
        self.assertEqual(len(self.calls),3)
        self.assertTrue(all(0<=p[0]<=99 and p[1]=='baseline' for p in self.calls))

    def test_first_error_stops_work_and_records_failure(self):
        self.calls=[]
        r=load.run(self.args(),self.fake_connect(fail=True))
        self.assertEqual(r['metrics']['errors'],1)
        self.assertEqual(r['metrics']['successes'],0)
        self.assertEqual(len(self.calls),1)


if __name__=='__main__':unittest.main()

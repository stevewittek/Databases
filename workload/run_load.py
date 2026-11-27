#!/usr/bin/env python3
"""Bounded QueryVault lab workload. Never writes QueryVault archives or alters server settings."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import json
import math
import os
from pathlib import Path
import random
import threading
import time
import uuid

UTC=dt.timezone.utc
MARKER='QueryVault bounded load lab v1'
SCENARIOS={'predicate':'EXEC dbo.qv_lab_probe @Bucket=?, @Variant=?',
           'sort':'EXEC dbo.qv_lab_sort @Bucket=?, @Variant=?'}


def connection_string(args):
    def field(value):return '{'+str(value).replace('}','}}')+'}'
    parts={'DRIVER':args.driver,'SERVER':args.server,'DATABASE':args.database,
           'Encrypt':'yes','TrustServerCertificate':'no','APP':'QueryVaultLoadLab'}
    if args.user:
        password=os.environ.get(args.password_env)
        if not password:raise ValueError('SQL authentication password environment variable is not set')
        parts.update(UID=args.user,PWD=password)
    else:parts['Trusted_Connection']='yes'
    return ';'.join(k+'='+field(v) for k,v in parts.items())+';'


def validate(args):
    if args.scenario not in SCENARIOS:raise ValueError('Unknown workload scenario')
    if args.database!='QueryVaultLoadLab':raise ValueError('Only the explicitly created QueryVaultLoadLab database is accepted')
    if not 1<=args.workers<=8:raise ValueError('Workers must be 1..8')
    if not 1<=args.duration_seconds<=900:raise ValueError('Duration must be 1..900 seconds')
    if not 1<=args.query_timeout<=15:raise ValueError('Query timeout must be 1..15 seconds')
    if not 0<=args.pause_ms<=10000:raise ValueError('Pause must be 0..10000 ms')
    if not 1<=args.max_requests_per_worker<=100000:raise ValueError('Maximum requests per worker must be 1..100000')
    if not args.experiment.strip():raise ValueError('Experiment name is required')


def summarize(samples,errors,seconds):
    ordered=sorted(samples)
    def pct(p):return ordered[max(0,math.ceil(len(ordered)*p)-1)] if ordered else None
    return dict(successes=len(samples),errors=errors,elapsed_seconds=seconds,
                successful_requests_per_second=len(samples)/seconds if seconds else None,
                client_mean_ms=sum(samples)/len(samples) if samples else None,
                client_p50_ms=pct(.50),client_p95_ms=pct(.95),client_p99_ms=pct(.99))


def run(args,connect):
    validate(args)
    connection=connection_string(args)
    # Preflight before any workload, using the same TLS and credential options.
    with connect(connection,autocommit=True,timeout=10) as cn:
        cn.timeout=args.query_timeout
        marker=cn.cursor().execute('SELECT Marker FROM dbo.QueryVaultLabMarker').fetchone()
        if not marker or marker[0]!=MARKER:raise ValueError('Lab marker missing or unrecognized')
    stop=threading.Event()
    started=dt.datetime.now(UTC)
    start=time.monotonic();deadline=start+args.duration_seconds
    def worker(index):
        samples=[];errors=0
        rng=random.Random(args.seed+index)
        try:
            with connect(connection,autocommit=True,timeout=10) as cn:
                cn.timeout=args.query_timeout
                cursor=cn.cursor()
                while not stop.is_set() and time.monotonic()<deadline and len(samples)+errors<args.max_requests_per_worker:
                    begin=time.monotonic()
                    try:
                        cursor.execute(SCENARIOS[args.scenario],rng.randrange(100),args.variant)
                        while True:
                            if cursor.description:cursor.fetchall()
                            if not cursor.nextset():break
                        samples.append((time.monotonic()-begin)*1000)
                    except Exception:
                        errors+=1
                        # Stop all workers on the first SQL error; report counts, not connection details.
                        stop.set();break
                    if args.pause_ms:stop.wait(min(args.pause_ms/1000,max(0,deadline-time.monotonic())))
        except Exception:
            errors+=1;stop.set()
        return samples,errors
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        try:results=list(pool.map(worker,range(args.workers)))
        except KeyboardInterrupt:
            stop.set();raise
    ended=dt.datetime.now(UTC)
    samples=[s for result,_ in results for s in result]
    receipt=dict(schema_version=1,experiment=args.experiment,scenario=args.scenario,variant=args.variant,seed=args.seed,
                 workers=args.workers,pause_ms=args.pause_ms,max_requests_per_worker=args.max_requests_per_worker,server=args.server,database=args.database,
                 client_start_utc=started.isoformat(),client_end_utc=ended.isoformat(),
                 query_store_epoch=args.epoch,
                 metrics=summarize(samples,sum(e for _,e in results),time.monotonic()-start),
                 note='Client percentiles are measured request latency including network overhead; Query Store percentiles are unavailable. Archive only fully contained completed intervals after flush grace. Use SQL server UTC boundaries, not an unsynchronized client clock.')
    return receipt


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--server',required=True)
    p.add_argument('--database',default='QueryVaultLoadLab')
    p.add_argument('--driver',default='ODBC Driver 18 for SQL Server')
    p.add_argument('--user');p.add_argument('--password-env',default='QV_LOAD_SQL_PASSWORD')
    p.add_argument('--experiment',required=True)
    p.add_argument('--epoch',type=lambda v:str(uuid.UUID(v)),required=True,help='Reuse for the same Query Store lifetime; change after reset/restore')
    p.add_argument('--scenario',choices=sorted(SCENARIOS),default='predicate')
    p.add_argument('--variant',choices=['baseline','regressed'],default='baseline')
    p.add_argument('--duration-seconds',type=int,default=180)
    p.add_argument('--workers',type=int,default=2)
    p.add_argument('--query-timeout',type=int,default=10)
    p.add_argument('--pause-ms',type=int,default=20)
    p.add_argument('--max-requests-per-worker',type=int,default=10000)
    p.add_argument('--seed',type=int,default=1729)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();validate(args)
    if args.output.exists():p.error('Output already exists; choose a new receipt path')
    import pyodbc
    try:receipt=run(args,pyodbc.connect)
    except Exception as exc:
        # Do not echo driver errors containing connection strings or credentials.
        raise SystemExit('Lab preflight failed ('+type(exc).__name__+'). Check TLS, credentials and lab setup.') from None
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x') as out:json.dump(receipt,out,indent=2);out.write('\n')
    print(args.output)
    if receipt['metrics']['errors']:raise SystemExit(1)


if __name__=='__main__':main()

#!/usr/bin/env python3
"""Run pin/maintenance races in an explicitly named disposable SQL container."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--database', choices=['QueryVaultDB', 'QueryVaultRowstoreLab'], default='QueryVaultDB')
    args = parser.parse_args()
    if not re.fullmatch(r'queryvault-compat-test(?:-[a-z0-9]+)?', args.container):
        raise ValueError('Only disposable queryvault-compat-test containers are accepted')
    env = dict(os.environ, SQLCMDPASSWORD=os.environ['QV_TEST_SQL_PASSWORD'])
    command = ['docker', 'exec', '-i', '-e', 'SQLCMDPASSWORD', args.container,
               '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-U', 'sa',
               '-C', '-I', '-b', '-r1', '-l', '10', '-d', args.database]
    template = (ROOT / 'QueryVault/Tests/TestPartitionPinConcurrency.sql').read_text()
    log = ROOT / 'artifacts/pin-concurrency.log'
    log.parent.mkdir(exist_ok=True)

    def sql(phase, operation):
        return template.replace('$(Phase)', phase).replace('$(Operation)', operation)

    def run(phase, operation):
        result = subprocess.run(command, input=sql(phase, operation), text=True,
                                env=env, capture_output=True, timeout=45)
        with log.open('a') as stream:
            stream.write(f'\n{operation} {phase}\n{result.stdout}{result.stderr}')
        if result.returncode:
            raise RuntimeError(f'{operation} {phase}: {result.stdout}{result.stderr}')

    for operation in ['SwitchOut', 'Truncate', 'MergeBoundary']:
        run('SETUP', operation)
        holder = None
        reader = None
        lines = []
        try:
            holder = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, text=True, env=env)
            holder.stdin.write(sql('HOLDER', operation))
            holder.stdin.close()

            def read_holder():
                for line in holder.stdout:
                    lines.append(line)

            reader = threading.Thread(target=read_holder)
            reader.start()
            # Docker/sqlcmd can buffer pipe output. Observe the actual lock rather
            # than relying on a console message or an arbitrary startup delay.
            deadline = time.monotonic() + 15
            while True:
                probe = subprocess.run(command + ['-h', '-1'], input="""
SET NOCOUNT ON;
SELECT COUNT(*) FROM sys.dm_tran_locks l
JOIN sys.dm_exec_sessions s ON s.session_id=l.request_session_id
WHERE s.context_info=0x5156484F4C444552 AND l.resource_type='APPLICATION'
AND l.resource_database_id=DB_ID() AND l.request_status='GRANT';
""", text=True, env=env, capture_output=True, timeout=10)
                if probe.returncode == 0 and probe.stdout.strip() == '1':
                    break
                if holder.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Holder did not acquire lifecycle lock: ' + ''.join(lines))
                time.sleep(0.1)
            run('WORKER', operation)
            holder.wait(timeout=30)
            reader.join(timeout=5)
            if holder.returncode:
                raise RuntimeError('Holder failed: ' + ''.join(lines))
            run('VERIFY', operation)
            print(operation + ' concurrent pin: PASS', flush=True)
        finally:
            if holder is not None and holder.poll() is None:
                holder.kill()
                holder.wait()
            if reader is not None:
                reader.join(timeout=5)
            if holder is not None:
                with log.open('a') as stream:
                    stream.write(f'\n{operation} HOLDER exit={holder.returncode}\n' + ''.join(lines))
            run('CLEANUP', operation)
    run('OWNERSHIP', 'SwitchOut')
    print('Purge caller transaction ownership: PASS', flush=True)


if __name__ == '__main__':
    main()

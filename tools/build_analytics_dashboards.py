#!/usr/bin/env python3
"""Generate the additional QueryVault analytics dashboards. No server connections."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DS = {'type': 'mssql', 'uid': 'queryvault-mssql'}
B = "TRY_CONVERT(int,${baseline:sqlstring})"
C = "TRY_CONVERT(int,${candidate:sqlstring})"
RUN = "TRY_CONVERT(int,${run:sqlstring})"
PAIR = f'qv_report.fn_CompareRuns({B},{C})'
QUALITY = f'qv_report.fn_CompareRunQuality({B},{C})'
SCOPE = 'source_server_name=${server:sqlstring} AND source_database_name=${database:sqlstring}'
DATE = 'period_start_utc <= $__timeTo() AND period_end_utc >= $__timeFrom()'


def variable(name, label, query):
    return dict(name=name,label=label,type='query',datasource=DS,query=query,definition=query,refresh=2,
                multi=False,includeAll=False,options=[],current={},sort=0,hide=0)


def custom(name, label, values):
    return dict(name=name,label=label,type='custom',query=values,options=[],current={'text':values.split(',')[0],'value':values.split(',')[0]},multi=False,includeAll=False)


def sources():
    return [variable('server','Source server','SELECT DISTINCT source_server_name FROM qv_report.periods ORDER BY 1;'),
            variable('database','Database','SELECT DISTINCT source_database_name FROM qv_report.periods WHERE source_server_name=${server:sqlstring} ORDER BY 1;')]


def run_query(extra='1=1'):
    return f"SELECT CONCAT('#',period_id,' | ',CONVERT(varchar(19),period_start_utc,120),' UTC | ',period_name, ' | ',COALESCE(variant,'')) AS __text, period_id AS __value FROM qv_report.run_quality WHERE {SCOPE} AND {DATE} AND period_status=N'Completed' AND {extra} ORDER BY period_start_utc DESC,period_id DESC;"


def panel(title, sql, x, y, w=12, h=9, kind='table', unit='none'):
    p=dict(title=title,type=kind,datasource=DS,gridPos=dict(x=x,y=y,w=w,h=h),
           fieldConfig={'defaults':{'unit':unit,'decimals':2,'color':{'mode':'palette-classic'}},'overrides':[]},
           targets=[dict(refId='A',datasource=DS,editorMode='code',rawQuery=True,rawSql=sql,format='time_series' if kind=='timeseries' else 'table')],
           options={'showHeader':True,'cellHeight':'sm','footer':{'show':False}})
    if kind=='stat':
        p['options']={'reduceOptions':{'calcs':['lastNotNull'],'fields':'','values':False},'colorMode':'value','graphMode':'none','textMode':'auto','justifyMode':'auto','orientation':'auto'}
    elif kind=='timeseries':
        p['options']={'legend':{'displayMode':'list','placement':'bottom'},'tooltip':{'mode':'multi','sort':'desc'}}
        p['fieldConfig']['defaults']['custom']={'drawStyle':'line','lineWidth':2,'fillOpacity':8,'showPoints':'auto','spanNulls':False}
    return p


def text_panel(title, content, y, h=4):
    return dict(title=title,type='text',gridPos=dict(x=0,y=y,w=24,h=h),options={'mode':'markdown','content':content})


def dashboard(uid, title, variables, panels):
    for n,p in enumerate(panels,1): p['id']=n
    return dict(uid=uid,title=title,description='Archived Query Store analytics. Uses the stable qv_report contract. No live-source queries or tuning actions.',
                tags=['QueryVault','Query Store','Analytics'],schemaVersion=39,version=1,editable=True,timezone='utc',refresh='',
                time={'from':'now-90d','to':'now'},timepicker={},annotations={'list':[]},templating={'list':variables},panels=panels,
                links=[{'title':'QueryVault dashboards','type':'dashboards','tags':['QueryVault'],'asDropdown':True,'includeVars':False,'keepTime':True}])


def comparison(load=False):
    variables=sources()
    if load:
        variables.append(variable('experiment','Experiment',f'SELECT DISTINCT experiment_name FROM qv_report.run_quality WHERE {SCOPE} AND period_classification=N\'Load test\' AND experiment_name IS NOT NULL ORDER BY 1;'))
    extra="period_classification=N'Load test' AND experiment_name=${experiment:sqlstring}" if load else '1=1'
    variables += [variable('candidate','After / candidate run',run_query(extra)),
                  variable('baseline','Before / baseline run',run_query(extra+f' AND period_id<>{C} AND captured_end_utc<=(SELECT captured_start_utc FROM qv_report.run_quality WHERE period_id={C})')),
                  custom('min_executions','Minimum executions each run','10,1,50,100,1000'),
                  custom('regression_pct','Regression threshold %','20,10,30,50,100')]
    eligible="match_state=N'MATCHED' AND baseline_executions>=TRY_CONVERT(int,${min_executions:sqlstring}) AND candidate_executions>=TRY_CONVERT(int,${min_executions:sqlstring})"
    panels=[text_panel('Read this comparison', 'Choose the date range, source and two run IDs. **After minus before** is used for deltas. Rates use captured Query Store interval time. Average latency identifies slower executions; totals also reflect frequency. Identity continuity is operator-confirmed only when both runs share a recorded epoch. New or absent queries are not scored as regressions. Plan inventory changes are investigation leads, not proof of cause. No percentiles are inferred from aggregate Query Store data.',0,4),
            panel('Comparison readiness',f'SELECT comparison_state,identity_confidence,unequal_windows,same_experiment,time_direction,baseline_wait_state,candidate_wait_state FROM {QUALITY};',0,4,24,4),
            panel('Queries above latency threshold',f'SELECT COUNT_BIG(*) AS regressed_queries FROM {PAIR} WHERE {eligible} AND avg_duration_delta_pct>=TRY_CONVERT(float,${{regression_pct:sqlstring}});',0,8,6,4,'stat'),
            panel('Queries improved',f'SELECT COUNT_BIG(*) AS improved_queries FROM {PAIR} WHERE {eligible} AND avg_duration_delta_pct<=-TRY_CONVERT(float,${{regression_pct:sqlstring}});',6,8,6,4,'stat'),
            panel('Plan inventories changed',f'SELECT COUNT_BIG(*) AS changed_queries FROM {PAIR} WHERE plan_inventory_changed=1;',12,8,6,4,'stat'),
            panel('Identity / membership changes',f"SELECT COUNT_BIG(*) AS changed_queries FROM {PAIR} WHERE match_state<>N'MATCHED';",18,8,6,4,'stat'),
            panel('Run context and data quality',f'SELECT period_id,period_name,period_classification,experiment_name,workload_name,variant,deployment_label,period_start_utc,period_end_utc,captured_seconds,requested_seconds,interval_count,observation_state,is_comparison_ready,invalid_intervals,outside_window_intervals,overlapping_intervals,orphan_runtime_rows,missing_metadata_rows,orphan_wait_rows FROM qv_report.run_quality WHERE period_id IN ({B},{C});',0,12,24,6),
            panel('Top latency regressions by estimated extra duration',f'SELECT TOP (40) query_id,baseline_executions,candidate_executions,baseline_avg_duration_ms,candidate_avg_duration_ms,avg_duration_delta_pct,estimated_extra_duration_ms,avg_cpu_delta_pct,avg_reads_delta_pct,plan_inventory_changed,query_text_preview FROM {PAIR} WHERE {eligible} AND avg_duration_delta_pct>=TRY_CONVERT(float,${{regression_pct:sqlstring}}) ORDER BY estimated_extra_duration_ms DESC,query_id;',0,18,24,10),
            panel('Improvements',f'SELECT TOP (30) query_id,baseline_avg_duration_ms,candidate_avg_duration_ms,avg_duration_delta_pct,estimated_extra_duration_ms,query_text_preview FROM {PAIR} WHERE {eligible} AND avg_duration_delta_pct<=-TRY_CONVERT(float,${{regression_pct:sqlstring}}) ORDER BY estimated_extra_duration_ms,query_id;',0,28,12,9),
            panel('Frequency versus cost',f'SELECT TOP (30) query_id,baseline_executions_per_second,candidate_executions_per_second,baseline_cpu_ms_per_hour,candidate_cpu_ms_per_hour,baseline_total_duration_ms,candidate_total_duration_ms,avg_duration_delta_pct FROM {PAIR} WHERE match_state=N\'MATCHED\' ORDER BY candidate_cpu_ms_per_hour DESC,query_id;',12,28,12,9),
            panel('Wait intensity by category',f'SELECT wait_category_desc,observation_state,baseline_wait_ms,candidate_wait_ms,baseline_wait_ms_per_hour,candidate_wait_ms_per_hour,baseline_wait_ms_per_execution,candidate_wait_ms_per_execution FROM qv_report.fn_CompareWaits({B},{C}) ORDER BY candidate_wait_ms DESC;',0,37,12,9),
            panel('New, absent or changed identity',f"SELECT TOP (50) query_id,match_state,baseline_executions,candidate_executions,query_text_preview FROM {PAIR} WHERE match_state<>N'MATCHED' ORDER BY COALESCE(candidate_total_cpu_ms,baseline_total_cpu_ms) DESC,query_id;",12,37,12,9)]
    panels += [panel('CPU regressions per execution', f"SELECT TOP (40) query_id,baseline_avg_cpu_ms,candidate_avg_cpu_ms,avg_cpu_delta_pct,baseline_executions,candidate_executions,query_text_preview FROM {PAIR} WHERE {eligible} AND avg_cpu_delta_pct>=TRY_CONVERT(float,${{regression_pct:sqlstring}}) ORDER BY (candidate_avg_cpu_ms-baseline_avg_cpu_ms)*candidate_executions DESC,query_id;",0,46,12,9),
               panel('Logical read regressions per execution',f"SELECT TOP (40) query_id,baseline_avg_reads,candidate_avg_reads,avg_reads_delta_pct,baseline_executions,candidate_executions,query_text_preview FROM {PAIR} WHERE {eligible} AND avg_reads_delta_pct>=TRY_CONVERT(float,${{regression_pct:sqlstring}}) ORDER BY (candidate_avg_reads-baseline_avg_reads)*candidate_executions DESC,query_id;",12,46,12,9),
               panel('Query wait regressions',f"SELECT TOP (50) * FROM qv_report.fn_CompareQueryWaits({B},{C}) ORDER BY wait_per_execution_delta_ms DESC,query_id,wait_category;",0,55,24,9)]
    if load:
        panels.append(panel('Experiment history - separate archive observations, never summed',f"SELECT q.period_id,q.period_start_utc,q.variant,q.deployment_label,q.captured_seconds,m.execution_count,m.execution_count/NULLIF(q.captured_seconds,0) AS executions_per_second,m.total_duration_ms/NULLIF(m.execution_count,0) AS avg_duration_ms,m.total_cpu_ms/NULLIF(m.execution_count,0) AS avg_cpu_ms,m.total_logical_reads,m.plan_count FROM qv_report.run_quality AS q INNER JOIN qv_report.period_metrics AS m ON m.period_id=q.period_id WHERE q.{SCOPE.replace(' AND source_database_name',' AND q.source_database_name')} AND q.period_classification=N'Load test' AND q.experiment_name=${{experiment:sqlstring}} ORDER BY q.period_start_utc,q.period_id;",0,64,24,9))
    for p in panels:
        if p.get('type')=='table' and p.get('targets'):
            p['fieldConfig']['overrides'].append({'matcher':{'id':'byName','options':'query_id'},'properties':[{'id':'links','value':[{'title':'Inspect candidate query timeline','url':'/d/qv-interval-investigation/queryvault-interval-investigation?var-server=${server:percentencode}&var-database=${database:percentencode}&var-run=${candidate:percentencode}&var-query=${__data.fields.query_id}&from=${__from}&to=${__to}','targetBlank':False}]}]})
    return dashboard('qv-load-test-lab' if load else 'qv-run-regressions', 'QueryVault Load Test Lab' if load else 'QueryVault Run Regressions',variables,panels)


def timeline():
    variables=sources()+[variable('run','Archived run',run_query()),variable('query','Query',f"SELECT N'All queries' AS __text, CONVERT(bigint,-1) AS __value UNION ALL SELECT CONCAT('#',query_id,' | ',LEFT(query_text_preview,100)),query_id FROM qv_report.query_period_metrics WHERE period_id={RUN};")]
    where=f'period_id={RUN} AND (TRY_CONVERT(bigint,${{query:sqlstring}})=-1 OR query_id=TRY_CONVERT(bigint,${{query:sqlstring}}))'
    panels=[text_panel('Inside one captured run','All timeline samples belong to one RunID. CPU is cumulative worker time, not server CPU utilization. Duration is elapsed query time and can overlap across concurrent executions. Aborts and exceptions are separated below. Memory and tempdb values are per-execution averages; they are not peaks or spill counts. Empty panels mean no canonical observations.',0),
            panel('Run quality',f'SELECT * FROM qv_report.run_quality WHERE period_id={RUN};',0,4,24,5),
            panel('Executions per second',f'SELECT interval_start_utc AS time,SUM(execution_count)/NULLIF(MAX(interval_seconds),0) AS executions_per_second FROM qv_report.query_interval_metrics WHERE {where} GROUP BY interval_start_utc ORDER BY time;',0,9,12,8,'timeseries','ops'),
            panel('Execution-weighted latency',f'SELECT interval_start_utc AS time,SUM(total_duration_ms)/NULLIF(SUM(execution_count),0) AS avg_duration_ms,MAX(max_duration_ms) AS max_duration_ms FROM qv_report.query_interval_metrics WHERE {where} GROUP BY interval_start_utc ORDER BY time;',12,9,12,8,'timeseries','ms'),
            panel('CPU and logical I/O',f'SELECT interval_start_utc,SUM(execution_count) AS executions,SUM(total_cpu_ms) AS cpu_ms,SUM(total_cpu_ms)/NULLIF(SUM(execution_count),0) AS avg_cpu_ms,SUM(total_logical_reads) AS logical_reads_pages FROM qv_report.query_interval_metrics WHERE {where} GROUP BY interval_start_utc ORDER BY interval_start_utc;',0,17,12,9),
            panel('Execution outcomes',f'SELECT execution_type,execution_type_desc,SUM(execution_count) AS executions,SUM(total_duration_ms) AS duration_ms FROM qv_report.query_interval_metrics WHERE {where} GROUP BY execution_type,execution_type_desc ORDER BY execution_type;',12,17,12,9),
            panel('Memory, tempdb and log per execution',f'SELECT TOP (100) query_id,plan_id,SUM(execution_count) AS executions,SUM(avg_max_used_memory_kb*execution_count)/NULLIF(SUM(CASE WHEN avg_max_used_memory_kb IS NOT NULL THEN execution_count END),0) AS avg_max_used_memory_kb,SUM(avg_tempdb_space_kb*execution_count)/NULLIF(SUM(CASE WHEN avg_tempdb_space_kb IS NOT NULL THEN execution_count END),0) AS avg_tempdb_space_kb,SUM(avg_log_bytes_used*execution_count)/NULLIF(SUM(CASE WHEN avg_log_bytes_used IS NOT NULL THEN execution_count END),0) AS avg_log_bytes_used FROM qv_report.query_interval_metrics WHERE {where} GROUP BY query_id,plan_id ORDER BY avg_tempdb_space_kb DESC,query_id;',0,26,24,9),
            panel('Plan inventory',f'SELECT period_id,query_id,plan_id,query_plan_hash_hex,is_forced_plan,plan_type_desc FROM qv_report.query_plans WHERE period_id={RUN} AND (TRY_CONVERT(bigint,${{query:sqlstring}})=-1 OR query_id=TRY_CONVERT(bigint,${{query:sqlstring}})) ORDER BY query_id,plan_id;',0,35,24,9)]
    return dashboard('qv-interval-investigation','QueryVault Interval Investigation',variables,panels)


def main():
    for data in [comparison(),comparison(True),timeline()]:
        (ROOT/'grafana/dashboards'/('queryvault-'+data['uid'][3:]+'.json')).write_text(json.dumps(data,indent=2)+'\n')


if __name__=='__main__':main()

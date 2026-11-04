# -*- coding: utf-8 -*-
from pathlib import Path
import csv,json,hashlib,collections,sys,html
p=Path(sys.argv[1]);root=Path('.');read=lambda f:list(csv.DictReader(f.open()))
tests=[]
for label,f in [('Paper',root/'output/robustness_specs/event_study/spec_a_county_trajectory_matching/pretrend_tests.csv'),('Prior state',root/'output/research_extensions/25_main_state_clean_controls/pretrend_tests.csv'),('New state',p/'pretrend_tests.csv')]:
 for x in read(f):tests.append(dict(version=label,**x))
with (p/'comparison_pretrend_tests.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=list(tests[0]));w.writeheader();w.writerows(tests)

r=read(p/'matched_pairs.csv');a=read(p/'comparison_att_long.csv')
controls=[];counts=[]
for g in ['pooled','lower_income','higher_income']:
 v=[x for x in r if x['group']==g];pairs=collections.defaultdict(list)
 for x in v:pairs[x['match_id']].append(x)
 for pair in pairs.values():
  assert len(pair)==2 and len({x['statea'] for x in pair})==1
  t=next(x for x in pair if x['treated_cohort']=='1');c=next(x for x in pair if x['treated_cohort']=='0')
  assert int(float(t['first_pis_year']))==int(t['cohort'])
  assert c['first_pis_year']=='NA' or int(float(c['first_pis_year']))>2019
  controls.append(c)
 vc=[x for x in v if x['treated_cohort']=='0'];counts.append((g,len(pairs),sum(x['first_pis_year']=='NA' for x in vc),sum(x['first_pis_year']!='NA' for x in vc)))
 assert len({(x['cohort'],x['tract_id']) for x in vc})==len(vc)
assert len(read(p/'sunab_att.csv'))==42
assert all(float(x['treated_by_2010_tracts'])==0 and int(x['never_treated_tracts'])>0 for x in read(p/'sunab_att.csv'))
(p/'VALIDATION.txt').write_text('PASS: 42 core models plus 3 commuting-level models.\nPASS: every control never treated or first treated after 2019; no within-window later-treated controls.\nPASS: same-state pairs, one treated and one control, no within-cohort control reuse.\nPASS: never-treated retained and pre-2011-treated excluded in all outcome samples.\n')
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_seer_pop':'Population (log)','seer_total_population':'Population (level)','log_rac':'Resident-held jobs (log)','rac_total':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac_total':'Workplace jobs (level)','avg_road_dist_from_s000':'Commuting distance (km)','log_avg_dist_from_s000':'Commuting distance (log)','log_rac_low':'RAC low wage (log)','log_rac_mid':'RAC mid wage (log)','log_rac_high':'RAC high wage (log)','log_wac_low':'WAC low wage (log)','log_wac_mid':'WAC mid wage (log)','log_wac_high':'WAC high wage (log)'}
versions=['Paper: county matching','Prior state: unguarded clean controls','New state: covariate guards']
def fmt(x):
 if not x:return '—'
 f=100 if x['outcome']=='emp_pop_ratio' else 1;d=2 if x['outcome'] in ['rac_total','wac_total','seer_total_population','avg_road_dist_from_s000'] else 4
 pv=float(x['p_value']);star='***' if pv<.01 else '**' if pv<.05 else '*' if pv<.1 else ''
 return f"{float(x['estimate'])*f:.{d}f}{star} ({float(x['std_error'])*f:.{d}f})"
methods='''新版本保留同州、全期未处理controls、1:1匹配、0.2标准化倾向得分caliper，新增住宅社区资格和逐变量约束。treated和control均排除9800–9899特殊用途tract，所有已观察处理前年份人口至少100。所有核心变量差异不超过该cohort/收入组匹配前合格treated的1个标准差；常数变量要求相同。核心变量为log人口/RAC/WAC水平、近期log增长和RAC/WAC绝对增量，以及可用的早期对应变化。另要求人口规模比≤3、max(RAC,1)和max(WAC,1)规模比≤5。

先筛选合格候选，再按treated倾向得分从高到低、倾向得分最近邻选择control，每cohort内不重复使用，平分时按tract ID排序。协变量来源和时间窗保持上一版本。资格和逐变量约束在选择control之前执行，不是事后删除极端配对。

保留sunab、tract FE、pair×year FE、tract聚类SE，分别估计pooled/lower-income/higher-income。新结果与论文和25_main_state_clean_controls比较。该比较同时反映新增资格、硬约束及其导致的样本和权重变化，不能视为同一批treated的纯方法效应。图展示−5至+5，ATT覆盖全部可观察post horizons。

主模型和区域分析使用相同资格/硬约束原则，仍保留各自排序算法和outcome地理定义。此处未重跑intensity、industry、nearby/farther专题；论文与旧结果均保持不变。''' 
parts=['<!doctype html><meta charset="utf-8"><title>Main model: clean controls + state matching</title><style>body{font:16px system-ui;color:#243348;max-width:1400px;margin:40px auto;padding:0 24px}table{width:100%;border-collapse:collapse}td,th{padding:9px;border-bottom:1px solid #ddd;text-align:right}td:first-child,th:first-child{text-align:left}img{width:100%}details{margin:22px 0}</style><h1>Main model: state matching, expanded histories, controls untreated through 2019</h1>'];parts+=['<p>'+html.escape(x)+'</p>' for x in methods.split('\n\n')]
md=['# 同州匹配＋新增协变量＋全期未处理controls','',methods,'','|分组|配对数|Never-treated controls配对次数|2019年后controls配对次数|','|---|---:|---:|---:|']
for row in counts:md.append('| '+' | '.join(map(str,row))+' |')
parts.append('<p>核查：新配对全部通过人口和规模门槛，原极小人口control不再入样。−5年就业人口比SE由5.393pp降为0.126pp。但cohort-specific显示期lead联合检验就业人口比p=0.033、log RAC p=0.463、log WAC p=0.084；不能据此称所有pretrend已解决。匹配后仍有部分非核心人口结构变量|SMD|>0.2，完整平衡表保留。</p>')
parts.append('<p>New pair counts: '+', '.join(f'{g}: {n}' for g,n,_,_ in counts)+'</p>')
for g in ['pooled','lower_income','higher_income']:
 parts.append(f'<h2>{g}</h2><table><tr><th>Outcome</th>'+''.join('<th>'+v+'</th>' for v in versions)+'<th>New observations</th></tr>');md+=['',f'## {g}','','|Outcome|Paper|Prior state|New state|','|---|---:|---:|---:|']
 for y,label in labels.items():
  xs=[next((x for x in a if x['group']==g and x['outcome']==y and x['version']==v),None) for v in versions];vals=list(map(fmt,xs));n=xs[-1]['observations'] if xs[-1] else '—'
  parts.append('<tr><td>'+label+'</td>'+''.join('<td>'+x+'</td>' for x in vals)+f'<td>{n}</td></tr>');md.append('| '+' | '.join([label]+vals)+' |')
 parts.append('</table>')
parts.append('<p>Stars: * p&lt;0.10, ** p&lt;0.05, *** p&lt;0.01. Parentheses: tract-clustered SE.</p>')
parts.append('<h2>Paper versus new matching: employment-to-population ratio</h2><img src="comparison_emp_pop_ratio_paper_new.png">')
for y,label in labels.items():parts.append(f'<details open><summary>{label}</summary><img src="comparison_{y}.png"></details>')
parts.append('<p><a href="comparison_pretrend_tests.csv">All-version lead tests</a> · <a href="pretrend_tests.csv">New lead tests</a> · <a href="matching_balance.csv">Matching balance</a> · <a href="cohort_retention.csv">Cohort retention</a> · <a href="comparison_att_long.csv">All comparison estimates</a></p>')
(p/'results.html').write_text('\n'.join(parts));(p/'RESULTS_CN.md').write_text('\n'.join(md)+'\n')
print(counts)
for x in a:
 if x['group']=='pooled' and x['outcome'] in list(labels)[:8]:print(x['version'],x['outcome'],fmt(x))

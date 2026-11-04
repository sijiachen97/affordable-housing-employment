# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys
p=Path(sys.argv[1])
read=lambda name:list(csv.DictReader((p/'estimates'/name).open()))
a=[x for x in read('att_long.csv') if x['covariance']=='spatial_50km'];pr=[x for x in read('pretrend_tests.csv') if x['covariance']=='spatial_50km'];ss=read('sample_summary.csv')
assert len(a)==63 and len(pr)==63
notes='''本页仅展示Stage O（eligibility + guards），不叠加其他版本。采用同州匹配，controls中心为never-treated或2019年后首次处理，并满足区域内2010–2019年无新增项目及原有未知年份与地理筛选规则。先完成匹配，再保留treated周边无新增项目的配对，不重新匹配。
匹配资格：中心排除9800–9899特殊用途tract；处理前中心人口和周边总人口均至少100。中心和周边特征同时进入匹配；每项核心变量差异不超过1个合格treated标准差，人口规模比不超过3，RAC及WAC规模比各不超过5（岗位数以max(count,1)计算）。保留0.2倾向得分caliper、配对中心距离大于2r及区域成员不重叠要求。
Center为中心tract；Surroundings为其他质心落在中心质心3、5或7 km内的tracts；Cumulative为中心加周边。Level使用总和，log对总和取对数，employment-to-population ratio使用岗位总和除以人口总和。不同半径对应不同匹配样本。
估计采用Sun–Abraham、center FE及pair × year FE；本页统一使用50 km空间HAC标准误。处理前联合检验仅针对−5至−2年的聚合系数。图中各面板独立设置纵轴，便于观察中心的变化。'''
labels={'rac':'Resident-held jobs (level)','log_rac':'Resident-held jobs (log)','wac':'Workplace jobs (level)','log_wac':'Workplace jobs (log)','population':'Population (level)','log_population':'Population (log)','emp_pop_ratio':'Employment-to-population ratio (pp)'}
s=['<!doctype html><html><head><meta charset="utf-8"><title>Stage O: standalone results</title><style>body{font:16px system-ui;color:#243348;max-width:1400px;margin:40px auto;padding:0 24px;line-height:1.5}table{border-collapse:collapse;width:100%}td,th{padding:9px;border-bottom:1px solid #ddd;text-align:right}td:first-child,th:first-child{text-align:left}img{width:100%}details{margin:20px 0}</style></head><body><h1>Stage O: eligibility + guards</h1><p>No additional LIHTC projects in surrounding tracts</p>']
s+=['<p>'+x+'</p>' for x in notes.split('\n')]
s+=['<p>Matched pairs: '+', '.join(x['radius_km']+' km: '+x['retained'] for x in ss)+'.</p>']
md=['# Stage O：单独展示','',notes]
for y,title in labels.items():
 s.append('<h2>'+title+'</h2><table><tr><th>Radius</th><th>Component</th><th>ATT (SE)</th><th>Pre-treatment joint p</th><th>Observations</th></tr>')
 md+=['','## '+title,'','|Radius|Component|ATT (SE)|Pre-treatment p|Observations|','|---|---|---:|---:|---:|']
 for r in ['3','5','7']:
  for c in ['center','surroundings','cumulative']:
   x=next(x for x in a if (x['outcome'],x['radius_km'],x['component'])==(y,r,c));q=next(x for x in pr if (x['outcome'],x['radius_km'],x['component'])==(y,r,c))
   f=100 if y=='emp_pop_ratio' else 1;digits=1 if y in ['rac','wac','population'] else 4;pv=float(x['p_value']);star='***' if pv<.01 else '**' if pv<.05 else '*' if pv<.1 else ''
   vals=[r+' km',c,f"{float(x['estimate'])*f:.{digits}f}{star} ({float(x['std_error'])*f:.{digits}f})",f"{float(q['p_value']):.4f}",x['observations']]
   s.append('<tr>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>');md.append('| '+' | '.join(vals)+' |')
 s.append('</table><img alt="'+title+' event study" src="eventstudy_'+y+'.png">')
s.append('<p>* p&lt;0.10; ** p&lt;0.05; *** p&lt;0.01. Parentheses: spatial HAC standard errors. Pre-treatment tests are reported separately from post-treatment significance.</p></body></html>')
(p/'results.html').write_text('\n'.join(s));(p/'RESULTS_CN.md').write_text('\n'.join(md)+'\n')

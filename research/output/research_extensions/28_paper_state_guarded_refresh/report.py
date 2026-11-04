# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys,html,json,hashlib
p=Path(sys.argv[1]);read=lambda f:list(csv.DictReader((p/f).open()));a=read('all_att.csv');q=read('all_pretrend_tests.csv');mf=read('figure_manifest.csv')
assert len(a)==len(q) and len(a)>500
sp=['matched_pair_year','full_county_year','matched_year']
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','seer_total_population':'Population (level)','log_seer_pop':'Population (log)','rac_total':'Resident-held jobs (level)','log_rac':'Resident-held jobs (log)','wac_total':'Workplace jobs (level)','log_wac':'Workplace jobs (log)','avg_road_dist_from_s000':'All workers: commuting distance (km)','avg_road_dist_from_sa01':'Age ≤29: commuting distance (km)','avg_road_dist_from_sa02':'Age 30–54: commuting distance (km)','avg_road_dist_from_sa03':'Age ≥55: commuting distance (km)','avg_road_dist_from_se01':'Low wage: commuting distance (km)','avg_road_dist_from_se02':'Mid wage: commuting distance (km)','avg_road_dist_from_se03':'High wage: commuting distance (km)','avg_road_dist_from_si01':'Goods producing: commuting distance (km)','avg_road_dist_from_si02':'Trade, transportation, utilities: distance (km)','avg_road_dist_from_si03':'Other services: commuting distance (km)'}
for side in ['rac','wac']:
 for tier in ['low','mid','high']:labels[f'log_{side}_{tier}']=f'{side.upper()} {tier}-wage jobs (log)'
defs=list(csv.DictReader(Path('./output/research_extensions/22_industry_rac_wac_20261022/industry_definitions.csv').open()))
for z in defs:
 labels[z['sector']]=z['industry']+' (level)'
 labels['log_'+z['sector']]=z['industry']+' (log)'
def lab(y):return labels.get(y,y.replace('_',' '))
def fmt(x):
 y=x['outcome'];factor=100 if any(k in y for k in ['per_pop','emp_pop_ratio','near_share']) else 1;v=float(x['p_value']);star='***' if v<.01 else '**' if v<.05 else '*' if v<.1 else '';d=2 if not y.startswith('log_') else 4
 return f"{float(x['estimate'])*factor:.{d}f}{star} ({float(x['std_error'])*factor:.{d}f})"
parts=['''<!doctype html><html><head><meta charset="utf-8"><title>Paper results: state matching with eligibility and guards</title><style>body{font:16px system-ui;color:#243348;max-width:1350px;margin:36px auto;padding:0 24px;line-height:1.55}table{width:100%;border-collapse:collapse;font-size:14px}td,th{padding:8px;border-bottom:1px solid #ddd;text-align:right}td:first-child,th:first-child{text-align:left}img{width:100%;margin:15px 0}details{margin:18px 0}summary{cursor:pointer;font-weight:600}nav{padding:16px;background:#edf3f8}a{color:#215c8c}small{color:#626e7b}h2{margin-top:48px}pre{white-space:pre-wrap}</style></head><body><h1>Paper results: same-state matching with eligibility + guards</h1><p>完整重估预览。区域分析保留Stage O；论文文件尚未修改。本页的图只展示新主模型，不与历史版本叠加。</p><p><a href="RESULTS_CN.md">主要发现及原论文需要重新审阅的论述</a></p>''']
parts.append('''<details><summary>Methods and scope</summary><p>匹配：同州、1:1、cohort内不放回；controls只含never-treated或首次placement&gt;2019。排除未知首期、2010及更早处理、9800–9899特殊用途中心；处理前人口至少100。核心变量差异≤1个合格treated标准差；人口规模比≤3，RAC/WAC比各≤5。保留0.2倾向得分caliper。扩展近期和早期人口、RAC/WAC趋势；2011仅用水平。</p><p>总体与收入配对复用已验证的26版并重新估计；低/高intensity独立重新匹配。Intensity按原全体eligible treated中位数分组，不随新匹配样本重新划分。Primary与all jobs使用相同配对及比较内相同观测。Near/far所有半径和指标使用相同观测。</p><p>表中(1)：新匹配样本，tract + pair × year FE；(2)：原full eligible sample，tract + county × year FE；(3)：与(1)相同观测，tract + year FE。同州跨县配对的pair-year FE不再自动吸收county-year FE。三个模型均使用Sun–Abraham，标准误按原tract聚类，保留never-treated。区域分析的空间HAC不用于这些主模型结果。</p><p>Figures: pointwise 95% CI. Tables: ATT (SE); * p&lt;.10, ** p&lt;.05, *** p&lt;.01. Ratio/share effects are in percentage points. Displayed-lead tests here jointly test cohort-specific coefficients for −5…−2; they differ from the aggregated-lead tests in regional reports.</p><p><a href="SCOPE.md">Full scope and definitions</a> · <a href="all_att.csv">All estimates</a> · <a href="all_pretrend_tests.csv">Lead tests</a> · <a href="matching_constraint_validation.csv">Matching checks</a> · <a href="replication_of_guarded_main.csv">Main-model replication check</a></p></details>''')
parts.append('<p><strong>Matched pairs:</strong> pooled 2,048; lower income 1,175; higher income 750; low intensity 998; high intensity 999. Main observations vary by outcome availability.</p>')
sections=[('main','Main outcomes and wage tiers'),('intensity','Construction intensity'),('industry','Industry employment'),('commute','Commuting distance'),('near_far','Employment by workplace distance and radius sensitivity'),('primary','Primary-job robustness'),('primary_intensity','Primary jobs by construction intensity')]
parts.append('<nav>'+ ' · '.join(f'<a href="#{s}">{title}</a>' for s,title in sections)+' · <a href="#descriptive">Descriptives, housing scale and balance</a></nav>')
def image(src):
 assert (p/src).exists(),src
 return '<img loading="lazy" src="'+src+'">'
def main_table(groups,title):
 cols=[(ss,gg) for ss in sp for gg in groups]
 out=['<h3>'+title+'</h3><table><tr><th>Outcome</th>'+''.join('<th>('+str(sp.index(ss)+1)+') '+gg.replace('_',' ')+'</th>' for ss,gg in cols)+'</tr>']
 export=[]
 for y in ['emp_pop_ratio','log_seer_pop','seer_total_population','log_rac','rac_total','log_wac','wac_total']:
  xs=[next(x for x in a if x['analysis'].startswith('main/') and (x['specification'],x['group'],x['outcome'])==(ss,gg,y)) for ss,gg in cols]
  vals=[fmt(x)+'<br><small>N='+str(x['observations'])+'</small>' for x in xs]
  out.append('<tr><td>'+lab(y)+'</td>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>')
  export.append([lab(y)]+[fmt(x) for x in xs])
 h=read('descriptives/housing_scale_by_estimation_sample.csv')
 for key,label in [('treated_tracts','Treated tracts'),('mean_first_year_total','Mean first-placement total units')]:
  vals=[]
  for ss,gg in cols:
   x=next(x for x in h if (x['specification'],x['group'],x['outcome'])==(ss,gg,'rac_total'))
   vals.append(x[key] if key=='treated_tracts' else f"{float(x[key]):.2f}")
  out.append('<tr><td>'+label+'</td>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>');export.append([label]+vals)
 for label,values in [('Tract FE',['Yes','Yes','Yes']),('Year FE',['Absorbed','Absorbed','Yes']),('County × year FE',['No','Yes','No']),('Pair × year FE',['Yes','No','No']),('Matched sample',['Yes','No','Yes'])]:
  vals=[values[sp.index(ss)] for ss,gg in cols];out.append('<tr><td>'+label+'</td>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>');export.append([label]+vals)
 out.append('</table><p><small>Housing statistics refer to actual treated tracts in the corresponding RAC estimation sample. Ratio effects are in percentage points. The two matched specifications use identical observations.</small></p>')
 dest=p/'tables';dest.mkdir(exist_ok=True)
 with (dest/('paper_pooled_main.csv' if groups==['pooled'] else 'paper_income_main.csv')).open('w') as f:
  w=csv.writer(f);w.writerow(['Outcome']+[ss+' / '+gg for ss,gg in cols]);w.writerows(export)
 return ''.join(out)
for sec,title in sections:
 parts.append(f'<h2 id="{sec}">{title}</h2>')
 if sec in ['primary','primary_intensity']:
  for kind in ['emp_pop_ratio','rac_total']:parts.append(image('figures/'+sec+'_comparison_'+kind+'.png'))
 if sec=='industry':parts.append(image('figures/industry_log.png'));parts.append('<details><summary>Industry effects in levels</summary>'+image('figures/industry_level.png')+'</details>')
 if sec=='near_far':parts.append(image('figures/near_far_10km.png'));parts.append(image('figures/radius_sensitivity.png'))
 if sec=='main':
  parts.append(main_table(['pooled'],'Pooled main outcomes'))
  parts.append(main_table(['lower_income','higher_income'],'Main outcomes by neighborhood income'))
  for side in ['rac','wac']:parts.append('<details><summary>'+side.upper()+' wage tiers, pooled and by income</summary>'+image('figures/'+side+'_wage_combined.png')+'</details>')
 analyses=list(dict.fromkeys(x['analysis'] for x in a if x['analysis'].split('/')[0]==sec))
 for an in analyses:
  rows=[x for x in a if x['analysis']==an];parts.append('<h3>'+html.escape(an.split('/')[-1].replace('_',' '))+'</h3><table><tr><th>Group / outcome</th><th>(1) Pair-year FE</th><th>(2) Full: county-year FE</th><th>(3) Matched: year FE</th><th>Main lead p</th></tr>')
  keys=list(dict.fromkeys((x['group'],x['outcome']) for x in rows))
  for g,y in keys:
   xx=[next(x for x in rows if (x['group'],x['outcome'],x['specification'])==(g,y,s)) for s in sp]
   z=next(x for x in q if (x['analysis'],x['group'],x['outcome'],x['specification'])==(an,g,y,sp[0]))
   parts.append('<tr><td>'+html.escape(g.replace('_',' ')+' / '+lab(y))+'</td>'+''.join('<td>'+fmt(x)+'<br><small>N='+f"{int(x['observations']):,}"+'</small></td>' for x in xx)+f"<td>{float(z['p_value']):.4f}</td></tr>")
  parts.append('</table>')
  if sec not in ['industry','near_far']:
   for x in mf:
    if x['analysis']==an:parts.append('<details'+(' open' if sec in ['intensity'] or (sec=='main' and x['outcome']=='emp_pop_ratio') else '')+'><summary>'+html.escape(lab(x['outcome']))+' event study</summary>'+image(x['file'])+'</details>')
  else:
   parts.append('<details><summary>Individual outcome event studies</summary>')
   for x in mf:
    if x['analysis']==an:parts.append('<details><summary>'+html.escape(lab(x['outcome']))+'</summary>'+image(x['file'])+'</details>')
   parts.append('</details>')
parts.append('<h2 id="descriptive">Descriptives, housing scale and matching balance</h2>')
parts.append(image('figures/matching_balance.png'))
parts.append('<p>Balance plot averages absolute within-cohort SMDs using matched treated counts as weights; SMD denominators are eligible-treated SDs before matching. The CSV also reports the maximum cohort imbalance. These summaries do not imply every covariate is balanced in every cohort.</p>')
for f,title in [('descriptives/housing_scale_by_estimation_sample.csv','Housing scale in actual estimation samples'),('descriptives/baseline.csv','Baseline summary: union of eligible matching candidates'),('descriptives/cohorts.csv','Cohort distribution'),('descriptives/project_scale_summary.csv','First-placement and cumulative units')]:
 rows=read(f);parts.append('<h3>'+title+'</h3><p><a href="'+f+'">Download CSV</a></p><div style="overflow:auto"><table><tr>'+''.join('<th>'+k+'</th>' for k in rows[0])+'</tr>')
 for x in rows:
  vals=[]
  for v in x.values():
   try: v=f'{float(v):,.3f}' if '.' in v or 'e-' in v else v
   except ValueError:pass
   vals.append(html.escape(v))
  parts.append('<tr>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>')
 parts.append('</table></div>')
parts.append('<p>Project scale uses valid project unit counts, summed at first placement; missing counts are not imputed. Treated-tract means are unweighted descriptive means, not an ATT per housing unit.</p><p><a href="matching_balance.csv">Pooled/income balance before and after matching</a> · <a href="intensity_balance.csv">Intensity balance</a> · <a href="cohort_retention.csv">Pooled/income retention</a> · <a href="intensity_retention.csv">Intensity retention</a> · <a href="DESIGN_VALIDATION.txt">Design validation</a></p></body></html>')
(p/'results.html').write_text('\n'.join(parts))
# Reusable tables for a future paper update, without touching current LaTeX.
t=p/'tables';t.mkdir(exist_ok=True)
def main_table(groups,title):
 cols=[(ss,gg) for ss in sp for gg in groups]
 out=['<h3>'+title+'</h3><table><tr><th>Outcome</th>'+''.join('<th>('+str(sp.index(ss)+1)+') '+gg.replace('_',' ')+'</th>' for ss,gg in cols)+'</tr>']
 export=[]
 for y in ['emp_pop_ratio','log_seer_pop','seer_total_population','log_rac','rac_total','log_wac','wac_total']:
  xs=[next(x for x in a if x['analysis'].startswith('main/') and (x['specification'],x['group'],x['outcome'])==(ss,gg,y)) for ss,gg in cols]
  vals=[fmt(x)+'<br><small>N='+str(x['observations'])+'</small>' for x in xs]
  out.append('<tr><td>'+lab(y)+'</td>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>')
  export.append([lab(y)]+[fmt(x) for x in xs])
 h=read('descriptives/housing_scale_by_estimation_sample.csv')
 for key,label in [('treated_tracts','Treated tracts'),('mean_first_year_total','Mean first-placement total units')]:
  vals=[]
  for ss,gg in cols:
   x=next(x for x in h if (x['specification'],x['group'],x['outcome'])==(ss,gg,'rac_total'))
   vals.append(x[key] if key=='treated_tracts' else f"{float(x[key]):.2f}")
  out.append('<tr><td>'+label+'</td>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>');export.append([label]+vals)
 for label,values in [('Tract FE',['Yes','Yes','Yes']),('Year FE',['Absorbed','Absorbed','Yes']),('County × year FE',['No','Yes','No']),('Pair × year FE',['Yes','No','No']),('Matched sample',['Yes','No','Yes'])]:
  vals=[values[sp.index(ss)] for ss,gg in cols];out.append('<tr><td>'+label+'</td>'+''.join('<td>'+v+'</td>' for v in vals)+'</tr>');export.append([label]+vals)
 out.append('</table><p><small>Housing statistics refer to actual treated tracts in the corresponding RAC estimation sample. Ratio effects are in percentage points. The two matched specifications use identical observations.</small></p>')
 dest=p/'tables';dest.mkdir(exist_ok=True)
 with (dest/('paper_pooled_main.csv' if groups==['pooled'] else 'paper_income_main.csv')).open('w') as f:
  w=csv.writer(f);w.writerow(['Outcome']+[ss+' / '+gg for ss,gg in cols]);w.writerows(export)
 return ''.join(out)
for sec,title in sections:
 rows=[x for x in a if x['analysis'].split('/')[0]==sec]
 keys=list(dict.fromkeys((x['analysis'],x['group'],x['outcome']) for x in rows));out=[]
 for an,g,y in keys:
  out.append({'analysis':an,'group':g,'outcome':y,**{s:fmt(next(x for x in rows if (x['analysis'],x['group'],x['outcome'],x['specification'])==(an,g,y,s))) for s in sp}})
 with (t/(sec+'_did_wide.csv')).open('w') as f:w=csv.DictWriter(f,fieldnames=list(out[0]));w.writeheader();w.writerows(out)
print('Models:',len(a),'Figures:',len(mf),'Report ready.')

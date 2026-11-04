import csv,html,json
from pathlib import Path
SRC=Path('./output/research_extensions/28_paper_state_guarded_refresh')
OUT=SRC/'paper_preview'; OUT.mkdir(parents=True,exist_ok=True)
rows=list(csv.DictReader((SRC/'all_att.csv').open()))
housing=list(csv.DictReader((SRC/'descriptives/housing_scale_by_estimation_sample.csv').open()))
specs=['matched_pair_year','matched_year','full_county_year']
def get(a,g,s,o):
 r=[r for r in rows if (r['analysis'],r['group'],r['specification'],r['outcome'])==(a,g,s,o)]
 assert len(r)==1,(a,g,s,o,len(r))
 return r[0]
used=[]
def cell(r,level=False):
 used.append(r); p=float(r['p_value']); stars='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 f=2 if level else 4
 return f"{float(r['estimate']):.{f}f}{stars}<br><span class='se'>({float(r['std_error']):.{f}f})</span>"
def tr(label,vals,cls=''):
 return f'<tr class="{cls}"><td>{label}</td>'+''.join('<td>'+str(v)+'</td>' for v in vals)+'</tr>'
base='Sun and Abraham aggregate treatment effects average over observed post-treatment horizons. Standard errors clustered by tract are in parentheses. * p &lt; 0.10, ** p &lt; 0.05, *** p &lt; 0.01.'
match='Matched samples use one-to-one matching within state and treatment cohort, with pre-treatment demographic and employment covariates and growth measures, eligibility screens, and covariate and scale constraints. Controls are never treated or first receive LIHTC after 2019.'
data='Resident-held jobs are LODES Version 7 Residence Area Characteristics (RAC) all-job counts, assigned by residence; workplace jobs are Workplace Area Characteristics (WAC) all-job counts, assigned by workplace. Population is total tract population from SEER. The employment-to-population ratio is RAC jobs divided by SEER population.'
main='Estimates use the main specification with tract and matched-pair-by-year fixed effects. '+match
parts=[]
def table(id,title,heads,body,note):
 if id in ('wage','commute'):
  file='pooled_wage.png' if id=='wage' else 'commuting_subgroups.png'
  note=note.replace(base, 'Points report Sun and Abraham aggregate treatment effects over observed post-treatment horizons; bars indicate 95% confidence intervals based on tract-clustered standard errors.')
  if id=='wage':
   ns=[]
   for side in ['rac','wac']:
    vals=[int(get('main/log_'+side+'_low','pooled',specs[0],'log_'+side+'_'+t)['observations']) for t in ['low','mid','high']]
    ns.append(('Resident-held jobs' if side=='rac' else 'Workplace jobs')+': '+', '.join(f'{n:,}' for n in vals))
   note+=' Observations for low, middle, and high wage outcomes, respectively: '+ '; '.join(ns)+'.'
  else:
   note+=' Observations: 40,852 for each subgroup, except high-wage workers (40,846) and goods-producing workers (40,850). Negative estimates indicate shorter commuting distances.'
  parts.append(f'<section id="{id}"><h2>{title}</h2><img src="{file}" alt="{title}"><p class="note"><i>Notes:</i> {note}</p></section>')
  return
 parts.append(f'<section id="{id}"><h2>{title}</h2><div class="scroll"><table><thead>'+tr('',heads)+'</thead><tbody>'+body+'</tbody></table></div><p class="note"><i>Notes:</i> '+note+'</p></section>')
outs=[('Employment-to-population ratio','emp_pop_ratio','emp_pop_ratio'),('Population (log)','seer_total_population','log_seer_pop'),('Population (level)','seer_total_population','seer_total_population'),('Resident-held jobs (log)','rac_total','log_rac'),('Resident-held jobs (level)','rac_total','rac_total'),('Workplace jobs (log)','wac_total','log_wac'),('Workplace jobs (level)','wac_total','wac_total')]
for income in [False,True]:
 gs=['lower_income','higher_income'] if income else ['pooled']; cols=[(s,g) for s in specs for g in gs]
 heads=[f'({i+1})'+('<br>'+('Lower' if g=='lower_income' else 'Higher')+'<br>income' if income else '') for i,(s,g) in enumerate(cols)]
 body=''
 for label,a,o in outs: body+=tr(label,[cell(get('main/'+a,g,s,o),'(level)' in label) for s,g in cols])
 for j,(label,a,o) in enumerate([outs[i] for i in [0,1,3,5]]):
  body+=tr('Observations: '+label.replace(' (log)',''),[f"{int(get('main/'+a,g,s,o)['observations']):,}" for s,g in cols],'rule' if j==0 else '')
 hs=[]
 for s,g in cols:
  h=[h for h in housing if h['group']==g and h['specification']==s and h['outcome']=='rac_total'];assert len(h)==1;hs.append(h[0])
 body+=tr('Treated tracts',[f"{int(h['treated_tracts']):,}" for h in hs],'rule')
 body+=tr('Mean first-placement total units',[f"{float(h['mean_first_year_total']):.2f}" for h in hs])
 for j,(label,marks) in enumerate([('Tract FE',['✓','✓','✓']),('Year FE',['Absorbed','✓','Absorbed']),('County × year FE',['','','✓']),('Pair × year FE',['✓','','']),('PSM matched sample',['✓','✓',''])]):
  body+=tr(label,[m for m in marks for _ in gs],'rule' if j==0 else '')
 note=base+' '+match+' Columns '+('(1)–(2), (3)–(4), and (5)–(6)' if income else '(1), (2), and (3)')+' report the matched pair-by-year, matched year, and unmatched county-by-year specifications, respectively. '+data+' Housing statistics describe treated tracts in the estimation sample; mean units measure total new-construction units placed in service in each tract’s first placement year. Observations count regression rows, including tract-years used in multiple matched pairs.'
 if income:note+=' Neighborhood income is defined using the median 2006–2010 ACS tract income ($51,548); matching is performed separately within each income group.'
 table('income' if income else 'pooled','Heterogeneity by Neighborhood Income: Aggregate Treatment Effects, Main Outcomes' if income else 'Aggregate Treatment Effects of LIHTC Development: Main Outcomes',heads,body,note)
body=''
for label,a,o in [outs[i] for i in [0,1,3,5]]:
 rs=[get('intensity/'+a,g,specs[0],o) for g in ['low_intensity','high_intensity']]
 body+=tr(label,[cell(r) for r in rs])+tr('Observations',[f"{int(r['observations']):,}" for r in rs],'nrow')
table('intensity','Aggregate Treatment Effects by Construction Intensity',['Lower intensity','Higher intensity'],body,base+' '+main+' The groups are matched separately and defined by the median first-placement new-construction units per 1,000 placement-year residents (13.34). '+data)
body=''
for tier,label in [('low','Low wage'),('mid','Middle wage'),('high','High wage')]:
 rs=[get('main/log_'+side+'_low','pooled',specs[0],'log_'+side+'_'+tier) for side in ['rac','wac']]
 body+=tr(label,[cell(r) for r in rs])+tr('Observations',[f"{int(r['observations']):,}" for r in rs],'nrow')
wage='Monthly earnings tiers are $1,250 or less, $1,251–$3,333, and above $3,333. Outcomes are log job counts.'
table('wage','Aggregate Treatment Effects by Wage Tier',['Resident-held jobs (log)','Workplace jobs (log)'],body,base+' '+main+' '+wage+' '+data.split(' Population')[0])
body=''
for cat,items in [('All workers',[('s000','All workers')]),('Age',[('sa01','29 or younger'),('sa02','30–54'),('sa03','55 or older')]),('Monthly earnings',[('se01','Low wage'),('se02','Middle wage'),('se03','High wage')]),('Industry',[('si01','Goods producing'),('si02','Trade, transportation, and utilities'),('si03','Other services')])]:
 if cat!='All workers':body+=f'<tr class="group"><td colspan="3">{cat}</td></tr>'
 for k,l in items:
  o='avg_road_dist_from_'+k;r=get('commute/'+o,'pooled',specs[0],o)
  body+=tr(l,[cell(r),f"{int(r['observations']):,}"])
table('commute','Aggregate Treatment Effects on Commuting Distance by Worker Subgroup (km)',['Effect (km)','Observations'],body,base+' '+main+' Commuting distance is the job-weighted mean road-network distance, constructed from available within-state LODES origin–destination flows and OSRM routes on a 2021 OpenStreetMap extract. '+wage.split(' Outcomes')[0])
for id,title,file,note in [('industry','Industry Employment: Aggregate Effects on Log Job Counts','industry_log.png','Points report main-specification aggregate treatment effects, multiplied by 100; bars indicate 95% confidence intervals. All 20 LODES industry categories are shown. '+main),('income_wage','Heterogeneity by Neighborhood Income: Aggregate Treatment Effects by Wage Tier','income_wage.png','Points report main-specification aggregate treatment effects on log job counts; bars indicate 95% confidence intervals based on tract-clustered standard errors. '+wage+' Neighborhood groups use the median 2006–2010 ACS tract income ($51,548) and are matched separately. '+main)]:
 parts.append(f'<section id="{id}"><h2>{title}</h2><img src="{file}" alt="{title}"><p class="note"><i>Notes:</i> {note}</p></section>')
exec((Path(__file__).parent/'append_sections.py').read_text())
css='''body{font-family:"Times New Roman",serif;color:#111;background:#eee;margin:0}header{max-width:1180px;margin:28px auto;padding:20px}header p,nav{font-family:Arial,sans-serif;font-size:14px;line-height:1.6}nav a{margin-right:20px;color:#214f80}section{background:white;max-width:1180px;margin:28px auto;padding:42px;box-shadow:0 1px 5px #ccc;page-break-after:always}h1{font-size:26px}h2{font-size:24px;font-weight:normal;line-height:1.3;margin:0 0 20px}table{width:100%;border-collapse:collapse;font-size:19px;text-align:center;border-top:2px solid;border-bottom:2px solid}thead{border-bottom:1px solid}td{padding:8px 10px;vertical-align:top}td:first-child{text-align:left}thead td{text-align:center!important}.se{white-space:nowrap}.rule{border-top:1px solid}.nrow{font-size:15px;color:#444}.nrow td{padding-top:0;padding-bottom:14px}.group{border-top:1px solid;font-style:italic}.note{font-size:15px;line-height:1.4;margin-top:12px}img{width:100%;display:block}.scroll{overflow:auto}@media print{body{background:white}header{display:none}section{box-shadow:none;margin:0;padding:12px;max-width:none}table{font-size:12px}.note{font-size:10px}h2{font-size:17px}td{padding:5px}}'''
(OUT/'results.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>Paper tables and figures preview</title><style>'+css+'</style><header><h1>Paper tables and figures preview</h1><p>Updated guarded same-state estimates. Preview only; manuscript unchanged. Includes the requested main event studies, primary-job appendix, and retained Stage O spatial results.</p><nav>'+''.join(f'<a href="#{i}">{l}</a>' for i,l in [('pooled','Pooled'),('income','Income'),('intensity','Intensity'),('wage','Wage tiers'),('commute','Commuting'),('industry','Industry'),('income_wage','Income × wage'),('es_pooled_emp_pop_ratio','Event studies'),('a3','Primary-job appendix'),('spatial_table_3','Spatial estimates'),('spatial_log_rac','Spatial event studies')])+'</nav></header>'+''.join(parts)+'</html>')
with (OUT/'displayed_table_estimates.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(used)
print('Built 6 tables and 15 figure slots;',len(used),'verified source estimates')

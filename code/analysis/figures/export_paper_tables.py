from pathlib import Path
import csv,re,html,statistics,math
from html.parser import HTMLParser
ROOT=Path('.');SRC=ROOT/'output/research_extensions/28_paper_state_guarded_refresh';OUT=ROOT/'output/paper_assets';PRE=SRC/'paper_preview'
OUT.mkdir(parents=True, exist_ok=True)
def read(n):return list(csv.DictReader((SRC/n).open()))
def tex(s):
 s=html.unescape(s).replace('Retained Stage O specification: ', '').replace('No previous estimates are overlaid.', '')
 for a,b in [('\\',r'\textbackslash{}'),('&',r'\&'),('%',r'\%'),('$',r'\$'),('_',r'\_'),('#',r'\#'),('✓',r'$\checkmark$'),('×',r'$\times$'),('≤',r'$\leq$'),('≥',r'$\geq$'),('–','--'),('—',','),('’',"'"),('−','-')]:s=s.replace(a,b)
 return re.sub(r'p < (0\.\d+)', r'$p < \1$', s)
class Parser(HTMLParser):
 def __init__(self):super().__init__();self.sections={};self.sec=None;self.cell=None;self.row=None;self.cap=False;self.note=False
 def handle_starttag(self,t,a):
  d=dict(a)
  if t=='section':self.sec={'rows':[],'caption':'','note':'','image':None};self.sections[d['id']]=self.sec
  if self.sec is None:return
  if t=='h2':self.cap=True
  if t=='p' and d.get('class')=='note':self.note=True
  if t=='tr':self.row={'cells':[],'class':d.get('class','')}
  if t=='td':self.cell={'text':'','span':int(d.get('colspan',1))}
  if t=='br' and self.cell is not None:self.cell['text']+='|BR|'
  if t=='img':self.sec['image']=d['src']
 def handle_endtag(self,t):
  if t=='h2':self.cap=False
  if t=='p':self.note=False
  if t=='td':self.row['cells'].append(self.cell);self.cell=None
  if t=='tr':self.sec['rows'].append(self.row);self.row=None
  if t=='section':self.sec=None
 def handle_data(self,s):
  if self.sec is None:return
  if self.cell is not None:self.cell['text']+=s
  elif self.cap:self.sec['caption']+=s
  elif self.note:self.sec['note']+=s
p=Parser();p.feed((PRE/'results.html').read_text());sections=p.sections

def rows_tex(rows):
 out=[]
 for i,r in enumerate(rows):
  if r['class'] in ('rule','group'):out.append(r'\midrule')
  vals=[]
  for j,c in enumerate(r['cells']):
   lines=[tex(x.strip()) for x in c['text'].split('|BR|')]
   v=(r'\shortstack['+('l' if j==0 else 'c')+']{'+r'\\'.join(lines)+'}') if len(lines)>1 else lines[0]
   if c['span']>1:v=r'\multicolumn{'+str(c['span'])+'}{'+('l' if r['class']=='group' else 'c')+'}{'+v+'}'
   vals.append(v)
  out.append(' & '.join(vals)+r' \\[3pt]')
  if i==0:out.append(r'\midrule')
 return '\n'.join(out)
def table_from(id,label):
 s=sections[id];n=max(sum(c['span'] for c in r['cells']) for r in s['rows']);caption=re.sub(r'^Table A\d+: ','',s['caption']);note=tex(s['note'].removeprefix('Notes: '))
 if label=='tab:intensity':
  import copy
  kept=[];obs=[];previous=''
  for row in s['rows']:
   row=copy.deepcopy(row)
   if row['cells'][0]['text'].strip()=='Observations':
    row['cells'][0]['text']='Observations: '+previous.replace(' (log)','');obs.append(row)
   else:
    kept.append(row);previous=row['cells'][0]['text'].strip()
  if obs:obs[0]['class']='rule'
  s=dict(s,rows=kept+obs)
 body=rows_tex(s['rows']); spec='l'+'c'*(n-1)
 if id=='spatial_table_3':
  return '\\clearpage\n\\begingroup\\small\n\\begin{longtable}{'+spec+'}\n\\caption{'+tex(caption)+'}\\label{'+label+'}\\\\\n\\toprule\n'+rows_tex(s['rows'][:1])+r'\endfirsthead'+'\n'+r'\multicolumn{4}{l}{\tablename\ \thetable\ (continued)}\\\toprule'+'\n'+rows_tex(s['rows'][:1])+r'\endhead'+'\n'+r'\bottomrule\endfoot'+'\n'+rows_tex(s['rows'][1:])+'\n\\end{longtable}\n{\\footnotesize\\textit{Notes:} '+note+'}\n\\endgroup\n'
 return '\\clearpage\n\\begin{table}[!ht]\\centering\n\\caption{'+tex(caption)+'}\\label{'+label+'}\n\\small\\setlength{\\tabcolsep}{4pt}\n\\resizebox{\\textwidth}{!}{\\begin{tabular}{'+spec+'}\n\\toprule\n'+body+'\n\\bottomrule\n\\end{tabular}}\n\\medskip\n\\parbox{\\textwidth}{\\footnotesize\\textit{Notes:} '+note+'}\n\\end{table}\n'
def fig(id,label,aliases=[]):
 s=sections[id];img=s['image'];pdf=PRE/Path(img).with_suffix('.pdf');use=pdf.name if pdf.exists() else img
 return figure(tex(re.sub(r'^Figure A\d+: ','',s['caption'])),label,'generated_guarded/'+use,tex(s['note'].removeprefix('Notes: ')),aliases)
def figure(caption,label,path,note,aliases=[]):
 return '\\clearpage\n\\begin{figure}[!ht]\\centering\n\\caption{'+caption+'}\\label{'+label+'}'+''.join('\\label{'+x+'}' for x in aliases)+'\n\\medskip\n\\includegraphics[width=\\textwidth,height=0.72\\textheight,keepaspectratio]{'+path+'}\n\\medskip\n\\parbox{\\textwidth}{\\footnotesize\\textit{Notes:} '+note+'}\n\\end{figure}\n'
def customtable(caption,label,heads,rows,note):
 sections['_custom']={'caption':caption,'note':note,'rows':[{'cells':[{'text':x,'span':1} for x in heads],'class':''}]+[{'cells':[{'text':str(x),'span':1} for x in r],'class':''} for r in rows]};return table_from('_custom',label)
# Updated descriptive tables: union of cohort-specific matching-eligible candidates.
b=read('descriptives/baseline.csv');counts={r['is_control']:r['n'] for r in read('descriptives/baseline_tract_counts.csv')}
vars=[('Population','seer_total_population'),('Share non-Hispanic Black','seer_share_nh_black'),('Share Hispanic','seer_share_hispanic'),('Share age under 29','seer_age_share_under29'),('Share age 55+','seer_age_share_55plus'),('Median household income ($)','acs2010_median_hh_income'),('Resident-held jobs','rac_total'),('Low-wage resident-held jobs','rac_earn_le_1250'),('Mid-wage resident-held jobs','rac_earn_1251_3333'),('High-wage resident-held jobs','rac_earn_ge_3333'),('Workplace jobs','wac_total'),('Low-wage workplace jobs','wac_earn_le_1250'),('Mid-wage workplace jobs','wac_earn_1251_3333'),('High-wage workplace jobs','wac_earn_ge_3333'),('Employment-to-population ratio','emp_pop_ratio')]
rr=[]
for label,v in vars:
 row=[label]
 for g in ['FALSE','TRUE']:
  z=next(x for x in b if x['is_control']==g and x['variable']==v);digits=2 if 'share' in v or v=='emp_pop_ratio' else 0;row.extend([f"{float(z['mean']):,.{digits}f}",f"{float(z['sd']):,.{digits}f}",f"{int(z['n']):,}"])
 rr.append(row)
rr.append(['Tracts',f"{int(counts['FALSE']):,}",'','',f"{int(counts['TRUE']):,}",'',''])
assets=customtable('Summary Statistics: Treated and Control Tracts at Baseline (2010)','tab:summary_stats',['','Treated|BR|Mean','Treated|BR|SD','Treated|BR|N','Control|BR|Mean','Control|BR|SD','Control|BR|N'],rr,'The sample is the union of cohort-specific matching-eligible candidate pools before pair selection. Treated tracts first receive new construction in 2011–2019; controls are never treated or first treated after 2019. Special-use tracts and candidates failing pre-treatment population or covariate availability requirements are excluded. Baseline values are measured in 2010; missing values are omitted separately by variable. Income is from the 2006–2010 ACS. Jobs are LODES7 RAC and WAC all-job counts; population is from SEER.')
sc=next(x for x in read('descriptives/project_scale_summary.csv') if x['sample']=='eligible');raw=[x for x in read('descriptives/first_and_cumulative_units.csv') if x['eligible']=='TRUE']
def nums(key):return [float(x[key]) for x in raw if x[key] not in ['NA','']]
def ratios(key):return [float(x[key])/float(x['seer_total_population'])*1000 for x in raw if x[key] not in ['NA',''] and x['seer_total_population'] not in ['NA',''] and float(x['seer_total_population'])>0]
rr=[]
for label,k in [('Mean units','mean'),('Median units','median'),('SD','sd')]:rr.append([label,f"{float(sc['first_'+k]):.1f}",f"{float(sc['cumulative_'+k]):.1f}"])
rr += [['Mean units per 1,000 population',f"{float(sc['first_per1000']):.1f}",f"{float(sc['cumulative_per1000']):.1f}"],['Median units per 1,000 population',f"{statistics.median(ratios('first_units')):.1f}",f"{statistics.median(ratios('cumulative_units')):.1f}"],['Share of cumulative units at first placement',f"{float(sc['first_share'])*100:.1f}%",''],['Tracts with only one project',f"{float(sc['one_project_share'])*100:.1f}%",''],['Observations (eligible treated tracts)',sc['tracts'],sc['tracts']],['Tracts with valid unit counts',len(nums('first_units')),len(nums('cumulative_units'))]]
assets+=customtable('LIHTC Project Scale: First Placement versus Cumulative Units','tab:first_vs_cum',['','First placement','Cumulative (by 2019)'],rr,'The sample contains matching-eligible treated tracts first receiving new construction in 2011–2019. First-placement units sum eligible new-construction projects in the first treatment year; cumulative units sum new-construction projects through 2019. Invalid or incomplete unit counts are excluded from unit summaries without imputation. Units per 1,000 residents use 2010 SEER population. The first-placement share is the mean tract-level first-to-cumulative ratio; the one-project share uses all eligible treated tracts.')
c=read('descriptives/cohorts.csv');assets+=customtable('Treatment Cohort Distribution','tab:cohorts',['Cohort']+[x['cohort'] for x in c],[['Eligible treated tracts']+[x['eligible'] for x in c],['Matched treated tracts']+[x['matched'] for x in c]],'Counts are for the pooled design. The eligible cohort-specific candidate pools contain 2,566 treated tracts; 2,048 receive matches. The 2010 cohort is excluded because the panel contains no observed pre-treatment year. Matching is one-to-one within state; income and construction-intensity groups are matched independently.')
for id,label in [('pooled','tab:main'),('intensity','tab:intensity'),('income','tab:income')]:assets+=table_from(id,label)
# Preserve the workplace-distance table using refreshed estimates and reordered specifications.
a=read('all_att.csv');specs=['matched_pair_year','matched_year','full_county_year'];rr=[]
for y,l in [('near_per_pop_10','Nearby jobs / population (pp)'),('far_per_pop_10','Farther jobs / population (pp)'),('log_near_jobs_10','Nearby jobs (log)'),('log_far_jobs_10','Farther jobs (log)'),('near_share_10','Nearby share (pp)'),('same_tract_per_pop','Same-tract jobs / population (pp)')]:
 row=[l]
 for sp in specs:
  r=next(x for x in a if x['analysis']=='near_far' and x['specification']==sp and x['outcome']==y);scale=1 if y.startswith('log') else 100;pv=float(r['p_value']);star='***' if pv<.01 else '**' if pv<.05 else '*' if pv<.1 else '';row.append(f"{float(r['estimate'])*scale:.4f}{star}|BR|({float(r['std_error'])*scale:.4f})")
 rr.append(row)
rr.append(['Observations']+[f"{int(next(x for x in a if x['analysis']=='near_far' and x['specification']==sp)['observations']):,}" for sp in specs])
rr.extend([['Tract FE','✓','✓','✓'],['Year FE','Absorbed','✓','Absorbed'],['County × year FE','','','✓'],['Pair × year FE','✓','',''],['PSM matched sample','✓','✓','']])
assets+=customtable('Resident-Held Jobs by Workplace Distance','tab:near_far',['','(1)','(2)','(3)'],rr,'Sun and Abraham aggregate effects with tract-clustered standard errors in parentheses. Columns (1)–(3) use matched pair-by-year, matched year, and unmatched county-by-year effects. Nearby workplaces are within 10 km of the residence centroid, including the same tract. The nearby share divides nearby jobs by covered OD jobs. All distance outcomes use common observations within each specification. * p < 0.10, ** p < 0.05, *** p < 0.01.')
for id,label,aliases in [('es_pooled_emp_pop_ratio','fig:emppop',['fig:pop','fig:rac','fig:wac']),('es_intensity','fig:intensity',[]),('wage','fig:wagetier',[]),('industry','fig:industry_employment',[]),('es_commute','fig:commute',[]),('commute','fig:commute_subgroups',[]),('es_income_emp_pop_ratio','fig:income_emppop',[]),('es_income_log_rac','fig:income_rac',[]),('es_income_log_wac','fig:income_wac',[]),('es_income_log_seer_pop','fig:income_pop',[]),('income_wage','fig:income_wage',[])]:assets+=fig(id,label,aliases)
for file,caption,label,note in [('near_far.pdf','Employment by Workplace Distance: Population-Normalized and Log Outcomes','fig:near_far','Main-specification event-study estimates. Nearby jobs are within 10 km, including same-tract jobs. Upper panels report percentage-point effects; lower panels report log-point effects. The sample is common across outcomes. Bars denote 95 percent tract-clustered intervals; year -1 is normalized to zero.'),('radius.pdf','Nearby and Farther Employment Effects Across Radius Definitions','fig:near_far_radius','Main-specification aggregate effects using common observations across 5, 10, and 20 km thresholds. Bars denote 95 percent tract-clustered confidence intervals.')]:assets+=figure(caption,label,'generated_guarded/'+file,note)
assets+='\n\\clearpage\\appendix\n\\setcounter{table}{0}\\renewcommand{\\thetable}{A\\arabic{table}}\\renewcommand{\\theHtable}{appendix.\\arabic{table}}\n\\setcounter{figure}{0}\\renewcommand{\\thefigure}{A\\arabic{figure}}\\renewcommand{\\theHfigure}{appendix.\\arabic{figure}}\n\\section*{Appendix: Matching}\n'
covrows=[['Log population; age and race/ethnicity shares','SEER'],['Log RAC and WAC; low- and high-wage job shares','LODES'],['Recent log population, RAC and WAC growth','SEER / LODES'],['Recent absolute RAC and WAC growth','LODES'],['Earlier log population, RAC and WAC growth','SEER / LODES'],['Earlier absolute RAC and WAC growth','LODES']]
assets+=customtable('Propensity Score Matching Covariates','tab:psm_covariates',['Covariate','Source'],covrows,'Levels and shares are measured at g−1. Recent growth uses 2010–2011 for cohort 2012 and annualized changes from g−3 to g−1 for cohorts 2013–2019. Earlier growth uses annualized changes from g−5 to g−3 for cohorts 2015–2019. Cohort 2011 uses levels and shares only. The pooled design contains 2,048 pairs. Matching is within state, with a propensity-score caliper and the covariate and scale constraints described in the text.')
assets+=figure('Covariate Balance Before and After Propensity Score Matching','fig:psm_balance','generated_guarded/balance.pdf','Before refers to the eligible treated and control candidate pools within each cohort; after refers to selected pairs. Each standardized difference divides the treated-control mean difference by the eligible treated standard deviation. Points report absolute standardized differences averaged across applicable cohorts, weighted by matched treated counts. The dashed line marks 0.1. Earlier growth covariates apply only to cohorts 2015–2019. This is a summary of covariate balance, not a test of parallel trends.')
assets+='\n\\section*{Appendix: Primary-Job Robustness}\n'
assets+=table_from('a3','tab:primary_pooled')+table_from('a4','tab:primary_heterogeneity')+fig('a9','fig:primary_comparison')
assets+='\n\\section*{Appendix: Spatial Spillovers}\n'+table_from('spatial_table_3','tab:spatial')
for id,label in [('spatial_log_rac','fig:spatial_rac'),('spatial_log_wac','fig:spatial_wac'),('spatial_log_population','fig:spatial_pop')]:assets+=fig(id,label)
(OUT/'tables_figures.tex').write_text(assets)

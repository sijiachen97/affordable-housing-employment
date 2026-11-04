def figure(id,title,file,note):
 parts.append(f'<section id="{id}"><h2>{title}</h2><img src="{file}" alt="{title}"><p class="note"><i>Notes:</i> {note}</p></section>')
esnote='Sun and Abraham interaction-weighted event-study coefficients from the main specification with tract and pair-by-year fixed effects. Vertical bars show 95% confidence intervals based on tract-clustered standard errors. The year before placement is normalized to zero. '+match
figure('es_pooled_emp_pop_ratio','Event-Study Estimates: Employment-to-Population Ratio, Log Resident-Held Jobs, Log Workplace Jobs, and Log Total Population','es_pooled_main_combined.png',esnote+' Panel (a) reports percentage-point effects; panels (b)–(d) report log-point effects. Each panel has its own vertical scale.')
for y,l in [('emp_pop_ratio','Employment-to-Population Ratio'),('log_rac','Log Resident-Held Jobs (Total)'),('log_wac','Log Workplace Jobs (Total)'),('log_seer_pop','Log Total Population')]:
 figure('es_income_'+y,'Event-Study Estimates by Neighborhood Income: '+l,'es_income_'+y+'.png',esnote+(' The ratio is expressed in percentage points.' if y=='emp_pop_ratio' else '')+' Income groups are matched separately.')
figure('es_commute','Event-Study Estimates: Average Commuting Distance (Road Network, Residence Panel, All Workers)','es_pooled_commute.png',esnote+' The outcome is mean commuting distance in kilometers, weighted by available within-state OD jobs.')
figure('es_intensity','Event-Study Estimates by Construction Intensity: Employment-to-Population Ratio','es_intensity_emp_pop_ratio.png',esnote+' The ratio is expressed in percentage points. Intensity groups split at 13.34 first-placement units per 1,000 residents and are matched independently.')
# A3 keeps all-job/primary columns within each specification.
body=''
prows=[('Employment-to-population ratio','emp_pop_ratio','emp_pop_ratio','primary_emp_pop_ratio'),('Resident-held jobs (log)','rac_total','log_rac','log_primary_rac'),('Resident-held jobs (level)','rac_total','rac_total','primary_rac_total')]+[(l+' jobs (log)','log_rac_'+k,'log_rac_'+k,'log_primary_rac_'+k) for k,l in [('low','Low-wage'),('mid','Mid-wage'),('high','High-wage')]]
for l,a,o,p in prows:body+=tr(l,[cell(get('primary/'+a,'pooled',s,y)) for s in specs for y in [o,p]])
for l,a,ys in [('Observations: RAC / population','emp_pop_ratio',['emp_pop_ratio','primary_emp_pop_ratio']),('Observations: job counts','rac_total',['rac_total','primary_rac_total'])]:
 body+=tr(l,[f"{int(get('primary/'+a,'pooled',s,y)['observations']):,}" for s in specs for y in ys],'rule' if 'population' in l else '')
for j,(l,vs) in enumerate([('Tract FE',['✓','✓','✓']),('Year FE',['Absorbed','✓','Absorbed']),('County × year FE',['','','✓']),('Pair × year FE',['✓','','']),('PSM matched sample',['✓','✓',''])]):body+=tr(l,[v for v in vs for _ in range(2)],'rule' if j==0 else '')
pnote='All-job and primary-job counts come from LODES Version 7 RAC, assigned by residence. Primary jobs retain each worker’s highest-earning job. Ratios divide the corresponding count by SEER population. Each primary-job regression uses the same observations and matching pairs as its all-job counterpart. '+wage+' '+base+' '+match
heads=[f'({i+1})<br>{k}' for i in range(3) for k in ['All jobs','Primary']]
table('a3','Table A3: Residence-Side Estimates Using All Jobs and Primary Jobs',heads,body,pnote+' Specifications (1), (2), and (3) use matched pair-by-year, matched year, and unmatched county-by-year effects, respectively.')
parts[-1]=parts[-1].replace('<thead>'+tr('',heads)+'</thead>', '<thead><tr><td></td><td colspan="2">(1)</td><td colspan="2">(2)</td><td colspan="2">(3)</td></tr>'+tr('', ['All jobs','Primary']*3)+'</thead>')
body=''
for title,an,gs in [('Panel A: Neighborhood income','primary',[('lower_income','Lower income'),('higher_income','Higher income')]),('Panel B: Construction intensity','primary_intensity',[('low_intensity','Low intensity'),('high_intensity','High intensity')])]:
 body+=f'<tr class="group"><td colspan="5">{title}</td></tr>'
 for g,l in gs:
  rr=[get(an+'/rac_total',g,specs[0],y) for y in ['log_rac','log_primary_rac']]+[get(an+'/emp_pop_ratio',g,specs[0],y) for y in ['emp_pop_ratio','primary_emp_pop_ratio']]
  body+=tr(l,[cell(r) for r in rr])+tr('Observations',[f"{int(r['observations']):,}" for r in rr],'nrow')
body+='<tr class="group"><td colspan="5">Panel C: Wage tiers by neighborhood income (log jobs)</td></tr>'+tr('',['Lower income<br>All jobs','Lower income<br>Primary','Higher income<br>All jobs','Higher income<br>Primary'])
for k,l in [('low','Low-wage jobs'),('mid','Mid-wage jobs'),('high','High-wage jobs')]:
 rr=[get('primary/log_rac_'+k,g,specs[0],y) for g in ['lower_income','higher_income'] for y in ['log_rac_'+k,'log_primary_rac_'+k]]
 body+=tr(l,[cell(r) for r in rr])
ns=[]
for g in ['lower_income','higher_income']:
 for prefix in ['log_rac_','log_primary_rac_']:
  vv=[get('primary/log_rac_'+k,g,specs[0],prefix+k)['observations'] for k in ['low','mid','high']];assert len(set(vv))==1;ns.append(f'{int(vv[0]):,}')
body+=tr('Observations (all wage tiers)',ns,'rule')
table('a4','Table A4: Primary-Job Robustness: Income, Construction Intensity, and Wage Tiers',['Resident-held jobs (log)<br>All jobs','Resident-held jobs (log)<br>Primary','Employment-to-population ratio<br>All jobs','Employment-to-population ratio<br>Primary'],body,main+' '+pnote+' Income and construction-intensity groups are matched independently.')
oldhead=parts[-1].split('<thead>')[1].split('</thead>')[0]
parts[-1]=parts[-1].replace('<thead>'+oldhead+'</thead>', '<thead><tr><td></td><td colspan="2">Resident-held jobs (log)</td><td colspan="2">Employment-to-population ratio</td></tr>'+tr('', ['All jobs','Primary']*2)+'</thead>')
figure('a9','Figure A9: Event-Study Comparison: All Jobs and Primary Jobs','primary_comparison.png',esnote+' Rows show the employment-to-population ratio (percentage points), log resident-held jobs, and log workplace jobs. Columns show pooled, lower-income, and higher-income estimates. All-job and primary-job comparisons use identical observations and matching pairs within each outcome and group. WAC comparisons use LODES primary workplace jobs (JT01).')
spnote='Retained Stage O specification: same-state matching with eligibility and covariate/scale constraints; treated areas with additional projects outside the center are excluded after matching, retaining their original controls. Center is the focal tract; surroundings are other tracts whose centroids lie within 3, 5, or 7 km of the center centroid; cumulative combines center and surroundings. Counts are summed over member tracts; logs are taken after summation, and ratios divide total jobs by total population. Each radius uses its own matched sample. Estimates use Sun and Abraham with center and pair-by-year fixed effects. Bars show 95% pointwise intervals using 50 km spatial HAC standard errors. Each panel has its own vertical scale. No previous estimates are overlaid.'
spatial_source=SRC.parent/'23_spatial_spillover/stage_o/estimates/att_long.csv'
spatial_rows=[r for r in csv.DictReader(spatial_source.open()) if r['covariance']=='spatial_50km' and r['estimator']=='sun_abraham']
assert len(spatial_rows)==63
spatial_used=[]
spatial_outcomes=[('Employment-to-population ratio','emp_pop_ratio'),('Population (log)','log_population'),('Population (level)','population'),('Resident-held jobs (log)','log_rac'),('Resident-held jobs (level)','rac'),('Workplace jobs (log)','log_wac'),('Workplace jobs (level)','wac')]
spatial_body=''
for panel,radius in zip(['A','B','C'],['3','5','7']):
 body=f'<tr class="group"><td colspan="4">Panel {panel}: {radius} km</td></tr>';these=[]
 for label,y in spatial_outcomes:
  vals=[]
  for component in ['center','surroundings','cumulative']:
   rr=[r for r in spatial_rows if (r['radius_km'],r['component'],r['outcome'])==(radius,component,y)];assert len(rr)==1
   r=rr[0];spatial_used.append(r);these.append(r)
   pv=float(r['p_value']);star='***' if pv<.01 else '**' if pv<.05 else '*' if pv<.1 else '';digits=2 if '(level)' in label else 4
   vals.append(f"{float(r['estimate']):.{digits}f}{star}<br><span class='se'>({float(r['std_error']):.{digits}f})</span>")
  body+=tr(label,vals)
 for field,label in [('observations','Observations'),('pairs','Matched pairs')]:
  vals=[]
  for c in ['center','surroundings','cumulative']:
   vs={r[field] for r in these if r['component']==c};assert len(vs)==1;vals.append(f'{int(next(iter(vs))):,}')
  body+=tr(label,vals,'rule' if field=='observations' else '')
 note='Sun and Abraham aggregate treatment effects over observed post-treatment horizons. Parentheses report 50 km spatial HAC standard errors. * p &lt; 0.10, ** p &lt; 0.05, *** p &lt; 0.01. '+spnote.split(' Bars show')[0]+' The employment-to-population ratio is expressed as a fraction. Level outcomes are persons or jobs. Observations count area-year regression rows, including centers used in multiple matched pairs.'
 spatial_body+=body
spatial_body+=tr('Center FE',['✓']*3,'rule')+tr('Pair × year FE',['✓']*3)
table('spatial_table_3','Aggregate Treatment Effects in Spatial Areas',['Center','Surroundings','Cumulative'],spatial_body,note)
with (OUT/'spatial_table_estimates.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=spatial_rows[0].keys());w.writeheader();w.writerows(spatial_used)
for y,l in [('log_rac','Log Resident-Held Jobs (Total)'),('log_wac','Log Workplace Jobs (Total)'),('log_population','Log Total Population')]:
 figure('spatial_'+y,'Spatial Event-Study Estimates: '+l,'spatial_'+y+'.png',spnote)

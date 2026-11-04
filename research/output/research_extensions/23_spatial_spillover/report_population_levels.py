# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys,json,hashlib
base=Path(sys.argv[1]);o=base/'estimates';read=lambda p:list(csv.DictReader(p.open()))
a=read(o/'att_long.csv');pre=read(o/'pretrend_tests.csv')
versions={'old_full':'Original (D)','prior_full':'Early log-growth constraints (G)','new_full':'Population + absolute job growth (H)'}
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_population':'Population (log)','population':'Population (level)','log_rac':'Resident-held jobs (log)','rac':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac':'Workplace jobs (level)'}
def get(r,c,y,s):return next(x for x in a if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km')
def pret(r,c,y,s):return float(next(x['p_value'] for x in pre if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km'))
def fmt(x):
 fac=100 if x['outcome']=='emp_pop_ratio' else 1;dec=1 if x['outcome'] in ['rac','wac','population'] else 4;p=float(x['p_value']);st='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*fac:.{dec}f}{st} ({float(x['std_error'])*fac:.{dec}f})"
md=['# Stage H：人口增长与就业绝对增量匹配','','使用2010–2019面板，包含2011–2019全部treated cohorts。仅新增处理前population log增长以及RAC/WAC绝对年增量，中心和周边分别计算。2011水平匹配不变；2012用2010–2011变化；2013起用g−3至g−1年均变化；2015起同时用g−5至g−3年均变化。已有log RAC/WAC增长约束保留。','','新增变量同时进入logit propensity、1 treated-SD配对门槛和距离排序。其他规则不变：同州、距离>2r、不重叠、clean control、0.2 pooled-SD propensity门槛、cohort内control不复用。FE、SA聚合和空间协方差保持不变。','','## 样本','','| 半径 | D | G | H |','|---|---:|---:|---:|']
for r in [3,5,10]:md.append('| '+str(r)+' km | '+' | '.join(get(r,'center','rac',s)['pairs'] for s in versions)+' |')
md+=['','## 重点诊断：联合lead检验p（−5至−2）','','| 半径 | 部分 | outcome | D | G | H |','|---|---|---|---:|---:|---:|']
for r,c,y in [(10,c,'log_population') for c in ['center','surroundings','cumulative']]+[(r,'surroundings','rac') for r in [3,5,10]]:
 md.append('| '+f'{r} km | {c} | {y} | '+' | '.join(f'{pret(r,c,y,s):.4f}' for s in versions)+' |')
md+=['','## log RAC ATT（50 km空间SE）','','| 半径 | 部分 | D | G | H |','|---|---|---:|---:|---:|']
for r in [3,5,10]:
 for c in ['center','surroundings','cumulative']:md.append('| '+f'{r} km | {c} | '+' | '.join(fmt(get(r,c,'log_rac',s)) for s in versions)+' |')
md+=['','## 方法解释','','使用处理前outcome历史匹配可以帮助构造有相近增长背景的比较组，但不保证平行趋势成立，也不保证比不匹配更无偏。暂时性冲击、测量误差及均值回归可引入新的偏误。匹配已使用这些处理前资料，匹配后的lead检验不是独立验证。此规则是在看到既有pretrend后提出，属于敏感性分析，不应称为事前预注册设计。','','只运行一次固定规则，未根据处理后显著性或lead p值调整门槛。cohort保留率改变会改变ATT权重。2011无增长信息，2012仅一年变化，不能补造处理前历史。首次placement前若已有预期或施工影响，匹配也可能控制掉政策早期反应。','','参考：Daw and Hatfield (2018), https://pmc.ncbi.nlm.nih.gov/articles/PMC6232412/ ; Roth (2022), https://www.aeaweb.org/articles?id=10.1257%2Faeri.20210236 。','','## 验证','','独立从原面板重算所有core变量、检查配对差异；核对never/future controls资格、非重叠和不复用；63个SA模型通过观测完整性、fixest ATT一致性、协方差恒等核检查和level可加性。旧结果均保留。']
md+=['','## 本次判断','','10 km人口log处理前轨迹显著变平；5 km周边RAC level的联合lead p从G的0.0004升至0.2706，且图上差异缩小。3 km周边RAC level仍存在差异（p=0.0327）。5 km log RAC中心/周边/累计lead p分别0.5131、0.7830、0.7263；10 km log RAC仍存在问题（中心0.0232，周边约0.00005，累计约0.00013）。因此不能说本次匹配解决了全部半径和outcome的平行趋势问题。','','样本缩小和controls变化共同影响结果，不能把检验p变化全归因于平衡改善。当前更适合作为有明确变量依据的敏感性版本；保留其他版本供比较。']
parts=['<!doctype html><meta charset="utf-8"><title>Population and absolute job-growth matching</title><style>body{font:16px system-ui;max-width:1400px;margin:40px auto;padding:0 24px;color:#243348}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{padding:8px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}details{margin:24px 0}.note{color:#596b7e;font-size:14px}</style><h1>Population and absolute job-growth matching</h1><p>All 2011–2019 treatment cohorts; 2010–2019 panel. Sun–Abraham ATT only. Center FE + pair × year FE. Main inference: full-time spatial HAC, 50 km.</p><p>H adds center/surrounding population log growth and RAC/WAC absolute annual changes to propensity, core calipers and ranking. Recent growth where available from 2012; earlier growth from 2015. The 2011 cohort remains level-only. Other rules unchanged.</p><p><a href="RESULTS_CN.md">中文说明</a> · <a href="../stage_d/results.html">Original D</a> · <a href="../stage_g/results.html">Previous G</a> · <a href="estimates/att_long.csv">All estimates / spatial bandwidths</a> · <a href="matching/balance_by_cohort.csv">Matching balance</a></p>']
for r in [3,5,10]:
 parts.append(f'<details open><summary><b>{r} km: '+ ' / '.join(f'{versions[s]}: {get(r,"center","rac",s)["pairs"]} pairs' for s in versions)+'</b></summary>')
 for c in ['center','surroundings','cumulative']:
  parts.append(f'<h3>{c}</h3><table><tr><th>Outcome</th>'+''.join(f'<th>{v}<br>ATT (SE)</th>' for v in versions.values())+''.join(f'<th>{s}<br>lead p</th>' for s in ['D','G','H'])+'</tr>')
  for y,label in labels.items():parts.append(f'<tr><td>{label}</td>'+''.join(f'<td>{fmt(get(r,c,y,s))}</td>' for s in versions)+''.join(f'<td>{pret(r,c,y,s):.4f}</td>' for s in versions)+'</tr>')
  parts.append('<tr><td>Observations</td>'+''.join(f'<td>{get(r,c,"rac",s)["observations"]}</td>' for s in versions)+'<td colspan="3"></td></tr></table>')
 parts.append('</details>')
for y,label in labels.items():parts.append(f'<details open><summary>{label}</summary><img src="estimates/comparison_full_{y}.png"></details>')
parts.append('<p class="note">95% pointwise intervals. Stars: 10%, 5%, 1%. Pre-period tests use matching-period data and are not independent validation. Sample retention and ATT weights differ. Estimates conditional on matching. No thresholds tuned to effect estimates or test p-values.</p>')
(base/'results.html').write_text('\n'.join(parts));(base/'RESULTS_CN.md').write_text('\n'.join(md)+'\n')
root=Path('./output/research_extensions/23_spatial_spillover')
paths=[root/s/f for s in ['stage_d','stage_f','stage_g'] for f in ['results.html']]
(base/'original_files_sha256.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2))
print('\n'.join(md[:40]))

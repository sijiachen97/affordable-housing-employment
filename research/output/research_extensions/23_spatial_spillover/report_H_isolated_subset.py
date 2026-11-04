# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys,json,hashlib
base=Path(sys.argv[1]);o=base/'estimates';read=lambda p:list(csv.DictReader(p.open()))
a=read(o/'att_long.csv');pre=read(o/'pretrend_tests.csv')
versions={'old_full':'Stage H','new_full':'Filtered H pairs (L)'}
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_population':'Population (log)','population':'Population (level)','log_rac':'Resident-held jobs (log)','rac':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac':'Workplace jobs (level)'}
def get(r,c,y,s):return next(x for x in a if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km')
def pret(r,c,y,s):return float(next(x['p_value'] for x in pre if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km'))
def fmt(x):
 fac=100 if x['outcome']=='emp_pop_ratio' else 1;dec=1 if x['outcome'] in ['rac','wac','population'] else 4;p=float(x['p_value']);st='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*fac:.{dec}f}{st} ({float(x['std_error'])*fac:.{dec}f})"
md=['# Stage L：筛选H原配对，周边无新增项目，不重新匹配','','直接从H保留treated周边成员tract在2010–2019无新增TYPE=1项目且无未知placement年份记录的配对。全部control保持原H配对，不要求treated也在J匹配成功。历史项目与中心内后续项目允许。成员范围按tract centroid计算。','','七个outcome、三个半径、center/surroundings/cumulative均估计SA ATT和event study。center FE + pair-year FE，50 km空间协方差主报告，25/100 km及center cluster在CSV中。','','| 半径 | H原pairs | 筛选后pairs |','|---|---:|---:|']
for r in [3,5,10]:md.append(f"| {r} km | {get(r,'center','rac','old_full')['pairs']} | {get(r,'center','rac','new_full')['pairs']} |")
md+=['','## 主要结果','','- 3 km累计RAC约增加110（SE43），log约1.80%，就业人口比约0.73pp，均显著；累计log RAC仍有pretrend（p=0.034）。','- 5 km累计RAC约增加162（SE77），log约1.66%，就业人口比约0.70pp，均显著；累计level、log及ratio的lead p约0.349、0.606、0.494。','- 3/5 km周边RAC level分别约33/59且不显著；log RAC与就业人口比为正且在5%显著。','- 3 km中心WAC level约149（SE71），p=0.035；log约2.57%但不显著。5 km中心WAC仍有明显pretrend。','- 10 km累计RAC数量与log不显著，部分pretrend仍存在。不同半径保留不同中心，并非固定样本的距离梯度。','','保留H controls避免重新匹配引起的controls变化，但筛选仍改变样本与cohort权重。全窗口周边筛选涉及处理后的项目布局，并不独立识别某个项目的纯因果贡献。','','## 验证','','从原始TYPE=1记录独立重算筛选名单，核对同州、control资格、成员不重叠和不复用。63个SA模型均保留预定观测；fixest聚合、空间核恒等及level可加性检查通过。fixest辅助协方差一次数值PSD修复提示，独立核协方差检查通过。']
parts=['<!doctype html><meta charset="utf-8"><title>Same-state isolated-area comparison</title><style>body{font:16px system-ui;max-width:1300px;margin:40px auto;padding:0 24px;color:#243348}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{padding:8px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}details{margin:24px 0}.warn{padding:18px;background:#fff0d9}.note{font-size:14px;color:#586979}</style><h1>Filtered H pairs: isolated surroundings, original controls</h1><p>No rematching. Retain all H pairs whose treated surroundings have no known TYPE=1 placements during 2010–2019 and no unknown timing. Historical neighboring projects and subsequent center projects remain allowed. No requirement to appear in J.</p><p>396 / 306 / 182 pairs at 3 / 5 / 10 km. Sun–Abraham ATT and event study; center and pair-year FE; spatial HAC 50 km.</p><p><a href="RESULTS_CN.md">中文说明与样本流失</a> · <a href="../stage_h/results.html">Stage H</a> · <a href="estimates/cohort_retention.csv">Cohort sample flow</a> · <a href="estimates/att_long.csv">All estimates</a></p>']
for r in [3,5,10]:
 parts.append(f'<details open><summary><b>{r} km: H {get(r,"center","rac","old_full")["pairs"]} / L {get(r,"center","rac","new_full")["pairs"]} pairs</b></summary>')
 for c in ['center','surroundings','cumulative']:
  parts.append(f'<h3>{c}</h3><table><tr><th>Outcome</th><th>Stage H ATT (SE)</th><th>Stage L ATT (SE)</th><th>H lead p</th><th>L lead p</th></tr>')
  for y,label in labels.items():parts.append(f'<tr><td>{label}</td>'+''.join(f'<td>{fmt(get(r,c,y,v))}</td>' for v in versions)+''.join(f'<td>{pret(r,c,y,v):.4f}</td>' for v in versions)+'</tr>')
  parts.append('<tr><td>Observations</td>'+''.join(f'<td>{get(r,c,"rac",v)["observations"]}</td>' for v in versions)+'<td></td><td></td></tr></table>')
 parts.append('</details>')
for y,label in labels.items():
 parts.append(f'<details open><summary>{label}: filtered H sample</summary><img src="estimates/eventstudy_{y}.png"><details><summary>Compare with full H</summary><img src="estimates/comparison_full_{y}.png"></details></details>')
parts.append('<p class="note">Center FE + pair × year FE; Sun–Abraham ATT, full-time spatial HAC 50 km. Pointwise 95% intervals, stars at 10/5/1%. Lead tests cover available aggregated years −5 to −2. Samples differ, including retained cohorts. Treated isolation is the added restriction; estimates concern a different matched sample. Matching-period tests are not independent validation.</p>')
(base/'results.html').write_text('\n'.join(parts));(base/'RESULTS_CN.md').write_text('\n'.join(md)+'\n')
root=Path('./output/research_extensions/23_spatial_spillover')
paths=[root/'stage_h'/f for f in ['results.html','estimates/att_long.csv','matching/matched_pairs.csv']]
(base/'original_files_sha256.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2))

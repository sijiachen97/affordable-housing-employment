# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys,json,hashlib
base=Path(sys.argv[1]);o=base/'estimates';read=lambda p:list(csv.DictReader(p.open()))
a=read(o/'att_long.csv');pre=read(o/'pretrend_tests.csv')
versions={'old_full':'Stage H','new_full':'Same state + isolated surroundings (J)'}
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_population':'Population (log)','population':'Population (level)','log_rac':'Resident-held jobs (log)','rac':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac':'Workplace jobs (level)'}
def get(r,c,y,s):return next(x for x in a if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km')
def pret(r,c,y,s):return float(next(x['p_value'] for x in pre if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km'))
def fmt(x):
 fac=100 if x['outcome']=='emp_pop_ratio' else 1;dec=1 if x['outcome'] in ['rac','wac','population'] else 4;p=float(x['p_value']);st='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*fac:.{dec}f}{st} ({float(x['std_error'])*fac:.{dec}f})"
md=['# Stage J：同州匹配＋周边无新增项目','','与Stage H相比，仅新增treated周边项目筛选：周边成员tract在2010–2019无TYPE=1新建LIHTC placement，且没有未知placement年份记录。历史项目、中心内后续项目仍允许。仍同州匹配；协变量、propensity与core门槛及FE、协方差算法保持不变。propensity模型与标准化SD随合格treated池重新计算。','','这是孤立开发子样本的估计，不是固定Stage H全部treated中心的比较；不应将结果差异完全解释成周边项目的因果贡献。','','| 半径 | H pairs | I同县隔离 pairs | J同州隔离 pairs |','|---|---:|---:|---:|']
for r,ni in [(3,121),(5,64),(10,16)]:md.append(f"| {r} km | {get(r,'center','rac','old_full')['pairs']} | {ni} | {get(r,'center','rac','new_full')['pairs']} |")
md+=['','## RAC/WAC结果','','| 半径 | 区域 | outcome | H ATT(SE) | J ATT(SE) | J lead p |','|---|---|---|---:|---:|---:|']
for r in [3,5,10]:
 for c in ['center','surroundings','cumulative']:
  for y in ['log_rac','rac','log_wac','wac']:md.append(f"| {r} | {c} | {y} | {fmt(get(r,c,y,'old_full'))} | {fmt(get(r,c,y,'new_full'))} | {pret(r,c,y,'new_full'):.4f} |")
md+=['','Control资格未变：全窗口无新建项目、无未知年份、成员完整、距离及成员不重叠。匹配保留never-treated。独立核验原始项目、同州、配对距离、control资格及level可加性。空间核50 km主报告，25/100敏感性在CSV。','', '本次不替换论文或Stage H。']
md+=['','主要发现：3 km累计RAC增加213（SE43），log约2.12%；但周边log RAC lead p=0.019。5 km累计log RAC约1.06%（p=0.015），累计level约158但不显著；累计log lead p=0.712。3/5 km中心WAC不显著，且有部分pretrend。10 km累计RAC数量与log均不显著，log pretrend仍明显。不能认为本版本稳定验证了中心岗位创造。','', 'fixest辅助协方差计算有2次非半正定修复提示；主空间核协方差独立计算，身份核等于center clustering验证通过。']
parts=['<!doctype html><meta charset="utf-8"><title>Same-state isolated-area comparison</title><style>body{font:16px system-ui;max-width:1300px;margin:40px auto;padding:0 24px;color:#243348}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{padding:8px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}details{margin:24px 0}.warn{padding:18px;background:#fff0d9}.note{font-size:14px;color:#586979}</style><h1>Same-state matching and isolated treated surroundings</h1><p>Stage H matching covariates and calipers; Stage J retains same-state geography and excludes treated surroundings with any 2010–2019 TYPE=1 project or unknown timing. Center subsequent projects and historical neighboring projects remain allowed.</p><p class="warn">Stage J retains 314 / 213 / 149 pairs at 3 / 5 / 10 km. Same-state matching is retained from Stage H. Only treated surrounding-project eligibility changes; sample composition and controls may therefore change.</p><p><a href="RESULTS_CN.md">中文说明与样本流失</a> · <a href="../stage_h/results.html">Stage H</a> · <a href="matching/sample_flow.csv">Cohort sample flow</a> · <a href="estimates/att_long.csv">All estimates</a></p>']
for r in [3,5,10]:
 parts.append(f'<details open><summary><b>{r} km: H {get(r,"center","rac","old_full")["pairs"]} / J {get(r,"center","rac","new_full")["pairs"]} pairs</b></summary>')
 for c in ['center','surroundings','cumulative']:
  parts.append(f'<h3>{c}</h3><table><tr><th>Outcome</th><th>Stage H ATT (SE)</th><th>Stage J ATT (SE)</th><th>H lead p</th><th>J lead p</th></tr>')
  for y,label in labels.items():parts.append(f'<tr><td>{label}</td>'+''.join(f'<td>{fmt(get(r,c,y,s))}</td>' for s in versions)+''.join(f'<td>{pret(r,c,y,s):.4f}</td>' for s in versions)+'</tr>')
  parts.append('<tr><td>Observations</td>'+''.join(f'<td>{get(r,c,"rac",s)["observations"]}</td>' for s in versions)+'<td></td><td></td></tr></table>')
 parts.append('</details>')
for y,label in labels.items():parts.append(f'<details open><summary>{label}</summary><img src="estimates/comparison_full_{y}.png"></details>')
parts.append('<p class="note">Center FE + pair × year FE; Sun–Abraham ATT, full-time spatial HAC 50 km. Pointwise 95% intervals, stars at 10/5/1%. Lead tests cover available aggregated years −5 to −2. Samples differ, including retained cohorts. Treated isolation is the added restriction; estimates concern a different matched sample. Matching-period tests are not independent validation.</p>')
(base/'results.html').write_text('\n'.join(parts));(base/'RESULTS_CN.md').write_text('\n'.join(md)+'\n')
root=Path('./output/research_extensions/23_spatial_spillover')
paths=[root/'stage_h'/f for f in ['results.html','estimates/att_long.csv','matching/matched_pairs.csv']]
(base/'original_files_sha256.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2))

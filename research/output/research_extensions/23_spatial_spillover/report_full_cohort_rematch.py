# -*- coding: utf-8 -*-
from pathlib import Path
import csv, json, hashlib, sys
base=Path(sys.argv[1]);o=base/'estimates'
root=Path('./output/research_extensions/23_spatial_spillover')
read=lambda p:list(csv.DictReader(p.open()))
a=read(o/'att_long.csv');pre=read(o/'pretrend_tests.csv')
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_population':'Population (log)','population':'Population (level)','log_rac':'Resident-held jobs (log)','rac':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac':'Workplace jobs (level)'}
def get(r,c,y,s): return next(x for x in a if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km')
def pret(r,c,y,s): return float(next(x['p_value'] for x in pre if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km'))
def fmt(x):
 f=100 if x['outcome']=='emp_pop_ratio' else 1;d=1 if x['outcome'] in ['rac','wac','population'] else 4;p=float(x['p_value']);st='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*f:.{d}f}{st} ({float(x['std_error'])*f:.{d}f})"
parts=['<!doctype html><meta charset="utf-8"><title>All-cohort rematching comparison</title><style>body{font:16px system-ui;max-width:1250px;margin:40px auto;padding:0 24px;color:#243348}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{padding:9px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}details{margin:25px 0}.note{color:#596b7e;font-size:14px}</style><h1>All cohorts: original versus expanded matching</h1><p><b>2010–2019 panel; treatment cohorts 2011–2019 in both columns.</b> Earlier cohorts retain their original pairs. Only 2015–2019 cohorts use the expanded early-growth matching.</p><p>Sun–Abraham aggregated ATT and event study. Original center FE + pair × year FE. Full-time spatial HAC 50 km (25/100 km also in CSV).</p><p>The original column is copied directly from Stage D, including the 3 km center population ATT of 16.2. Stage F was a separate late-cohort comparison.</p><p><a href="../stage_d/results.html">Stage D original</a> · <a href="../stage_f/results.html">Stage F late cohorts</a> · <a href="estimates/att_long.csv">Estimates and bandwidth sensitivity</a></p>']
md=['# 全部 cohort：原匹配与加入更早增长约束的比较','','两列均使用2010–2019面板、2011–2019 treatment cohorts。2011–2014沿用原配对；2015–2019采用Stage F重新匹配。2010年无处理前观测，不作为treated cohort。原版直接读取Stage D，不覆盖旧文件。','','样本及cohort权重仍因匹配保留率变化而不同；这比较的是采用新规则后的总体结果，并非固定全部treated中心只更换control的比较。Stage F另有晚cohort共同treated样本比较。','','| 半径 | 原版pairs | 新版pairs |','|---|---:|---:|']
for r in [3,5,10]:
 old=get(r,'center','rac','old_full');new=get(r,'center','rac','new_full')
 md.append(f"| {r} km | {old['pairs']} | {new['pairs']} |")
 parts.append(f'<details open><summary><b>{r} km: {old["pairs"]} original / {new["pairs"]} expanded pairs</b></summary>')
 for c in ['center','surroundings','cumulative']:
  parts.append(f'<h3>{c}</h3><table><tr><th>Outcome</th><th>Original full-cohort ATT (SE)</th><th>Expanded full-cohort ATT (SE)</th><th>Original lead p</th><th>Expanded lead p</th></tr>')
  for y,label in labels.items():parts.append(f'<tr><td>{label}</td><td>{fmt(get(r,c,y,"old_full"))}</td><td>{fmt(get(r,c,y,"new_full"))}</td><td>{pret(r,c,y,"old_full"):.4f}</td><td>{pret(r,c,y,"new_full"):.4f}</td></tr>')
  parts.append(f'<tr><td>Observations</td><td>{old["observations"]}</td><td>{new["observations"]}</td><td></td><td></td></tr></table>')
 parts.append('</details>')
md+=['','## log RAC','','| 半径 | 区域 | 原ATT(SE) | 新ATT(SE) | 原lead p | 新lead p |','|---|---|---:|---:|---:|---:|']
for r in [3,5,10]:
 for c in ['center','surroundings','cumulative']:md.append(f'| {r} km | {c} | {fmt(get(r,c,"log_rac","old_full"))} | {fmt(get(r,c,"log_rac","new_full"))} | {pret(r,c,"log_rac","old_full"):.4f} | {pret(r,c,"log_rac","new_full"):.4f} |')
parts.append('<h2>Event-study comparisons</h2>')
for y,label in labels.items():parts.append(f'<details open><summary>{label}</summary><img src="estimates/comparison_full_{y}.png"></details>')
parts.append('<p class="note">Stars: p &lt; .10 / .05 / .01. Pointwise 95% intervals. Joint lead tests cover −5 through −2. Matching uses pre-treatment trajectories; these tests are not independent validation. Cohort composition and post-period weights change with pair retention. Later horizons disproportionately reflect earlier cohorts whose matching was unchanged.</p>')
md+=['','原始配对与Stage D结果均保持不变。新版63个SA模型，均保留预定观测；SA ATT等于fixest聚合；空间核取单位矩阵时等于中心cluster协方差；level ATT满足center+surroundings=cumulative。','', '注意：处理后较长horizon主要来自未重新匹配的早期cohorts。联合lead检验不应作为单独决定采用哪种匹配方法的标准。']
(base/'results.html').write_text('\n'.join(parts));(base/'RESULTS_CN.md').write_text('\n'.join(md))
oldpaths=[root/'stage_c/matched_pairs.csv',root/'stage_d/att_long.csv',root/'stage_d/event_study.csv',root/'stage_d/results.html']
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in oldpaths}
prev=json.loads((root/'stage_f/original_files_sha256.json').read_text());assert all(prev[k]==v for k,v in hashes.items())
(base/'original_files_sha256.json').write_text(json.dumps(hashes,indent=2))
print('\n'.join(md))

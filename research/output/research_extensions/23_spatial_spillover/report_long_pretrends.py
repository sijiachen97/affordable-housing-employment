# -*- coding: utf-8 -*-
from pathlib import Path
import csv,html,json,hashlib
base=Path(__file__).parent/'stage_f';o=base/'estimates';m=base/'matching'
project=Path('./output/research_extensions/23_spatial_spillover')
read=lambda p:list(csv.DictReader(p.open()))
a=read(o/'att_long.csv');pre=read(o/'pretrend_tests.csv');oldall=read(project/'stage_d/att_long.csv')
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_population':'Population (log)','population':'Population (level)','log_rac':'Resident-held jobs (log)','rac':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac':'Workplace jobs (level)'}
def get(r,c,y,s):return next(x for x in a if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km')
def pret(r,c,y,s):return float(next(x['p_value'] for x in pre if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km'))
def fmt(x):
 fac=100 if x['outcome']=='emp_pop_ratio' else 1;dec=1 if x['outcome'] in ['rac','wac','population'] else 4;p=float(x['p_value']);star='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*fac:.{dec}f}{star} ({float(x['std_error'])*fac:.{dec}f})"
lines=['# 更早处理前增长约束：2015–2019 cohorts重新匹配与Sun–Abraham比较','', '旧版Stage C/D/E文件保留。新版仅报告Sun–Abraham aggregated ATT和event study，不估计standard DID。','', '## 设计与可比性','','沿用同州跨县、原有controls暴露筛选、1 SD关键变量配对门槛、0.2 pooled-SD倾向得分门槛。在中心与周边原有g−3至g−1的RAC/WAC年均log增长之外，增加g−5至g−3的RAC/WAC年均log增长：共新增四个变量，同时进入logit得分、硬性距离门槛及关键变量距离。未额外改变水平变量定义或调整门槛。','', '只使用2015–2019 cohorts，确保每组有五年处理前数据。样本变化必须与重新匹配区分，所以报告四套估计：旧配对限制在2015–2019、新配对，以及各半径共同treated中心上的旧/新配对。共同treated比较保留完全相同的cohort构成，controls允许变化。','', 'FE、参考期、空间协方差都与Stage D一致：原始中心FE+pair×year FE；ref.p=c(−1,.F)；50 km全时间空间HAC为主，25/100 km敏感性。只有SA估计。所有outcome与center/surrounding/cumulative在各设计内使用相同行。','', '2015–2019在2010–2019面板最多只观察到event +4（仅2015贡献），没有+5。新旧晚cohort版本均使用各自可观察post horizons聚合，因此不应直接与旧版2011–2019的ATT等同。','','## 样本','','| 半径 | 旧匹配2011–2019 | 旧匹配2015–2019 | 新匹配2015–2019 | 新旧共同treated |','|---|---:|---:|---:|---:|']
for r,nall in [(3,1043),(5,1014),(10,733)]:lines.append(f"| {r} km | {nall} | {get(r,'center','rac','old_late')['pairs']} | {get(r,'center','rac','new_late')['pairs']} | {get(r,'center','rac','old_common')['pairs']} |")
lines+=['','## log RAC：同样2015–2019 cohorts比较','','括号内50 km空间SE；星号为未调整p值（1%、5%、10%）。','','| 半径 | 部分 | 旧匹配ATT | 新匹配ATT | 旧pretrend p | 新pretrend p |','|---|---|---:|---:|---:|---:|']
for r in [3,5,10]:
 for c in ['center','surroundings','cumulative']:lines.append(f"| {r} km | {c} | {fmt(get(r,c,'log_rac','old_late'))} | {fmt(get(r,c,'log_rac','new_late'))} | {pret(r,c,'log_rac','old_late'):.4f} | {pret(r,c,'log_rac','new_late'):.4f} |")
lines+=['','## 主要判断','','- 5 km中心log RAC ATT基本保留：旧0.0162、新0.0164；其−5至−2聚合lead联合检验p由0.0149变为0.6147。周边log RAC由0.0030降到约−0.0002，接近零；累计由0.0050变为0.0029。','- 5 km周边pretrend减弱，但未消失：联合p约0.0163；累计p约0.0530。因此不能宣称长历史匹配已经解决平行趋势问题，也不能因p刚好超过0.05宣布识别成功。','- 5 km新样本的RAC level周边ATT仍为230.5（SE100.1），累计276.6（101.1），与log接近零并不矛盾：level与log反映不同规模加权，较大区域可以主导level。不能只报告log或只报告level来概括全部结果。','- 同样5 km晚cohort样本中，WAC累计level从约−485.8变为−611.3；累计log WAC仍不显著。中心emp/pop的ATT从约0.70pp变为0.66pp，周边从约0.19pp变为0.02pp。完整其他outcome见网页和CSV。','- 3 km与10 km的pretrend没有一致改善。3 km周边log RAC的联合p从0.0853变为0.0007；10 km从0.7050变为0.0065。样本及cohort权重变化、误差相关以及仍未约束的年度路径都可能影响结果；不能把所有改变都归于一个机制。','', '这些诊断使用了匹配已经约束的处理前年份，不是完全独立的外部验证。未根据处理后显著性再调门槛，也未按p值删除cohort。','','## 同一批treated中心的比较','','| 半径 | 部分 | 旧controls ATT | 新controls ATT | 旧pretrend p | 新pretrend p |','|---|---|---:|---:|---:|---:|']
for r in [3,5,10]:
 for c in ['center','surroundings','cumulative']:lines.append(f"| {r} km | {c} | {fmt(get(r,c,'log_rac','old_common'))} | {fmt(get(r,c,'log_rac','new_common'))} | {pret(r,c,'log_rac','old_common'):.4f} | {pret(r,c,'log_rac','new_common'):.4f} |")
lines+=['','5 km共同297个treated中，周边log RAC ATT从0.0017变为0.0002，pretrend联合p从小于0.0001变为0.0230；累计ATT从0.0047变为0.0034，pretrend p从小于0.0001变为0.0693。更换controls改善了部分早期差异，但并未彻底解决。','', '## 住房规模与验证','','新匹配住房规模见matching/housing_scale_summary.csv，按首次placement当年及g至2019累计报告。区域内其他项目继续允许存在。','', '独立从原面板重新计算全部14个关键变量的配对差异，核对不超过1 SD；同时验证同州、真实成员不重叠、control资格及cohort内不复用。全部模型保留预定观测，SA聚合与fixest一致，level ATT满足中心+周边=累计。','', '新结果保存在独立stage_f目录；Stage D的结果不覆盖。本次共252个SA模型，未运行standard DID。网页results.html包含全部outcome、两种样本比较以及14张新旧event-study叠加图。']
(base/'RESULTS_CN.md').write_text('\n'.join(lines)+'\n')
parts=['<!doctype html><meta charset="utf-8"><title>Long pretrend rematching comparison</title><style>body{font:16px system-ui;max-width:1250px;margin:40px auto;padding:0 24px;color:#243348}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{padding:8px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}.note{color:#596b7e;font-size:14px}details{margin:25px 0}h1,h2{color:#173a60}</style><h1>2015–2019 cohorts: expanded pretrend matching</h1><p>Sun–Abraham aggregated ATT and event study only. Original results are preserved. Primary inference: full-time spatial HAC, 50 km.</p><p><b>Main diagnostic:</b> 5 km surrounding log RAC attenuates toward zero; earlier leads improve but still jointly reject zero. Improvement is not uniform at 3/10 km.</p><p><a href="RESULTS_CN.md">中文分析</a> · <a href="../stage_d/results.html">Original full-cohort results</a> · <a href="estimates/att_long.csv">All estimates / bandwidths</a></p>']
for kind,title in [('late','Same cohort range: original versus expanded matching'),('common','Identical treated centers: original versus new controls')]:
 parts.append(f'<h2>{title}</h2>')
 for r in [3,5,10]:
  os,ns='old_'+kind,'new_'+kind;parts.append(f'<details><summary>{r} km tables: {get(r,"center","rac",os)["pairs"]} old / {get(r,"center","rac",ns)["pairs"]} new pairs</summary>')
  for c in ['center','surroundings','cumulative']:
   parts.append(f'<h3>{c}</h3><table><tr><th>Outcome</th><th>Original ATT (SE)</th><th>New ATT (SE)</th><th>Original lead test p</th><th>New lead test p</th></tr>')
   for y,label in labels.items():parts.append(f'<tr><td>{label}</td><td>{fmt(get(r,c,y,os))}</td><td>{fmt(get(r,c,y,ns))}</td><td>{pret(r,c,y,os):.4f}</td><td>{pret(r,c,y,ns):.4f}</td></tr>')
   parts.append(f'<tr><td>Observations</td><td>{get(r,c,"rac",os)["observations"]}</td><td>{get(r,c,"rac",ns)["observations"]}</td><td></td><td></td></tr></table>')
  parts.append('</details>')
 for y in ['log_rac','emp_pop_ratio','rac','log_wac','wac','log_population','population']:
  parts.append(f'<details {"open" if y=="log_rac" else ""}><summary>{labels[y]}: event studies</summary><img src="estimates/comparison_{kind}_{y}.png"></details>')
parts.append('<p class="note">95% pointwise intervals. Lead tests cover aggregated event years −5 to −2. Matching uses these pre-period data, so these tests are not independent validation. No event +5 is observed for 2015–2019 cohorts.</p>')
(base/'results.html').write_text('\n'.join(parts))
oldpaths=[project/'stage_c/matched_pairs.csv',project/'stage_d/att_long.csv',project/'stage_d/event_study.csv',project/'stage_d/results.html']
(base/'original_files_sha256.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in oldpaths},indent=2))

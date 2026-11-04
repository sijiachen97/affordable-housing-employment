# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys,json,hashlib
base=Path(sys.argv[1]);o=base/'estimates';read=lambda p:list(csv.DictReader(p.open()))
a=read(o/'att_long.csv');pre=read(o/'pretrend_tests.csv')
versions={'old_full':'Stage H','new_full':'Same county + isolated surroundings (I)'}
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_population':'Population (log)','population':'Population (level)','log_rac':'Resident-held jobs (log)','rac':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac':'Workplace jobs (level)'}
def get(r,c,y,s):return next(x for x in a if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km')
def pret(r,c,y,s):return float(next(x['p_value'] for x in pre if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km'))
def fmt(x):
 fac=100 if x['outcome']=='emp_pop_ratio' else 1;dec=1 if x['outcome'] in ['rac','wac','population'] else 4;p=float(x['p_value']);st='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*fac:.{dec}f}{st} ({float(x['std_error'])*fac:.{dec}f})"
md=['# 同县匹配与周边无同期新增项目：Stage I','','Stage H作为已有版本保留。本次同时改变两项：匹配限同县；treated的周边成员tract在2010–2019无TYPE=1新建LIHTC placement，且没有未知placement年份记录。历史pre-2010项目允许；中心tract内后续项目允许。范围按固定tract-centroid成员定义，不是实际项目坐标圆形边界；无法定位的项目仍受原数据覆盖限制。','','匹配变量、可用年份、propensity门槛、每变量1 SD门槛、距离排序及control资格同Stage H。propensity和标准化SD按新的合格treated样本重新计算。仍为中心FE+pair×year FE，SA aggregated ATT及event study，50 km空间协方差为主。','','由于排除了整个观察期内周边有项目的地区，本版本描述孤立开发的子样本，不能简单理解为整个Stage H样本的单一项目效应；项目后续布局也可能与中心开发相关。两个改变同时发生，不能把结果差异单独归给同县限制或周边项目排除。','','## 样本流失','','| 半径 | Stage H pairs | 完整且非空周边treated | 再排除周边项目后的候选treated | 最终同县pairs |','|---|---:|---:|---:|---:|']
flow=read(base/'matching/sample_summary.csv')
for r in [3,5,10]:
 x=next(x for x in flow if x['radius_km']==str(r));md.append(f"| {r} km | {get(r,'center','rac','old_full')['pairs']} | {x['with_neighbors']} | {x['isolated_neighbors']} | {x['matched']} |")
md+=['','5 km无2019匹配对；10 km无2012、2016、2018匹配对，16对中10对来自2011。2011只有一个处理前年份，不能检查该cohort的处理前增长。完整匹配流失见matching_status.csv及sample_flow.csv。','','## 解释','','- 严格条件没有自动带来更好平衡：3/5/10 km核心变量平均绝对SMD约0.089/0.115/0.255；部分其他协变量差异更大。','- 3 km中心WAC为−4.7（SE92.6），原Stage H的中心正向显著WAC没有在该子样本复现。不能仅因不显著判定没有效应。','- 5 km累计RAC为425.5（SE204.4），累计log RAC约0.0128（SE0.0066），方向仍正；只有64对且部分中心/周边RAC lead在10%水平拒绝。','- 10 km只有16对，多个cohort只有一对，部分WAC lead严重拒绝。表格和图保留透明性，不将其作为可靠的主要因果证据。','- 当前不能把这版概括为全面验证了Stage H；变化混合样本选择、controls变化和估计精度下降。','','## 核验','','逐一检查同县、周边原始新建项目记录、unknown年份、control资格、成员不重叠、不复用。独立重算全部核心距离。估计保留每对20行，SA聚合与fixest一致，level满足中心+周边=累计。','', 'fixest辅助协方差计算在极小样本中报告3次非半正定修复提示；主结果采用独立计算的PSD空间核score协方差，cluster恒等核检查通过。小样本正态/chi-square推断仍可能不可靠，未做bootstrap或small-sample修正。']
md+=['','10 km 2018 propensity拟合出现概率数值接近0/1提示，该cohort最终无配对；没有更改模型或门槛以强行保留样本。']
parts=['<!doctype html><meta charset="utf-8"><title>Same-county isolated-area comparison</title><style>body{font:16px system-ui;max-width:1300px;margin:40px auto;padding:0 24px;color:#243348}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{padding:8px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}details{margin:24px 0}.warn{padding:18px;background:#fff0d9}.note{font-size:14px;color:#586979}</style><h1>Same-county matching and isolated treated surroundings</h1><p>Stage H matching covariates and calipers; Stage I changes geography to same county and excludes treated surroundings with any 2010–2019 TYPE=1 project or unknown timing. Center subsequent projects and historical neighboring projects remain allowed.</p><p class="warn"><b>Limited overlap:</b> 121 / 64 / 16 pairs at 3 / 5 / 10 km. Several cohorts have no matches; 10 of the 16 pairs at 10 km belong to 2011. Covariate balance remains imperfect. The 10 km estimates and asymptotic p-values are exploratory.</p><p><a href="RESULTS_CN.md">中文说明与样本流失</a> · <a href="../stage_h/results.html">Stage H</a> · <a href="matching/sample_flow.csv">Cohort sample flow</a> · <a href="estimates/att_long.csv">All estimates</a></p>']
for r in [3,5,10]:
 parts.append(f'<details open><summary><b>{r} km: H {get(r,"center","rac","old_full")["pairs"]} / I {get(r,"center","rac","new_full")["pairs"]} pairs</b></summary>')
 for c in ['center','surroundings','cumulative']:
  parts.append(f'<h3>{c}</h3><table><tr><th>Outcome</th><th>Stage H ATT (SE)</th><th>Stage I ATT (SE)</th><th>H lead p</th><th>I lead p</th></tr>')
  for y,label in labels.items():parts.append(f'<tr><td>{label}</td>'+''.join(f'<td>{fmt(get(r,c,y,s))}</td>' for s in versions)+''.join(f'<td>{pret(r,c,y,s):.4f}</td>' for s in versions)+'</tr>')
  parts.append('<tr><td>Observations</td>'+''.join(f'<td>{get(r,c,"rac",s)["observations"]}</td>' for s in versions)+'<td></td><td></td></tr></table>')
 parts.append('</details>')
for y,label in labels.items():parts.append(f'<details open><summary>{label}</summary><img src="estimates/comparison_full_{y}.png"></details>')
parts.append('<p class="note">Center FE + pair × year FE; Sun–Abraham ATT, full-time spatial HAC 50 km. Pointwise 95% intervals, stars at 10/5/1%. Lead tests cover available aggregated years −5 to −2. Samples differ, including retained cohorts. Two design changes are combined; differences cannot be attributed to either alone. Matching-period tests are not independent validation.</p>')
(base/'results.html').write_text('\n'.join(parts));(base/'RESULTS_CN.md').write_text('\n'.join(md)+'\n')
root=Path('./output/research_extensions/23_spatial_spillover')
paths=[root/'stage_h'/f for f in ['results.html','estimates/att_long.csv','matching/matched_pairs.csv']]
(base/'original_files_sha256.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2))

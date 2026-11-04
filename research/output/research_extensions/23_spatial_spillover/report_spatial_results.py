# -*- coding: utf-8 -*-
from pathlib import Path
import csv, html, json, hashlib
base=Path(__file__).parent;out=base/'stage_d'
read=lambda name:list(csv.DictReader((out/name).open()))
a=read('att_long.csv');pr=read('pretrend_tests.csv');es=read('event_study.csv')
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','population':'Population (level)','log_population':'Population (log)','rac':'Resident-held jobs (level)','log_rac':'Resident-held jobs (log)','wac':'Workplace jobs (level)','log_wac':'Workplace jobs (log)'}
order=['emp_pop_ratio','log_population','population','log_rac','rac','log_wac','wac']
def row(r,y,c,est='sun_abraham',sample='radius_specific',cov='spatial_50km'):
 return next(x for x in a if x['radius_km']==str(r) and x['outcome']==y and x['component']==c and x['estimator']==est and x['sample']==sample and x['covariance']==cov)
def cell(x):
 factor=100 if x['outcome']=='emp_pop_ratio' else 1
 dec=1 if x['outcome'] in ['rac','wac','population'] else 3
 p=float(x['p_value']);stars='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*factor:.{dec}f}{stars} ({float(x['std_error'])*factor:.{dec}f})"
lines=['# 区域分析：标准DID、Sun–Abraham ATT与event study','', '使用已确定的同州匹配、1 SD关键变量门槛配对，不重新匹配。3、5、10 km分别为1,043、1,014、733对。所有outcome使用同一组pair及2010–2019观测，分别估计中心、周边（不含中心）、累计区域。论文未修改。','', '## 标准误怎样处理','','采用全时间空间HAC：先把同一原始中心的所有年份与重复cohort的回归影响贡献加总，再按中心之间的距离计算协方差。这样既保留同一中心的跨年相关，也纳入不同附近中心在不同年份的相关。controls跨cohort重复使用不会被当成独立样本。','', '主结果预先选定50 km空间带宽，另报25、100 km；带宽不是outcome半径，也不改变matching或ATT点估计。三个带宽都大于最大分析区域直径20 km。使用Wendland正半定距离核，避免对负特征值事后修补。只按原始中心聚类作为比较，不作为主推断。','', '这仍是空间相关随距离减弱的近似推断，而不是知道所有共享tract的真实误差协方差。区间为渐近正态点置信区间，无小样本自由度修正，条件于固定matching；未把重新估计倾向得分和匹配选择的不确定性全部计入。对超过100 km的经济冲击也不能保证充分覆盖。','', '## 两种估计量','','标准DID回归：outcome = 原始中心FE + pair×year FE + treated×post。该系数在恒定处理效应设定下可解释为ATT，存在动态或异质效应时应视为标准DID汇总系数，不能与Sun–Abraham加权ATT混同。','', 'Sun–Abraham使用与论文一致的cohort×event-time交互、中心FE和pair×year FE，参考期−1并按论文同时省略最早lead。汇总ATT覆盖全部可观察的post-treatment horizons，图展示−5至+5。controls的cohort编码9999，never-treated未被遗漏。','', '## 汇总ATT（50 km空间标准误）','']
for r in [3,5,10]:
 lines += [f'### {r} km','', '| Outcome | 中心 | 周边 | 累计区域 |','|---|---:|---:|---:|']
 for y in order:lines.append('| '+labels[y]+' | '+' | '.join(cell(row(r,y,c)) for c in ['center','surroundings','cumulative'])+' |')
 x=row(r,'rac','center');lines+=['',f"Pairs: {x['pairs']}; observations per regression: {x['observations']}. 括号内为空间标准误；*** p<0.01、** p<0.05、* p<0.10。",'']
lines+=['## 主要结果与解释','','1. 中心RAC的ATT在3/5/10 km样本分别为约64、74、68个岗位，log RAC约0.029、0.032、0.025。三个样本的中心结果都为正。','2. 3/5 km周边RAC level也为正，累计ATT约288、669个岗位。点估计没有呈现中心增加、周边等量减少的简单抵消模式。但这不是个人迁移检验，也不是全国净就业创造的证据。区域可以重叠，不能把不同中心的区域总量相加当作全国总量。','3. 10 km累计RAC level为正，但累计log RAC只有约0.0043，p约0.081；周边log RAC接近零。这提示level结果可能较受较大区域影响，不能简单说效应随半径增加。','4. 中心WAC log约0.029–0.031，三个样本均为正且50 km推断下p<0.05；累计区域WAC log均不显著。因此没有一致证据表明区域内工作地岗位整体增加。','5. 标准DID与Sun–Abraham汇总不是同一权重；例如3 km中心WAC level的标准DID约11.8、Sun–Abraham约75.4。两者均完整保留，不能选显著的一种作为结论。','','## 处理前轨迹是当前主要限制','','匹配变量平衡不等于整个处理前窗口平行。50 km空间推断下，对−5至−2四个聚合lead作联合检验：','', '| 半径 | 中心log RAC | 周边log RAC | 累计log RAC |','|---|---:|---:|---:|']
for r in [3,5,10]:
 vals=[]
 for c in ['center','surroundings','cumulative']:
  x=next(x for x in pr if x['sample']=='radius_specific' and x['radius_km']==str(r) and x['component']==c and x['outcome']=='log_rac' and x['covariance']=='spatial_50km')
  vals.append(f"{float(x['p_value']):.4f}")
 lines.append(f'| {r} km | '+' | '.join(vals)+' |')
lines+=['', '3 km中心和5 km周边/累计log RAC的处理前系数存在明显偏离。5 km周边图显示处理前已经上升，后续增长不宜全归因于LIHTC。3 km累计log RAC未拒绝lead联合为零，但level RAC拒绝；不能只挑某一指标的检验。以上是聚合lead检验，不是每个cohort-specific lead的联合检验，未拒绝也不等于证明平行趋势。','','## 空间标准误敏感性','','以累计RAC的Sun–Abraham ATT为例：','', '| 半径 | 仅中心聚类SE | 25 km SE | 50 km SE | 100 km SE |','|---|---:|---:|---:|---:|']
for r in [3,5,10]:lines.append(f'| {r} km | '+' | '.join(f"{float(row(r,'rac','cumulative',cov=c)['std_error']):.2f}" for c in ['center_cluster','spatial_25km','spatial_50km','spatial_100km'])+' |')
lines+=['', '例如5 km的标准误由仅中心聚类的77增至50 km的132、100 km的173，说明区域相关性不能忽略。该level ATT在三个空间带宽下仍为正且显著，但空间修正不会修复处理前趋势差异。','','## 共同treated样本','','额外在3/5 km共同保留的754个treated中心上复算全部结果，沿用各自原有control。累计RAC ATT分别约210和856；仍不能解释为纯粹的半径效应，因为controls及周边构成不同，而且前趋势问题仍需审阅。完整输出sample=common_3_5。','','## 数据与实现核对','','- 210个模型全部完成，所有模型使用固定配对，没有因某个outcome改变样本。','- 自定义ATT与fixest的Sun–Abraham聚合结果一致。','- 同一影响函数实现退化为中心聚类时，与fixest无小样本修正的聚类协方差一致。','- RAC、WAC、人口level的中心ATT＋周边ATT＝累计ATT，数值误差小于1e−5。标准误不能相加；log及比率也没有这种加性。','- 保留原始never/future controls审计；未将未知年份中心误作never-treated。','','文件：`att_long.csv`（全部标准误版本）、`did_wide.csv`（两种估计主表）、`event_study.csv`、`pretrend_tests.csv`、`estimation_audit.csv`、7张event-study图。`results.html`可直接查看完整表格及图。','','方法参考：[空间面板HAC](https://bura.brunel.ac.uk/bitstream/2438/7746/2/Fulltext.pdf)、[Wendland核说明](https://rpkgs.github.io/fields/reference/Wendland.html)。']
(out/'RESULTS_CN.md').write_text('\n'.join(lines)+'\n')
# Standalone local viewer; all figure paths relative to this output folder.
parts=['<!doctype html><meta charset="utf-8"><title>Spatial-region estimates</title><style>body{font:16px system-ui;max-width:1250px;margin:40px auto;padding:0 24px;color:#243348}h1,h2{color:#173a60}table{border-collapse:collapse;width:100%;margin:20px 0 35px}th,td{padding:9px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}.note{color:#596b7e;font-size:14px}nav a{margin-right:18px}</style><h1>Matched spatial-region results</h1><p>Fixed same-state pairs; center, surroundings and cumulative area. Main intervals: full-time spatial HAC, 50 km.</p><p><b>Interpretation:</b> positive RAC estimates do not establish net job creation. Several pre-treatment lead tests reject zero; review the event studies alongside the tables.</p><nav><a href="RESULTS_CN.md">Chinese analysis</a><a href="att_long.csv">All estimates and bandwidths</a><a href="pretrend_tests.csv">Pre-treatment tests</a></nav>']
for r in [3,5,10]:
 parts.append(f'<h2>{r} km: {row(r,"rac","center")["pairs"]} pairs</h2>')
 for est,title in [('sun_abraham','Sun–Abraham aggregated ATT'),('standard_did','Standard DID post coefficient')]:
  parts.append(f'<h3>{title}</h3><table><tr><th>Outcome</th><th>Center</th><th>Surroundings</th><th>Cumulative</th></tr>')
  for y in order:parts.append('<tr><td>'+labels[y]+'</td>'+''.join('<td>'+cell(row(r,y,c,est))+'</td>' for c in ['center','surroundings','cumulative'])+'</tr>')
  parts.append(f'<tr><td>Observations</td><td colspan="3">{row(r,"rac","center")["observations"]} per regression</td></tr></table>')
 parts.append('<p class="note">Standard errors in parentheses. *** p&lt;.01, ** p&lt;.05, * p&lt;.10. Center FE and pair × year FE. Normal asymptotic inference, conditional on matching; no finite-sample correction.</p>')
for y in order:parts.append(f'<h2>{labels[y]}</h2><img src="eventstudy_{y}.png">')
(out/'results.html').write_text('\n'.join(parts))
(out/'input_hashes.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path('./output/research_extensions/23_spatial_spillover/stage_c/matched_pairs.csv'),base/'estimate_spatial_regions.R']},indent=2))
hpath=Path('./output/research_extensions/23_spatial_spillover/stage_c/housing_scale_summary.csv')
h=[x for x in csv.DictReader(hpath.open()) if x['core_caliper']=='1']
with (out/'housing_scale_summary.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=list(h[0]));w.writeheader();w.writerows(h)
with (out/'RESULTS_CN.md').open('a') as f:
 f.write('\n## 对应区域的LIHTC规模\n\n| 半径 | 首年平均项目数 | 首年平均total units | g至2019平均项目数 | 同期平均total units |\n|---|---:|---:|---:|---:|\n')
 for r in ['3','5','10']:
  s=next(x for x in h if x['radius_km']==r and x['period']=='first_year');e=next(x for x in h if x['radius_km']==r and x['period']=='through_2019')
  f.write(f"| {r} km | {float(s['mean_projects']):.2f} | {float(s['mean_units']):.1f} | {float(e['mean_projects']):.2f} | {float(e['mean_units']):.1f} |\n")
 f.write('\n住房规模覆盖区域内全部新建项目，units均值使用单位数完整的区域；累计期长度因cohort不同，不是ATT加权规模。允许treated周边其他项目意味着区域效应包含共同开发环境，不能全部归因于中心的某一个项目。\n')

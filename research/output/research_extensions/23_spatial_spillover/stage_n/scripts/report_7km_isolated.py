# -*- coding: utf-8 -*-
from pathlib import Path
import csv,json,hashlib,html,sys
p=Path(sys.argv[1]);root=Path('./output/research_extensions/23_spatial_spillover')
read=lambda f:list(csv.DictReader((p/f).open()))
a=read('combined_att_long.csv');pr=read('combined_pretrend_tests.csv')
methods='''本版只分析周边无新增项目组，3、5 km原样复用L；7 km重新构造区域、按H规则匹配，再筛选孤立treated并保留原control。10 km结果保留，没有覆盖。采用组内原生Sun–Abraham ATT权重，与L一致；不采用M中为了两组比较构建的共同权重。各半径的配对样本不同，不能把半径间的差额解释为新增距离环带的效应。

区域定义：center为整个中心tract；surroundings为其他质心距中心质心不超过r km的完整tract；cumulative为二者之和。不是把tract切割为圆形，也不是per-tract平均。RAC level为区域内所有居民持有岗位数之和，不是唯一就业人数。

Treated资格：中心首次已知新建LIHTC placement在2011–2019年，2010年用于处理前基准；排除2010年及更早处理的中心和无法确定首次placement的328个tract。区域内RAC、WAC、population十年数据完整、有至少一个周边tract、处理前匹配变量可用。先允许treated周边有其他项目完成H匹配，然后只保留其他成员tract在2010–2019年没有新建LIHTC placement且没有未知年份项目记录的treated。周边2010年前的历史项目、中心后续项目均允许；不是附近从未存在LIHTC。

Control资格：中心从未处理或首次placement在2019年之后；整个control区域数据完整且2010–2019年无新建项目、无未知placement年份。除成员tract项目记录，还按实际项目坐标额外排除半径内的新建或未知年份项目。包含never-treated，且比论文旧有的仅在cohort当年尚未处理规则更严格。treated的孤立筛选按成员tract定义，control另有实际坐标安全筛选。

配对约束：同州，不要求同县；两个中心距离大于2r，且两个区域不共享成员tract。每cohort按treated倾向得分从高到低贪婪1:1匹配，同cohort control不重复，不同cohort可重复。logistic propensity在每个半径、cohort的合格样本中估计，概率差不超过两组组内合并标准差的0.2倍。核心变量每项差异不超过合格treated的1个标准差；通过后最小化核心标准化差平方均值加0.25倍其他变量标准化差平方均值。不是只按propensity最近邻。

匹配变量分别对中心和周边构造：g−1的log人口、log RAC、log WAC；种族和年龄构成；RAC/WAC低、高工资占比；人口或就业为零的指标。核心变量还包括人口、RAC、WAC的log增长率及RAC/WAC绝对年均增量：2011 cohort只有水平，2012使用2010–2011变化，2013起使用g−3至g−1年均变化，2015起再加入g−5至g−3的早期变化。所有预测变量均早于placement，没有按本次ATT结果调整阈值。

估计：2010–2019完整面板，Sun–Abraham cohort×event估计，中心tract FE及pair×year FE，参照期沿用原代码c(-1,.F)。ATT汇总所有可观察处理后时期，event study展示−5至+5；不另外报告standard TWFE DID。主表使用按原中心聚合全期得分的50 km空间HAC，另存25/100 km及中心聚类结果。

7 km样本：原候选treated 2,618；区域数据完整2,056；有周边且匹配变量可用1,817；H规则匹配593对；随后筛选无周边新增项目剩245对，4,900行观测。3、5 km分别396、306对。原配对保留、never-treated保留、地理不重叠和距离约束、协方差复核及level可加性检查均通过。'''
md=['# 无周边新增项目：3、5、7 km',methods,'## RAC level ATT','单位为jobs；括号为空间标准误。所有估计都使用该无项目组的原生汇总权重。','|半径|区域|ATT (SE)|95% CI|Lead联合p|','|---|---|---:|---:|---:|'];rows=[]
for r in ['3','5','7']:
 for c in ['center','surroundings','cumulative']:
  x=next(x for x in a if x['radius_km']==r and x['component']==c and x['outcome']=='rac' and x['covariance']=='spatial_50km');q=next(x for x in pr if x['radius_km']==r and x['component']==c and x['outcome']=='rac' and x['covariance']=='spatial_50km');row=[r,c,f"{float(x['estimate']):.1f} ({float(x['std_error']):.1f})",f"[{float(x['ci_low']):.1f}, {float(x['ci_high']):.1f}]",f"{float(q['p_value']):.4f}"];rows.append(row);md.append('| '+' | '.join(row)+' |')
interpret='''3、5 km中，中心RAC增长显著，周边点估计为正但不精确，累计RAC增长显著。因此，在无周边新增项目样本中，没有出现中心增加被区域内部周边下降完全抵消的平均模式。这比只看周边不显著更能回应“纯区域内部重新分布”的解释，但不是个人迁移追踪，也不能排除一部分搬迁或来自半径之外的迁入。

7 km中心约增加67 jobs，周边约−99、累计约−32，后两者不显著；周边95%区间约[−297,99]，处理前联合p约0.049。因而不能称7 km证明周边没有下降，也不能排除区域内部重新分布。应完整保留这个敏感性结果。各半径的treated/control不同，3、5、7 km的变化同时含有样本组成变化。'''
md+=['## 解释',interpret];(p/'RESULTS_CN.md').write_text('\n\n'.join(md))
parts=['<!doctype html><meta charset="utf-8"><title>No surrounding projects: 3, 5, 7 km</title><style>body{font:17px system-ui;color:#23354a;max-width:1400px;margin:40px auto;padding:0 24px;line-height:1.6}table{border-collapse:collapse;width:100%}td,th{padding:10px;border-bottom:1px solid #ccc;text-align:right}img{width:100%}summary{font-weight:bold;cursor:pointer}</style><h1>No additional surrounding projects: 3, 5, 7 km</h1>']
parts+=['<p>'+html.escape(x)+'</p>' for x in interpret.split('\n\n')];parts+=['<h2>RAC level ATT</h2><table><tr>'+''.join('<th>'+x+'</th>' for x in ['Radius (km)','Component','ATT (SE)','95% CI','Lead test p'])+'</tr>'];parts+=['<tr>'+''.join('<td>'+html.escape(v)+'</td>' for v in row)+'</tr>' for row in rows];parts+=['</table><p>Native within-group Sun–Abraham weights; 50 km spatial HAC. Original L estimates at 3/5 km; newly matched 7 km areas followed by isolation filter.</p>','<img src="eventstudy_rac.png"><details><summary>Eligibility, matching, and estimation audit</summary>'];parts+=['<p>'+html.escape(x)+'</p>' for x in methods.split('\n\n')];parts+=['</details>']
for y in ['log_rac','population','wac','log_population','log_wac','emp_pop_ratio']:parts.append(f'<details><summary>{y}</summary><img src="eventstudy_{y}.png"></details>')
(p/'results.html').write_text('\n'.join(parts))
(p/'original_results_sha256.json').write_text(json.dumps({str(root/s/'estimates/att_long.csv'):hashlib.sha256((root/s/'estimates/att_long.csv').read_bytes()).hexdigest() for s in ['stage_h','stage_l','stage_m']},indent=2))

# -*- coding: utf-8 -*-
from pathlib import Path
import csv
base=Path(__file__).parent
read=lambda p:list(csv.DictReader(p.open()))
first=base/'stage_b';second=base/'stage_b_mahalanobis'
flow=read(second/'sample_summary.csv');b1=read(first/'balance_quality_summary.csv');b2=read(second/'balance_quality_summary.csv')
lines=['# 区域匹配：同县与同州跨县的实际结果','', '本轮完成实际匹配、匹配平衡检查和住房规模描述。没有运行 DID 或修改论文。','', '## 匹配后保留的 treated 中心','', '| 半径 | 同县 | 同州跨县 | 同州相对同县增加 |','|---|---:|---:|---:|']
for r in ['3','5','10']:
 c=int(next(x['matched'] for x in flow if x['radius_km']==r and x['scope']=='county'));s=int(next(x['matched'] for x in flow if x['radius_km']==r and x['scope']=='state'))
 lines.append(f'| {r} km | {c:,} | {s:,} | {s-c:,}（{100*(s/c-1):.1f}%） |')
lines+=['','## 匹配方法与时间口径','','- 中心首次新建 LIHTC placement 为2011–2019。保留 never-treated controls；中心2010年及此前已处理的tract不进入候选中心。周边成员可以是此前已处理的tract。','- Controls 中心未在2010–2019接受新建项目，整个区域无该期间新增项目、无未知年份项目。同时使用项目所在tract的质心和可用实际项目坐标筛查；无法定位且没有有效tract的记录仍是数据限制。','- Treated 周边允许其他项目，未知年份周边项目保留并标记。区域与中心处理时点并不一定相同，后续估计需解释为围绕中心首次placement的区域变化。','- 两个区域内的每个成员都需具有完整十年RAC、WAC、population。缺失不补零。treated/control中心距离超过两倍半径，并独立检查实际成员集合不重叠。','- Cohort g 的所有匹配变量取 g−1。中心与区域各纳入log人口、log RAC、log WAC，黑人、AIAN、API、Hispanic人口份额，0–24岁和55岁以上份额，RAC/WAC低工资和高工资份额。区域份额用人口或岗位总数相除，不是tract份额的简单平均。源字段under_29实际对应0–24岁，沿用数值但明确标签。','- 2012 cohort 的RAC/WAC增长为2010至2011变化；2013 onward使用g−3至g−1年均log变化。2011只有2010基期，不添加增长变量。','- 每个半径、cohort用logit估计倾向得分；同县与同州比较使用同一个得分模型。县/州限制用于候选配对，模型本身没有县/州固定效应。','- 1:1匹配，cohort内无放回，按treated倾向得分从高到低依次匹配；允许controls跨cohort复用。门槛为0.2倍处理/对照组倾向得分的组内合并标准差。','- 第一轮在门槛内选倾向得分最近control；改进轮在同一门槛内选择协变量Mahalanobis距离最小control。协方差来自处理/对照合并组内协方差，特征标准化后将特征值下限固定为最大特征值的1%，避免中心与区域变量高度相关导致数值不稳定。','- 改进规则只依据处理前变量和平衡诊断，没有查看处理后估计结果来选匹配。','','## 平衡诊断','','下表为各cohort、变量的绝对标准化均值差（SMD）按匹配数量加权后的平均。标准化分母固定为该cohort匹配前treated变量标准差；0.1只是常用诊断参考，不能证明平行趋势。','','| 半径 | 范围 | 第一轮平均绝对SMD | 改进轮平均绝对SMD | 改进轮最大绝对SMD |','|---|---|---:|---:|---:|']
for x in b2:
 old=next(t for t in b1 if t['radius_km']==x['radius_km'] and t['scope']==x['scope'])
 lines.append(f"| {x['radius_km']} km | {'同县' if x['scope']=='county' else '同州'} | {float(old['mean_absolute_smd']):.3f} | {float(x['mean_absolute_smd']):.3f} | {float(x['max_absolute_smd']):.3f} |")
lines+=['','必须同时查看balance_by_cohort.csv，不能用跨cohort正负差异相互抵消来判断平衡。balance_summary.csv另有平均绝对差异。Before比较的是该半径/cohort完整的treated与全国合格controls池；After为实际匹配对。Before并非精确地理分层加权的反事实对照。','','## 区域住房规模（同州匹配）','','| 半径 | 首次placement当年平均项目数 | 当年平均total units | placement至2019平均项目数 | 同期平均total units |','|---|---:|---:|---:|---:|']
h=read(second/'housing_scale_summary.csv')
for r in ['3','5','10']:
 f=next(x for x in h if x['radius_km']==r and x['scope']=='state' and x['period']=='first_year');e=next(x for x in h if x['radius_km']==r and x['scope']=='state' and x['period']=='through_2019')
 lines.append(f"| {r} km | {float(f['mean_projects']):.2f} | {float(f['mean_total_units_complete']):.1f} | {float(e['mean_projects']):.2f} | {float(e['mean_total_units_complete']):.1f} |")
lines+=['','上述项目/units覆盖固定区域所有成员tract中的新建LIHTC项目，包括中心与周边；年份以中心的g为起点。Units均值使用项目units完整的区域，缺失数量单列，未补零。累计到2019的观察长度因cohort而异，不是ATT加权规模。半径间匹配样本不同，不能把三个均值直接当成同一批中心向外扩张的增量。','','## 估计前还需要处理','','1. 审查各cohort核心就业水平与增长的剩余不平衡，再确定匹配方案。2. 使用相同匹配对分别分析中心、周边和累计区域，level总和可作加性核对；跨半径比较需另报共同treated样本。3. 区域可能互相重叠，且controls跨cohort复用，不能直接照搬论文的tract聚类标准误；估计须加入能覆盖空间和跨期相关的推断。4. treated附近此前已存在的项目意味着中心g不是整个区域首次受影响时间，结果不能解释为单一项目的孤立效应。','','文件：matched_pairs.csv为配对；sample_flow.csv为cohort样本流失；matching_failure_summary.csv为失败原因；matched_control_timing.csv核对never-treated；INDEPENDENT_VALIDATION.txt记录独立检查。']
(second/'RESULTS_CN.md').write_text('\n'.join(lines)+'\n')
p=second/'RESULTS_CN.md'
s=p.read_text().replace('改进轮','协变量距离轮').replace('改进规则','该规则')
s += '\n## 诊断结论\n\n同州跨县明显改善保留样本数，但不能据此认定匹配已经足够平衡。协变量距离轮没有整体优于第一轮，因此不将其自动替代第一轮。第一轮同州在3、5、10 km保留2,181、1,940、1,387个treated中心，同县为1,711、1,336、627。\n\n第一轮同州在10 km下，2019 cohort区域RAC预增长绝对SMD约0.443，2014 cohort区域log WAC约0.355。3/5 km也有关键变量超过0.1。下一阶段应先处理剩余平衡和共同支撑，不能把未通过诊断的样本直接用于因果结论。\n'
p.write_text(s)

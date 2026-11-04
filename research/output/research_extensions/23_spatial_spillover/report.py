# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys,hashlib
p=Path(sys.argv[1]);read=lambda f:list(csv.DictReader((p/f).open()))
c=read('candidate_summary.csv');q=read('original_pair_summary.csv');reg=read('region_summary.csv');area=read('tract_area_summary.csv');geo=read('project_geography_audit.csv')
s=['# 空间扩展：阶段 A 可行性诊断','', '日期：2026-10-23。只检查地理范围、处理暴露、原始匹配和候选对照。尚未匹配新样本、估计 DID 或修改论文。','', '## 数据与口径','', '复用并重新运行原分析的处理核验：2,618 个 2011–2019 首次新建 treated tracts；58,087 never-treated；817 个面板结束后首次处理 tracts；排除 328 个无已知首次年份的未知状态 tracts。原 pooled 匹配为 2,153 对。', '', '所有区域按 2010 tract 几何中心之间的球面距离定义，包含中心和跨县、跨州邻居。周边成员来自完整坐标库，不按处理资格筛掉早期处理地区。新增项目暴露包含所有有有效 tract 编码的新建记录，不能仅查看各 tract 的首次项目。项目真实坐标已经审计，但本轮项目暴露同样按所属 tract 中心定位，因此这些是几何近似诊断，不是精确项目缓冲区。', '', '两套候选暴露窗口都在查看因果结果前设置：full_panel = 2010–2019；cohort_window = max(2010,g−1) 至 min(2019,g+5)。后者允许更早历史项目和窗口后处理，并非要求永久 never-treated。候选中心要求自身首次处理在窗口结束之后或 never-treated，周边窗口内无新项目，并排除周边含任何未知年份项目的候选区域。早期已处理中心不进入候选池，但历史项目可以存在于其他周边 tracts。', '', '候选中心限同县，距离 treated 中心 >2r 是保证质心区域不重叠的充分条件（保守地也排除部分没有实际共享 tract 的较近中心）。原匹配的重叠则直接用共同成员计算。未加入更外层缓冲带，所以无圈内新项目不等于完全没有外溢暴露。候选可重复使用；存在一个候选并不保证通过匹配、共同支持、平衡或不放回分配。', '', '## 原匹配对','', '| 半径 km | 窗口 | 区域重叠的匹配对 | 对照区域有新增项目 | 无暴露、无未知年份且不重叠 | 同时有完整区域结果 |','|---|---|---:|---:|---:|---:|']
for x in q:s.append('| '+' | '.join(x[k] for k in ['radius_km','window','overlap','exposed_controls','unexposed_nonoverlap','complete_unexposed_nonoverlap'])+' |')
s += ['','所有数量以 2,153 对为分母。暴露指标包括 control 自身后来处理以及邻近项目；不是已经证明存在经济 spillover。','','## 同县新候选：按 treated 中心计数','','| 半径 km | 窗口 | 至少一个无暴露候选 | 加不重叠条件 | 两侧区域结果完整 | 再排除 treated 区域未知年份 | 再排除 treated 周边其他 tract 的窗口内项目 |','|---|---|---:|---:|---:|---:|---:|']
for x in c:s.append('| '+' | '.join(x[k] for k in ['radius_km','window','clean_available','disjoint_available','both_complete_available','both_complete_no_unknown','isolated_other_tract_available'])+' |')
s += ['','所有数量以 2,618 个 treated 中心为分母。最后一列仅排除其他 tract 的项目，尚未排除中心本身同年多个项目及后续追加建设，不等于孤立单项目样本。','','## 区域覆盖与 tract 尺寸','','| 半径 km | treated 区域平均 tract 数 | 中位数 | 只有中心的区域数 | 区域所有成员三项结果均完整 |','|---|---:|---:|---:|---:|']
for x in reg:
 if x['timing']=='treated_2011_2019':s.append('| '+' | '.join(x[k] for k in ['radius_km','mean_tracts','median_tracts','center_only','complete_regions'])+' |')
s += ['','完整结果定义：区域每一个成员 tract 都在现有面板中有 2010–2019 十年，RAC、WAC、SEER population 均非缺失。任何缺失均不设为零。完整样本限制可能过严，后续应追查缺失来源，而不是据此直接删除。','','| 中心类型 | 土地面积均值 km² | 中位数 | 90分位 |','|---|---:|---:|---:|']
for x in area:s.append('| '+' | '.join(x[k] for k in ['timing','mean','median','p90'])+' |')
if (p/'treated_region_overlap.csv').exists():
 s += ['','## treated 区域之间的相关性','','| 半径 km | 重叠中心对 | 涉及中心数 | 跨县重叠中心对 |','|---|---:|---:|---:|']
 for x in read('treated_region_overlap.csv'):s.append('| '+' | '.join(x[k] for k in ['radius_km','overlapping_pairs','centers_with_overlap','cross_county_pairs'])+' |')
s += ['','## 如何使用这些结果','','这些数字用于决定下一阶段的空间规则，不是效应估计。应先解决区域结果覆盖，再评估 3/5 km 同县候选的处理前平衡。10 km 是否可用要结合样本变化决定。对中心及累计结果使用同一匹配对象时，中心和区域都必须检查平衡。未知项目年份、中心追加项目、圈外项目以及项目实际坐标仍需在最终设计中处理。', '', '详细核验见 VALIDATION.txt；按 cohort 的保留数见 candidate_summary_by_cohort.csv；各中心候选数见 candidate_counts_by_treated.csv。']
(p/'RESULTS_CN.md').write_text('\n'.join(s))

# -*- coding: utf-8 -*-
from pathlib import Path
import csv,hashlib,json,sys
p=Path(sys.argv[1]);f=p/'RESULTS_CN.md'
s=f.read_text()
s+='''

## 实际项目坐标复核与缺口

原始新建记录有 1,883 条不满足既有有效 2010 tract 编码规则，其中 156 条 placement 在 2010–2019：46 条有可用坐标，110 条没有可用坐标。主候选表只使用有效 tract 编码记录，不能被解释为最终无暴露名单。补充检查使用全部有坐标的 2010–2019 新建项目，核对原 2,153 个 control：

| 半径 km | 实际项目坐标显示有暴露 | tract 中心近似显示有暴露 | 两种定位的暴露分类不同 |
|---|---:|---:|---:|
'''
for x in csv.DictReader((p/'actual_project_coordinate_summary.csv').open()):
 s+='| '+' | '.join(x[k] for k in ['radius_km','exposed_actual','exposed_tract_centroid','classification_differs'])+' |\n'
s+='''
下一阶段应优先使用实际项目坐标筛选项目暴露，区域 outcome 仍按固定 tract 成员加总，两种几何概念需要明确区分。110 条无坐标且无有效 tract 编码的新建记录需要通过地址或其他地理信息核对。未知 placement 年份的项目也不能视为无暴露。

## 阶段 A 判断与下一步

1. 3 km 和 5 km 可以继续评估匹配，原有匹配不宜直接用于累计区域分析。
2. 全期窗口下，3/5/10 km 有同县无已知新增项目、无未知年份项目、距离大于两倍半径且两侧 outcome 完整候选的 treated 中心为 2,311/2,102/1,529 个。再排除 treated 区域未知年份项目后为 2,186/1,932/1,360。这些是匹配前上限，不是最终可用样本。
3. 若进一步要求 treated 周边其他 tracts 全期无新增项目，仅剩 1,367/950/431 个中心有候选。此项限制对代表性有重要影响。
4. 跨县重叠明显：10 km 有 10,639 对 treated 中心跨县共享成员。县级聚类不能完整覆盖机械重叠。
5. 下一阶段先核对暴露定位和结果覆盖缺口，再锁定主窗口、其他项目规则、3/5 km共同样本与匹配变量。尚未进行 DID，不依据处理后结果选择设计。
'''
f.write_text(s)
root=Path('.')
files=['scripts/event_study_analysis/research_extensions/00_common.R','data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv','data_raw/LODES/OD_related/cache/tract2010_points_from_shapefile.parquet','output/robustness_specs/event_study/spec_a_county_trajectory_matching/matched_pairs.csv']
a={k:hashlib.sha256((root/k).read_bytes()).hexdigest() for k in files}
(p/'input_hashes.json').write_text(json.dumps(a,indent=2))

# -*- coding: utf-8 -*-
from pathlib import Path
import csv,sys,math,json,hashlib
base=Path(sys.argv[1]);o=base/'estimates';read=lambda p:list(csv.DictReader(p.open()))
a=read(o/'att_long.csv');pre=read(o/'pretrend_tests.csv');es=read(o/'event_study.csv');summary=read(o/'common_sample_summary.csv')
samples={'h_full':'H full','old_common':'Common: H controls','new_common':'Common: J controls','j_full':'J full'}
labels={'emp_pop_ratio':'Employment-to-population ratio (pp)','log_population':'Population (log)','population':'Population (level)','log_rac':'Resident-held jobs (log)','rac':'Resident-held jobs (level)','log_wac':'Workplace jobs (log)','wac':'Workplace jobs (level)'}
def get(data,r,c,y,s):return next(x for x in data if x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['sample']==s and x['covariance']=='spatial_50km')
def fmt(x):
 f=100 if x['outcome']=='emp_pop_ratio' else 1;d=1 if x['outcome'] in ['rac','wac','population'] else 4;p=float(x['p_value']);st='***' if p<.01 else '**' if p<.05 else '*' if p<.1 else ''
 return f"{float(x['estimate'])*f:.{d}f}{st} ({float(x['std_error'])*f:.{d}f})"
metrics=[]
for r in [3,5,10]:
 for c in ['center','surroundings','cumulative']:
  for y in labels:
   for s in samples:
    v=[float(x['estimate']) for x in es if x['sample']==s and x['radius_km']==str(r) and x['component']==c and x['outcome']==y and x['covariance']=='spatial_50km' and -5<=float(x['event'])<=-2]
    metrics.append(dict(radius_km=r,component=c,outcome=y,sample=s,lead_rms=math.sqrt(sum(z*z for z in v)/len(v)),max_abs_lead=max(map(abs,v)),joint_p=get(pre,r,c,y,s)['p_value']))
with (o/'lead_magnitude_diagnostics.csv').open('w') as f:w=csv.DictWriter(f,fieldnames=metrics[0].keys());w.writeheader();w.writerows(metrics)
md=['# H/J共同treated固定样本对照','','不重新匹配。每个半径选取H与J共同treated，保持原cohort，分别使用原H controls和原J controls。FE、SA参考期、时间窗和空间标准误保持原设置。126个新SA模型，所有结果保留。','','四列依次为H全样本、共同treated+H controls、共同treated+J controls、J全样本。第一到第二列是H样本筛选/权重构成变化；第二到第三列是同一treated样本更换controls；第三到第四列反映J额外保留中心的构成差异。估计值差异可加，但p值不能这样分解。','','| 半径 | 共同treated | 同一个control | 换了control |','|---|---:|---:|---:|']
for x in summary:md.append(f"| {x['radius_km']} km | {x['common_treated']} | {x['same_control']} | {x['changed_control']} |")
md+=['','## 主要发现','','- 3 km中心log WAC：H全样本四个lead的RMS为0.0049，筛到共同treated后为0.0090，换成J controls后为0.0236。联合p依次0.534、0.330、0.010。此处更换controls是较大的变化来源，但样本筛选也有贡献。','- 5 km中心log WAC：RMS为0.0043→0.0158→0.0298，联合p为0.371→0.025→0.001。样本筛选与controls变化均重要。','- 5 km中心log RAC：RMS为0.0042→0.0034→0.0161，联合p为0.513→0.791→0.055。共同样本保留H controls时较平，换J controls后才明显偏离，主要指向controls变化。','- 10 km不能推广上述结论：累计log RAC在共同样本更换J controls后RMS从0.0064降到0.0044，p从0.003升到0.366；J全样本RMS为0.0084，p为0.004。这里J额外保留的中心及其权重改变很重要，换controls并非总是变差。','','这些是顺序性的描述分解，不是设计变更的因果效应，也未对H/J估计差值做跨模型联合显著性检验。RMS仅衡量−5至−2系数偏离零的大小，不是正式检验。共同样本的两列具有相同treated/cohort组成，但controls地理位置和协方差也改变。','', '结果不支持直接丢掉J，因为隔离周边项目仍有研究含义；也不能只因H controls图更平就挑选。当前更准确的结论是重新匹配并未总改善比较组，且影响因半径/outcome不同。','','## 核验','','逐半径验证共同样本treated、cohort与原配对完全对应；每对20个预定观测保留；SA聚合等于fixest；空间核恒等时等于中心cluster；level ATT满足可加性。四组点估计分解恒等式通过。fixest辅助协方差有4次数值半正定修复提示，独立空间核协方差与cluster恒等检查均通过。']
parts=['<!doctype html><meta charset="utf-8"><title>H/J fixed treated comparison</title><style>body{font:16px system-ui;max-width:1450px;margin:40px auto;padding:0 24px;color:#243348}table{border-collapse:collapse;width:100%;margin:18px 0}th,td{padding:8px;border-bottom:1px solid #ddd;text-align:right}th:first-child,td:first-child{text-align:left}img{width:100%}details{margin:24px 0}.note{font-size:14px;color:#596b7e}</style><h1>Fixed treated centers: H versus J controls</h1><p>No rematching. H/J common treated centers separately at 3, 5, 10 km; original controls retained. Center + pair-year FE; Sun–Abraham ATT; spatial HAC 50 km.</p><p>H full → Common/H: treated sample composition. Common/H → Common/J: controls change. Common/J → J full: J-only treated composition. These are descriptive contrasts, not causal effects of matching choices.</p><p><a href="RESULTS_CN.md">中文结论</a> · <a href="estimates/lead_magnitude_diagnostics.csv">Lead magnitudes and tests</a> · <a href="estimates/decomposition_event_study.csv">Coefficient decomposition</a> · <a href="estimates/att_long.csv">All ATT and bandwidths</a></p>']
for r in [3,5,10]:
 n=next(x['common_treated'] for x in summary if x['radius_km']==str(r));parts.append(f'<details open><summary><b>{r} km: {n} common treated centers</b></summary>')
 for c in ['center','surroundings','cumulative']:
  parts.append(f'<h3>{c}</h3><table><tr><th>Outcome</th>'+''.join(f'<th>{v}<br>ATT(SE)<br>[lead p]</th>' for v in samples.values())+'</tr>')
  for y,label in labels.items():parts.append(f'<tr><td>{label}</td>'+''.join(f'<td>{fmt(get(a,r,c,y,s))}<br>[{float(get(pre,r,c,y,s)["p_value"]):.4f}]</td>' for s in samples)+'</tr>')
  for name,col in [('Pairs','pairs'),('Observations','observations')]:parts.append(f'<tr><td>{name}</td>'+''.join(f'<td>{get(a,r,c,"rac",s)[col]}</td>' for s in samples)+'</tr>')
  parts.append('</table>')
 parts.append('</details>')
for y,label in labels.items():parts.append(f'<details open><summary>{label}: selection and control comparison</summary><img src="estimates/comparison_{y}.png"></details>')
parts.append('<p class="note">Stars 10/5/1%. 95% pointwise intervals; lead tests −5 to −2. Full J values provided in tables; charts emphasize H full and two fixed-treated comparisons. Neither p-value changes nor overlapping confidence intervals constitute formal tests of differences.</p>')
(base/'results.html').write_text('\n'.join(parts));(base/'RESULTS_CN.md').write_text('\n'.join(md)+'\n')
root=Path('./output/research_extensions/23_spatial_spillover')
paths=[root/st/f for st in ['stage_h','stage_j'] for f in ['results.html','estimates/att_long.csv','matching/matched_pairs.csv']]
(base/'original_files_sha256.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2))

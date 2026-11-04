#!/usr/bin/env python3
"""Single entry point for the LIHTC replication workflow (run --help first)."""
from pathlib import Path
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable
AGGREGATES = ['lodes_rac_outcomes_tract2010_2010_2019.parquet', 'lodes_wac_outcomes_tract2010_2010_2019.parquet', 'lodes_od_same_tract2010_2010_2019.parquet']
STAGES = ['download-lodes', 'seer', 'panel', 'geometry', 'routing', 'commuting', 'primary-inputs', 'main', 'spatial', 'figures', 'verify']

def resolve(config, key):
    p = Path(config[key]).expanduser()
    return p if p.is_absolute() else ROOT / p

def required(stage, cfg):
    if stage == 'verify': return [ROOT/'output/research_extensions/28_paper_state_guarded_refresh/all_att.csv']
    lodes = resolve(cfg,'lodes_dir')
    if stage == 'download-lodes': return []
    if stage == 'seer': return [resolve(cfg,'seer_raw')]
    if stage == 'panel':
        return [resolve(cfg,'lihtc_csv'), resolve(cfg,'nhgis_dir'), resolve(cfg,'seer_summary'), *[lodes/f for f in AGGREGATES]]
    if stage == 'geometry':return [ROOT/'data_raw/LODES/tiger2010_tract/unzipped', ROOT/'data_raw/LODES/OD_related/out_od_full_parquet']
    if stage == 'routing':return [ROOT/'data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both', ROOT/'data_raw/LODES/OD_related/cache/tract2010_points_from_shapefile.parquet']
    if stage == 'commuting':return [ROOT/'data_raw/LODES/OD_related/cache/tract_pair_road_distance_2021.parquet', ROOT/'data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both']
    if stage == 'primary-inputs':return [ROOT/'data_panels/2010_2019_did_panel_with_seer.csv']
    if stage in ['main','spatial']:
        files=[ROOT/'data_panels/2010_2019_did_panel_with_seer.csv',ROOT/'data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv']
        if stage=='spatial':return files+[ROOT/'data_raw/LODES/OD_related/cache/tract2010_points_from_shapefile.parquet',ROOT/'data_raw/LODES/tiger2010_tract/unzipped']
        return files+[ROOT/'data_panels/od_commute_panel_residence_road.parquet',ROOT/'data_panels/primary_rac/2010_2019_panel_with_primary_rac.parquet',ROOT/'output/research_extensions/03_near_far/od_near_far_panel.parquet',ROOT/'data_raw/LODES/primary_wac_2010_2019/download_manifest.csv',*[ROOT/'data_raw/LODES/OD_related/lodes7_tract_agg_2010_2019'/f for f in AGGREGATES[:2]]]
    return [ROOT/'output/research_extensions/28_paper_state_guarded_refresh/all_att.csv',ROOT/'output/research_extensions/28_paper_state_guarded_refresh/all_event_study.csv',ROOT/'output/research_extensions/23_spatial_spillover/stage_o/estimates/event_study.csv']

def commands(stage, cfg):
    if stage=='verify':return [[PY,'code/analysis/verify_results.py']]
    py=lambda name:[PY,'code/data_process/'+name]
    r=lambda name:['Rscript','code/data_process/'+name]
    if stage=='download-lodes':return [r('download_lodes.R')]
    if stage=='seer':return [py('05_aggregate_seer.py')+['--input',str(resolve(cfg,'seer_raw')),'--output',str(resolve(cfg,'seer_summary'))]]
    if stage=='panel':return [py(x) for x in ['01_build_treatment.py','02_build_controls.py','03_build_employment.py','04_merge_panel.py','06_merge_seer.py']]
    if stage=='geometry':return [r('build_tract2010_points_from_tigerline.R'),r('compute_od_pair_distance_from_shapefile_points.R')]
    if stage=='routing':return [py('build_unique_tract_pairs_nodb.py'),py('query_osrm_road_distances.py'),py('merge_road_distance_batches.py')]
    if stage=='commuting':return [py('build_residence_panel_road.py'),r('build_near_far_panel.R')]
    if stage=='primary-inputs':return [r('download_primary_rac_2010_2019.R'),r('build_primary_rac_panel.R'),r('download_primary_wac.R')]
    return [['bash','code/analysis/run_'+{'main':'main','spatial':'spatial','figures':'figures'}[stage]+'.sh']]

def check(stage,cfg):
    errors=[]
    for p in required(stage,cfg):
        if not p.exists() or (p.is_dir() and not any(p.iterdir())):errors.append('Missing or empty input: '+str(p))
    if stage=='panel' and resolve(cfg,'nhgis_dir').is_dir():
        for pattern in ['nhgis*_ds172_2010_tract.csv','nhgis*_ds176_20105_tract.csv']:
            count=len(list(resolve(cfg,'nhgis_dir').glob(pattern)))
            if count!=1:errors.append(f'Expected exactly one NHGIS {pattern}, found {count}')
    for pkg in ['numpy','pandas','pyarrow']:
        if stage in ['panel','routing','commuting'] and importlib.util.find_spec(pkg) is None:errors.append('Missing Python package: '+pkg)
    if stage in ['download-lodes','geometry','commuting','primary-inputs','main','spatial','figures'] and not shutil.which('Rscript'):errors.append('Rscript is not on PATH')
    # Existing analysis code deliberately uses canonical locations, not arbitrary output paths.
    if stage in ['main','spatial','primary-inputs'] and resolve(cfg,'analysis_panel') != ROOT/'data_panels/2010_2019_did_panel_with_seer.csv':
        errors.append('Estimation uses the canonical data_panels/ path; copy the validated analysis panel there first.')
    return errors

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['list','check','run'])
    parser.add_argument('stage',nargs='?',choices=STAGES+['all'])
    parser.add_argument('--config',type=Path,default=ROOT/'config/paths.example.json')
    parser.add_argument('--dry-run',action='store_true',help='Print commands and missing inputs without executing')
    args=parser.parse_args()
    if args.action=='list':
        print('\n'.join(f'{i+1:02d}. {s}' for i,s in enumerate(STAGES)));return 0
    if args.stage is None:parser.error('check/run requires a stage')
    cfg=json.loads(args.config.resolve().read_text());stages=STAGES if args.stage=='all' else [args.stage]
    env=os.environ.copy();env['PROJECT_CONFIG']=str(args.config.resolve());env['PROJECT_ROOT']=str(ROOT);env['PYTHONPATH']=str(ROOT/'code')+os.pathsep+env.get('PYTHONPATH','')
    env['LODES_DIR']=str(resolve(cfg,'lodes_dir'))
    cache=ROOT/'data_raw/LODES/OD_related/cache';batches=ROOT/'data_intermediate/road_distance_batches'
    env.update(INPUT_PATH=str(cache/'unique_tract_pairs.parquet'),OUTPUT_DIR=str(batches),BATCHES_DIR=str(batches),OUTPUT_PATH=str(cache/'tract_pair_road_distance_2021.parquet'))
    failures=False
    for stage in stages:
        errors=check(stage,cfg);print(f'[{stage}]',flush=True)
        for error in errors:print('  '+error,flush=True)
        if args.action=='check':failures|=bool(errors);continue
        cmds=commands(stage,cfg)
        if args.dry_run:
            for cmd in cmds:print('  '+' '.join(cmd))
            continue
        if errors:return 2
        logs=ROOT/'output/replication_logs';logs.mkdir(parents=True,exist_ok=True)
        run={'stage':stage,'started':datetime.now(timezone.utc).isoformat(),'commands':cmds,'config':str(args.config.resolve()),'python':sys.version,'status':'running'}
        record=logs/(stage+'.json');record.write_text(json.dumps(run,indent=2))
        try:
            for i,cmd in enumerate(cmds):
                logfile=logs/f'{stage}-{i+1:02d}.log';print('  Running '+' '.join(cmd)+'\n  Log: '+str(logfile),flush=True)
                with logfile.open('w') as log:subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
        except subprocess.CalledProcessError as exc:
            run['status']='failed';run['exit_code']=exc.returncode;record.write_text(json.dumps(run,indent=2));print('Stopped at failed command; inspect '+str(logfile));return exc.returncode
        run['status']='complete';run['finished']=datetime.now(timezone.utc).isoformat();record.write_text(json.dumps(run,indent=2))
    return 2 if failures else 0

if __name__=='__main__':raise SystemExit(main())

"""
Ultra Memory-Efficient OD Panel Creation

Process files one at a time with aggressive memory management.
Designed to handle large states like CA, TX, FL without crashing.

Author: SKY
Date: January 2026
"""

import pandas as pd
import numpy as np
from pathlib import Path
import glob
import gc

INPUT_DIR = Path("/sessions/vigilant-wizardly-volta/mnt/project-lihtc-lodes/LODES/data_derivatives/out_od_full_parquet_with_dist_both")
OUTPUT_DIR = Path("/sessions/vigilant-wizardly-volta/mnt/project-lihtc-lodes/LODES/data_panels")
STATE_TEMP = OUTPUT_DIR / "temp_states"
STATE_TEMP.mkdir(parents=True, exist_ok=True)

LODES_VARS = ['S000', 'SA01', 'SA02', 'SA03', 'SE01', 'SE02', 'SE03', 'SI01', 'SI02', 'SI03']

print("=" * 80)
print("ULTRA MEMORY-EFFICIENT OD PANEL CREATION")
print("=" * 80)
print()


def calc_weighted_avg(group_df, weight_var):
    """Calculate weighted average distance."""
    dist = group_df['dist_centroid_km']
    weights = group_df[weight_var]
    valid = (~dist.isna()) & (~weights.isna()) & (weights > 0)

    if valid.sum() == 0:
        return np.nan

    return (dist[valid] * weights[valid]).sum() / weights[valid].sum()


def process_single_file_h(file_path):
    """Process one file for h_tract - ultra efficient."""
    df = pd.read_parquet(file_path, columns=[
        'h_tract', 'year', 'dist_centroid_km',
        'S000', 'SA01', 'SA02', 'SA03', 'SE01', 'SE02', 'SE03', 'SI01', 'SI02', 'SI03'
    ])

    results = []

    for (h_tract, year), grp in df.groupby(['h_tract', 'year']):
        row = {'h_tract': h_tract, 'year': year}

        for var in LODES_VARS:
            row[f'avg_dist_from_{var.lower()}'] = calc_weighted_avg(grp, var)
            row[f'total_{var.lower()}'] = grp[var].sum()

        results.append(row)

    panel = pd.DataFrame(results)
    del df, results
    gc.collect()

    return panel


def process_single_file_w(file_path):
    """Process one file for w_tract - ultra efficient."""
    df = pd.read_parquet(file_path, columns=[
        'w_tract', 'year', 'dist_centroid_km',
        'S000', 'SA01', 'SA02', 'SA03', 'SE01', 'SE02', 'SE03', 'SI01', 'SI02', 'SI03'
    ])

    results = []

    for (w_tract, year), grp in df.groupby(['w_tract', 'year']):
        row = {'w_tract': w_tract, 'year': year}

        for var in LODES_VARS:
            row[f'avg_dist_to_{var.lower()}'] = calc_weighted_avg(grp, var)
            row[f'total_{var.lower()}'] = grp[var].sum()

        results.append(row)

    panel = pd.DataFrame(results)
    del df, results
    gc.collect()

    return panel


def process_state_h(state, files):
    """Process one state for h_tract - file by file."""
    print(f"\n[H] State {state.upper()}: {len(files)} files")

    file_panels = []

    for i, fpath in enumerate(files, 1):
        fname = Path(fpath).name
        print(f"  {i}/{len(files)}: {fname}...", end=" ", flush=True)

        try:
            panel = process_single_file_h(fpath)
            file_panels.append(panel)
            print(f"{len(panel)} rows")

            del panel
            gc.collect()

        except Exception as e:
            print(f"ERROR: {e}")
            continue

    if file_panels:
        state_panel = pd.concat(file_panels, ignore_index=True)
        state_panel = state_panel.sort_values(['h_tract', 'year']).reset_index(drop=True)

        output = STATE_TEMP / f"h_panel_{state}.parquet"
        state_panel.to_parquet(output, index=False)

        print(f"  → {len(state_panel):,} tract-years saved")

        del file_panels, state_panel
        gc.collect()


def process_state_w(state, files):
    """Process one state for w_tract - file by file."""
    print(f"\n[W] State {state.upper()}: {len(files)} files")

    file_panels = []

    for i, fpath in enumerate(files, 1):
        fname = Path(fpath).name
        print(f"  {i}/{len(files)}: {fname}...", end=" ", flush=True)

        try:
            panel = process_single_file_w(fpath)
            file_panels.append(panel)
            print(f"{len(panel)} rows")

            del panel
            gc.collect()

        except Exception as e:
            print(f"ERROR: {e}")
            continue

    if file_panels:
        state_panel = pd.concat(file_panels, ignore_index=True)
        state_panel = state_panel.sort_values(['w_tract', 'year']).reset_index(drop=True)

        output = STATE_TEMP / f"w_panel_{state}.parquet"
        state_panel.to_parquet(output, index=False)

        print(f"  → {len(state_panel):,} tract-years saved")

        del file_panels, state_panel
        gc.collect()


def main():
    # Get all files grouped by state
    all_files = sorted(glob.glob(str(INPUT_DIR / "od_full_*.parquet")))
    print(f"Found {len(all_files)} files\n")

    state_files = {}
    for fpath in all_files:
        state = Path(fpath).name.split('_')[2]
        if state not in state_files:
            state_files[state] = []
        state_files[state].append(fpath)

    states = sorted(state_files.keys())
    print(f"{len(states)} states to process\n")

    # Check which states already done
    existing_h = set([f.stem.replace('h_panel_', '') for f in STATE_TEMP.glob('h_panel_*.parquet')])
    existing_w = set([f.stem.replace('w_panel_', '') for f in STATE_TEMP.glob('w_panel_*.parquet')])

    print(f"Already processed (H): {len(existing_h)} states")
    print(f"Already processed (W): {len(existing_w)} states\n")

    # H-TRACT PROCESSING
    print("=" * 80)
    print("PART 1: H_TRACT PANELS")
    print("=" * 80)

    for i, state in enumerate(states, 1):
        if state in existing_h:
            print(f"\n[{i}/{len(states)}] {state.upper()}: already done (H)")
            continue

        print(f"\n[{i}/{len(states)}] Processing {state.upper()}")
        try:
            process_state_h(state, state_files[state])
        except Exception as e:
            print(f"  ERROR processing {state}: {e}")
            continue

    # Combine H panels
    print("\n\nCombining H-tract panels...")
    h_files = sorted(STATE_TEMP.glob('h_panel_*.parquet'))
    print(f"Found {len(h_files)} state files")

    h_panels = [pd.read_parquet(f) for f in h_files]
    h_final = pd.concat(h_panels, ignore_index=True)
    h_final = h_final.sort_values(['h_tract', 'year']).reset_index(drop=True)

    output_h = OUTPUT_DIR / "od_commute_panel_residence.parquet"
    h_final.to_parquet(output_h, index=False)

    print(f"\n✓ H-PANEL COMPLETE: {h_final.shape} → {output_h.stat().st_size/1e6:.1f} MB")

    del h_panels, h_final
    gc.collect()

    # W-TRACT PROCESSING
    print("\n\n" + "=" * 80)
    print("PART 2: W_TRACT PANELS")
    print("=" * 80)

    for i, state in enumerate(states, 1):
        if state in existing_w:
            print(f"\n[{i}/{len(states)}] {state.upper()}: already done (W)")
            continue

        print(f"\n[{i}/{len(states)}] Processing {state.upper()}")
        try:
            process_state_w(state, state_files[state])
        except Exception as e:
            print(f"  ERROR processing {state}: {e}")
            continue

    # Combine W panels
    print("\n\nCombining W-tract panels...")
    w_files = sorted(STATE_TEMP.glob('w_panel_*.parquet'))
    print(f"Found {len(w_files)} state files")

    w_panels = [pd.read_parquet(f) for f in w_files]
    w_final = pd.concat(w_panels, ignore_index=True)
    w_final = w_final.sort_values(['w_tract', 'year']).reset_index(drop=True)

    output_w = OUTPUT_DIR / "od_commute_panel_workplace.parquet"
    w_final.to_parquet(output_w, index=False)

    print(f"\n✓ W-PANEL COMPLETE: {w_final.shape} → {output_w.stat().st_size/1e6:.1f} MB")

    # Cleanup
    print("\n\nCleaning up temp files...")
    for f in list(STATE_TEMP.glob('*.parquet')):
        f.unlink()
    STATE_TEMP.rmdir()

    print("\n" + "=" * 80)
    print("ALL DONE!")
    print("=" * 80)
    print(f"\nOutputs:")
    print(f"  1. {output_h}")
    print(f"  2. {output_w}")


if __name__ == "__main__":
    main()

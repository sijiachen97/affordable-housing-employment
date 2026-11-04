"""
OD Commuting Distance Panels - For Running Locally on Your Mac

This script is designed to run on your local machine where you have more memory.
Use this if the VM keeps running out of memory.

Usage:
    python3 create_od_panels_local.py

Expected runtime: 30-60 minutes
Memory required: ~8-16 GB RAM

Author: SKY
Date: January 2026
"""

import pandas as pd
import numpy as np
from pathlib import Path
import glob
import gc
from tqdm import tqdm

# ============================ CONFIGURATION ============================

# ADJUST THESE PATHS FOR YOUR MAC
INPUT_DIR = Path("./LODES/data_derivatives/out_od_full_parquet_with_dist_both")
OUTPUT_DIR = Path("./data_panels")
STATE_TEMP = OUTPUT_DIR / "temp_states"

# Create directories
STATE_TEMP.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# LODES variables to process
LODES_VARS = ['S000', 'SA01', 'SA02', 'SA03', 'SE01', 'SE02', 'SE03', 'SI01', 'SI02', 'SI03']

print("=" * 80)
print("OD COMMUTING DISTANCE PANELS - LOCAL PROCESSING")
print("=" * 80)
print(f"\nInput: {INPUT_DIR}")
print(f"Output: {OUTPUT_DIR}\n")

# ============================= FUNCTIONS ===============================

def calc_weighted_avg(group_df, weight_var):
    """Calculate weighted average commuting distance."""
    dist = group_df['dist_centroid_km']
    weights = group_df[weight_var]
    valid = (~dist.isna()) & (~weights.isna()) & (weights > 0)

    if valid.sum() == 0:
        return np.nan

    return (dist[valid] * weights[valid]).sum() / weights[valid].sum()


def process_file_h(file_path):
    """Process one file for h_tract panel."""
    # Read only needed columns to save memory
    cols = ['h_tract', 'year', 'dist_centroid_km'] + LODES_VARS

    df = pd.read_parquet(file_path, columns=cols)

    results = []

    for (h_tract, year), grp in df.groupby(['h_tract', 'year']):
        row = {'h_tract': h_tract, 'year': year}

        # Calculate distances and totals
        for var in LODES_VARS:
            row[f'avg_dist_from_{var.lower()}'] = calc_weighted_avg(grp, var)
            row[f'total_{var.lower()}'] = grp[var].sum()

        results.append(row)

    return pd.DataFrame(results)


def process_file_w(file_path):
    """Process one file for w_tract panel."""
    cols = ['w_tract', 'year', 'dist_centroid_km'] + LODES_VARS

    df = pd.read_parquet(file_path, columns=cols)

    results = []

    for (w_tract, year), grp in df.groupby(['w_tract', 'year']):
        row = {'w_tract': w_tract, 'year': year}

        # Calculate distances and totals
        for var in LODES_VARS:
            row[f'avg_dist_to_{var.lower()}'] = calc_weighted_avg(grp, var)
            row[f'total_{var.lower()}'] = grp[var].sum()

        results.append(row)

    return pd.DataFrame(results)


def process_state(state, files, tract_type):
    """Process all files for one state."""
    print(f"\nProcessing state {state.upper()} ({tract_type}): {len(files)} files")

    file_panels = []

    for fpath in tqdm(files, desc=f"  {state.upper()}"):
        try:
            if tract_type == 'h':
                panel = process_file_h(fpath)
            else:
                panel = process_file_w(fpath)

            file_panels.append(panel)

            del panel
            gc.collect()

        except Exception as e:
            print(f"\n  ERROR in {Path(fpath).name}: {e}")
            continue

    if file_panels:
        state_panel = pd.concat(file_panels, ignore_index=True)

        if tract_type == 'h':
            state_panel = state_panel.sort_values(['h_tract', 'year']).reset_index(drop=True)
            output = STATE_TEMP / f"h_panel_{state}.parquet"
        else:
            state_panel = state_panel.sort_values(['w_tract', 'year']).reset_index(drop=True)
            output = STATE_TEMP / f"w_panel_{state}.parquet"

        state_panel.to_parquet(output, index=False)
        print(f"  → Saved {len(state_panel):,} tract-years")

        del file_panels, state_panel
        gc.collect()


# ============================ MAIN PROCESSING ============================

def main():
    # Get all files
    all_files = sorted(glob.glob(str(INPUT_DIR / "od_full_*.parquet")))
    print(f"Found {len(all_files)} OD files\n")

    # Group by state
    state_files = {}
    for fpath in all_files:
        state = Path(fpath).name.split('_')[2]
        if state not in state_files:
            state_files[state] = []
        state_files[state].append(fpath)

    states = sorted(state_files.keys())
    print(f"States to process: {len(states)}\n")

    # Check existing
    existing_h = set([f.stem.replace('h_panel_', '') for f in STATE_TEMP.glob('h_panel_*.parquet')])
    existing_w = set([f.stem.replace('w_panel_', '') for f in STATE_TEMP.glob('w_panel_*.parquet')])

    print(f"Already done (H): {len(existing_h)} states")
    print(f"Already done (W): {len(existing_w)} states\n")

    # =============== PART 1: H-TRACT PANELS ===============

    print("=" * 80)
    print("PART 1: RESIDENCE-BASED PANELS (H-TRACT)")
    print("=" * 80)

    for state in states:
        if state in existing_h:
            print(f"\nState {state.upper()}: already processed (H)")
            continue

        try:
            process_state(state, state_files[state], 'h')
        except Exception as e:
            print(f"ERROR processing {state} (H): {e}")
            continue

    # Combine H panels
    print("\n\nCombining all H-tract state panels...")
    h_files = sorted(STATE_TEMP.glob('h_panel_*.parquet'))
    print(f"Found {len(h_files)} state files")

    h_panels = []
    for f in tqdm(h_files, desc="Loading H panels"):
        h_panels.append(pd.read_parquet(f))

    h_final = pd.concat(h_panels, ignore_index=True)
    h_final = h_final.sort_values(['h_tract', 'year']).reset_index(drop=True)

    output_h = OUTPUT_DIR / "od_commute_panel_residence.parquet"
    h_final.to_parquet(output_h, index=False)

    print(f"\n✓ H-PANEL COMPLETE")
    print(f"  Shape: {h_final.shape}")
    print(f"  File: {output_h}")
    print(f"  Size: {output_h.stat().st_size / 1e6:.1f} MB")

    del h_panels, h_final
    gc.collect()

    # =============== PART 2: W-TRACT PANELS ===============

    print("\n\n" + "=" * 80)
    print("PART 2: WORKPLACE-BASED PANELS (W-TRACT)")
    print("=" * 80)

    for state in states:
        if state in existing_w:
            print(f"\nState {state.upper()}: already processed (W)")
            continue

        try:
            process_state(state, state_files[state], 'w')
        except Exception as e:
            print(f"ERROR processing {state} (W): {e}")
            continue

    # Combine W panels
    print("\n\nCombining all W-tract state panels...")
    w_files = sorted(STATE_TEMP.glob('w_panel_*.parquet'))
    print(f"Found {len(w_files)} state files")

    w_panels = []
    for f in tqdm(w_files, desc="Loading W panels"):
        w_panels.append(pd.read_parquet(f))

    w_final = pd.concat(w_panels, ignore_index=True)
    w_final = w_final.sort_values(['w_tract', 'year']).reset_index(drop=True)

    output_w = OUTPUT_DIR / "od_commute_panel_workplace.parquet"
    w_final.to_parquet(output_w, index=False)

    print(f"\n✓ W-PANEL COMPLETE")
    print(f"  Shape: {w_final.shape}")
    print(f"  File: {output_w}")
    print(f"  Size: {output_w.stat().st_size / 1e6:.1f} MB")

    # Cleanup temp files
    print("\n\nCleaning up temporary files...")
    for f in list(STATE_TEMP.glob('*.parquet')):
        f.unlink()
    STATE_TEMP.rmdir()
    print("✓ Cleanup complete")

    # =============== SUMMARY ===============

    print("\n\n" + "=" * 80)
    print("PROCESSING COMPLETE!")
    print("=" * 80)

    print("\nOutput files:")
    print(f"  1. {output_h} ({output_h.stat().st_size/1e6:.1f} MB)")
    print(f"  2. {output_w} ({output_w.stat().st_size/1e6:.1f} MB)")

    # Show summary statistics
    print("\n--- Sample Statistics ---")

    h_reload = pd.read_parquet(output_h)
    print(f"\nResidence panel: {h_reload.shape}")
    print("\nAverage commute distances (km):")
    dist_cols = [c for c in h_reload.columns if c.startswith('avg_dist_from')]
    print(h_reload[dist_cols].describe().round(2))

    w_reload = pd.read_parquet(output_w)
    print(f"\nWorkplace panel: {w_reload.shape}")
    print("\nAverage commute distances (km):")
    dist_cols = [c for c in w_reload.columns if c.startswith('avg_dist_to')]
    print(w_reload[dist_cols].describe().round(2))

    print("\n" + "=" * 80)
    print("Ready for analysis!")
    print("=" * 80)


if __name__ == "__main__":
    main()

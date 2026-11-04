#!/usr/bin/env python3
"""
Merge OD Commuting Panels with LIHTC Panel

This script merges the residence and workplace commuting distance panels
with the LIHTC treatment and control variables panel.

Key operations:
1. Load OD panels (h_tract and w_tract as strings with leading zeros)
2. Load LIHTC panel (tract_id as integers without leading zeros)
3. Exclude columns with rac_, wac_, od_ prefixes from LIHTC panel
4. Convert tract IDs to match (string to int)
5. Merge on tract_id and year
6. Save merged panels

Author: SKY
Date: January 29, 2026
"""

import pandas as pd
import pyarrow.parquet as pq
from pathlib import Path
import gc

# Paths
PROJECT_DIR = Path("/sessions/vigilant-wizardly-volta/mnt/project-lihtc-lodes")
DATA_PANELS_DIR = PROJECT_DIR / "data_panels"

# Input files
OD_RESIDENCE = DATA_PANELS_DIR / "od_commute_panel_residence.parquet"
OD_WORKPLACE = DATA_PANELS_DIR / "od_commute_panel_workplace.parquet"
LIHTC_PANEL = DATA_PANELS_DIR / "2010_2019_did_panel_with_seer.csv"

# Output files
OUTPUT_RESIDENCE = DATA_PANELS_DIR / "od_commute_panel_residence_merged.parquet"
OUTPUT_WORKPLACE = DATA_PANELS_DIR / "od_commute_panel_workplace_merged.parquet"


def load_lihtc_panel():
    """
    Load LIHTC panel and exclude rac_, wac_, od_ columns.

    Returns:
        pd.DataFrame: LIHTC panel with only treatment and control variables
    """
    print("\n" + "=" * 80)
    print("LOADING LIHTC PANEL")
    print("=" * 80)

    # Read all columns first to identify which to exclude
    lihtc = pd.read_csv(LIHTC_PANEL)

    print(f"Original shape: {lihtc.shape}")
    print(f"Original columns: {len(lihtc.columns)}")

    # Identify columns to exclude
    exclude_prefixes = ['rac_', 'wac_', 'od_']
    exclude_cols = [
        col for col in lihtc.columns
        if any(col.startswith(prefix) for prefix in exclude_prefixes)
    ]

    print(f"\nExcluding {len(exclude_cols)} columns with prefixes: {exclude_prefixes}")
    print(f"  - rac_ columns: {sum(1 for c in exclude_cols if c.startswith('rac_'))}")
    print(f"  - wac_ columns: {sum(1 for c in exclude_cols if c.startswith('wac_'))}")
    print(f"  - od_ columns: {sum(1 for c in exclude_cols if c.startswith('od_'))}")

    # Keep only non-excluded columns
    keep_cols = [col for col in lihtc.columns if col not in exclude_cols]
    lihtc = lihtc[keep_cols]

    print(f"\nKept {len(keep_cols)} columns")
    print(f"Final shape: {lihtc.shape}")

    # Ensure tract_id is integer and year is integer
    lihtc['tract_id'] = lihtc['tract_id'].astype('int64')
    lihtc['year'] = lihtc['year'].astype('int64')

    print(f"\nTract ID range: {lihtc['tract_id'].min()} to {lihtc['tract_id'].max()}")
    print(f"Year range: {lihtc['year'].min()} to {lihtc['year'].max()}")

    return lihtc


def merge_residence_panel(lihtc):
    """
    Merge residence commuting panel with LIHTC panel.

    Args:
        lihtc: LIHTC panel DataFrame

    Returns:
        pd.DataFrame: Merged residence panel
    """
    print("\n" + "=" * 80)
    print("MERGING RESIDENCE PANEL")
    print("=" * 80)

    # Load OD residence panel
    print("Loading OD residence panel...")
    h_panel = pq.read_table(OD_RESIDENCE).to_pandas()

    print(f"OD residence panel shape: {h_panel.shape}")
    print(f"Columns: {h_panel.columns.tolist()}")

    # Convert h_tract from string to integer (remove leading zeros)
    print("\nConverting h_tract from string to integer...")
    print(f"  Before: h_tract dtype = {h_panel['h_tract'].dtype}")
    print(f"  Sample values: {h_panel['h_tract'].head(3).tolist()}")

    h_panel['tract_id'] = h_panel['h_tract'].astype('int64')
    h_panel['year'] = h_panel['year'].astype('int64')

    print(f"  After: tract_id dtype = {h_panel['tract_id'].dtype}")
    print(f"  Sample values: {h_panel['tract_id'].head(3).tolist()}")

    # Merge with LIHTC panel
    print("\nMerging with LIHTC panel...")
    print(f"  OD panel: {h_panel.shape[0]:,} rows")
    print(f"  LIHTC panel: {lihtc.shape[0]:,} rows")

    merged = h_panel.merge(
        lihtc,
        on=['tract_id', 'year'],
        how='left',
        suffixes=('', '_lihtc')
    )

    print(f"  Merged: {merged.shape[0]:,} rows, {merged.shape[1]} columns")

    # Check merge quality
    n_matched = merged['first_pis_year'].notna().sum()
    n_total = len(merged)
    print(f"\nMerge quality:")
    print(f"  Rows with LIHTC data: {n_matched:,} ({n_matched/n_total*100:.1f}%)")
    print(f"  Rows without LIHTC data: {n_total - n_matched:,} ({(n_total-n_matched)/n_total*100:.1f}%)")

    # Report column counts
    od_cols = [c for c in merged.columns if c.startswith('avg_dist_') or c.startswith('total_')]
    lihtc_cols = [c for c in merged.columns if c not in od_cols and c not in ['h_tract', 'year', 'tract_id']]

    print(f"\nColumn breakdown:")
    print(f"  OD outcomes: {len(od_cols)} columns")
    print(f"  LIHTC treatment/controls: {len(lihtc_cols)} columns")
    print(f"  IDs: 3 (h_tract, tract_id, year)")
    print(f"  Total: {merged.shape[1]} columns")

    return merged


def merge_workplace_panel(lihtc):
    """
    Merge workplace commuting panel with LIHTC panel.

    Args:
        lihtc: LIHTC panel DataFrame

    Returns:
        pd.DataFrame: Merged workplace panel
    """
    print("\n" + "=" * 80)
    print("MERGING WORKPLACE PANEL")
    print("=" * 80)

    # Load OD workplace panel
    print("Loading OD workplace panel...")
    w_panel = pq.read_table(OD_WORKPLACE).to_pandas()

    print(f"OD workplace panel shape: {w_panel.shape}")
    print(f"Columns: {w_panel.columns.tolist()}")

    # Convert w_tract from string to integer (remove leading zeros)
    print("\nConverting w_tract from string to integer...")
    print(f"  Before: w_tract dtype = {w_panel['w_tract'].dtype}")
    print(f"  Sample values: {w_panel['w_tract'].head(3).tolist()}")

    w_panel['tract_id'] = w_panel['w_tract'].astype('int64')
    w_panel['year'] = w_panel['year'].astype('int64')

    print(f"  After: tract_id dtype = {w_panel['tract_id'].dtype}")
    print(f"  Sample values: {w_panel['tract_id'].head(3).tolist()}")

    # Merge with LIHTC panel
    print("\nMerging with LIHTC panel...")
    print(f"  OD panel: {w_panel.shape[0]:,} rows")
    print(f"  LIHTC panel: {lihtc.shape[0]:,} rows")

    merged = w_panel.merge(
        lihtc,
        on=['tract_id', 'year'],
        how='left',
        suffixes=('', '_lihtc')
    )

    print(f"  Merged: {merged.shape[0]:,} rows, {merged.shape[1]} columns")

    # Check merge quality
    n_matched = merged['first_pis_year'].notna().sum()
    n_total = len(merged)
    print(f"\nMerge quality:")
    print(f"  Rows with LIHTC data: {n_matched:,} ({n_matched/n_total*100:.1f}%)")
    print(f"  Rows without LIHTC data: {n_total - n_matched:,} ({(n_total-n_matched)/n_total*100:.1f}%)")

    # Report column counts
    od_cols = [c for c in merged.columns if c.startswith('avg_dist_') or c.startswith('total_')]
    lihtc_cols = [c for c in merged.columns if c not in od_cols and c not in ['w_tract', 'year', 'tract_id']]

    print(f"\nColumn breakdown:")
    print(f"  OD outcomes: {len(od_cols)} columns")
    print(f"  LIHTC treatment/controls: {len(lihtc_cols)} columns")
    print(f"  IDs: 3 (w_tract, tract_id, year)")
    print(f"  Total: {merged.shape[1]} columns")

    return merged


def main():
    """Main execution function."""

    print("=" * 80)
    print("MERGE OD COMMUTING PANELS WITH LIHTC PANEL")
    print("=" * 80)
    print(f"\nInput files:")
    print(f"  - OD residence: {OD_RESIDENCE}")
    print(f"  - OD workplace: {OD_WORKPLACE}")
    print(f"  - LIHTC panel: {LIHTC_PANEL}")
    print(f"\nOutput files:")
    print(f"  - Residence merged: {OUTPUT_RESIDENCE}")
    print(f"  - Workplace merged: {OUTPUT_WORKPLACE}")

    # Step 1: Load LIHTC panel (excluding rac_, wac_, od_ columns)
    lihtc = load_lihtc_panel()

    # Step 2: Merge residence panel
    h_merged = merge_residence_panel(lihtc)

    # Save residence merged panel
    print(f"\nSaving residence merged panel to {OUTPUT_RESIDENCE}...")
    h_merged.to_parquet(OUTPUT_RESIDENCE, index=False, compression='snappy')
    print(f"  Saved! File size: {OUTPUT_RESIDENCE.stat().st_size / 1024**2:.1f} MB")

    # Clear memory
    del h_merged
    gc.collect()

    # Step 3: Merge workplace panel
    w_merged = merge_workplace_panel(lihtc)

    # Save workplace merged panel
    print(f"\nSaving workplace merged panel to {OUTPUT_WORKPLACE}...")
    w_merged.to_parquet(OUTPUT_WORKPLACE, index=False, compression='snappy')
    print(f"  Saved! File size: {OUTPUT_WORKPLACE.stat().st_size / 1024**2:.1f} MB")

    print("\n" + "=" * 80)
    print("MERGE COMPLETE!")
    print("=" * 80)
    print(f"\nFinal output files:")
    print(f"  1. {OUTPUT_RESIDENCE}")
    print(f"     - Residence-based commuting distances + LIHTC treatment/controls")
    print(f"  2. {OUTPUT_WORKPLACE}")
    print(f"     - Workplace-based commuting distances + LIHTC treatment/controls")
    print("\nThese merged panels are ready for Sun & Abraham event-study analysis!")
    print("=" * 80)


if __name__ == "__main__":
    main()

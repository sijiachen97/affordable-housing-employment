#!/usr/bin/env python3
"""
Phase 3 of the OSRM road-distance pipeline.

For each state-year OD parquet file in
  data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both/

  1. Read columns (h_tract, w_tract, year, dist_centroid_km, S000, SA01, ..., SI03)
  2. Join with the road-distance lookup at
     data_raw/LODES/OD_related/cache/tract_pair_road_distance_2021.parquet
     on (h_tract, w_tract) to attach road_dist_km, road_time_min, success
  3. Replace missing values:
       - For h_tract == w_tract: use dist_centroid_km (existing fallback), road_time_min = NaN
       - For failed OSRM queries (success == 0): road_dist_km and road_time_min = NaN
  4. Compute employment-weighted averages per (h_tract, year) for each LODES category:
       - avg_road_dist_from_<var>  (km)
       - avg_road_time_from_<var>  (min)
       - total_<var>               (employment count, unchanged)
  5. Accumulate per-state partial results, write final residence panel parquet:
       data_panels/od_commute_panel_residence_road.parquet

This is the road-distance counterpart of create_od_panels_local.py's residence
panel; the existing straight-line `od_commute_panel_residence_merged.parquet`
remains untouched for comparison.

Run on Mac:
  cd .
  python3 scripts/data_process/build_residence_panel_road.py

Expected runtime: 15-30 min on a modern Mac. Peak RAM: ~6-10 GB.
"""

from __future__ import annotations

import gc
import os
import time
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# ----------------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------------
PROJECT_ROOT = Path(os.environ.get(
    "PROJECT_ROOT",
    ".",
))
OD_DIR        = PROJECT_ROOT / "data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both"
ROAD_LOOKUP   = PROJECT_ROOT / "data_raw/LODES/OD_related/cache/tract_pair_road_distance_2021.parquet"
OUT_PATH      = PROJECT_ROOT / "data_panels/od_commute_panel_residence_road.parquet"

LODES_VARS = ["S000", "SA01", "SA02", "SA03",
              "SE01", "SE02", "SE03",
              "SI01", "SI02", "SI03"]


def weighted_avg(values: np.ndarray, weights: np.ndarray) -> float:
    """Weighted average ignoring NaNs and non-positive weights. Returns NaN if no valid rows."""
    mask = (~np.isnan(values)) & (~np.isnan(weights)) & (weights > 0)
    if not mask.any():
        return np.nan
    return float(np.sum(values[mask] * weights[mask]) / np.sum(weights[mask]))


def process_state(state: str, road_lookup: pd.DataFrame) -> pd.DataFrame:
    """Process all year files for one state. Returns h_tract-year panel rows for that state."""
    files = sorted(OD_DIR.glob(f"od_full_{state}_*.parquet"))
    if not files:
        return pd.DataFrame()

    # Read all year files for this state, only the columns we need.
    cols = ["h_tract", "w_tract", "year", "dist_centroid_km"] + LODES_VARS
    parts = [pd.read_parquet(f, columns=cols) for f in files]
    df = pd.concat(parts, ignore_index=True)
    del parts
    gc.collect()

    # Left join road distance lookup. Pairs not in lookup will have NaN road_*.
    # Note: road_lookup only contains pairs that appeared in any state-year, so
    # a left-join match is guaranteed for any pair present in this state's OD.
    df = df.merge(road_lookup, on=["h_tract", "w_tract"], how="left")

    # ---- Resolve missing road values ------------------------------------------------
    # For intra-tract pairs (h == w): OSRM was not queried, so road_dist/time are NaN.
    # Fall back to the existing straight-line dist_centroid_km. Road time stays NaN
    # (no meaningful "in-tract driving time" — these are typically walking-distance).
    intra_mask = df["h_tract"] == df["w_tract"]
    df.loc[intra_mask, "road_dist_km"] = df.loc[intra_mask, "dist_centroid_km"]
    # road_time_min stays NaN for intra-tract — will be excluded from time weighted avg

    # For failed queries (success == 0 from OSRM): leave as NaN. The weighted-avg
    # helper drops NaN rows, so these pairs simply don't contribute to averages.

    # Optional sanity: how many rows are usable for road distance vs road time
    n_dist_valid = (~df["road_dist_km"].isna()).sum()
    n_time_valid = (~df["road_time_min"].isna()).sum()

    # ---- Aggregate per (h_tract, year) ---------------------------------------------
    results = []
    for (h_tract, year), grp in df.groupby(["h_tract", "year"], sort=False):
        row = {"h_tract": h_tract, "year": int(year)}
        d_road = grp["road_dist_km"].to_numpy()
        t_road = grp["road_time_min"].to_numpy()
        for var in LODES_VARS:
            w = grp[var].to_numpy()
            row[f"avg_road_dist_from_{var.lower()}"] = weighted_avg(d_road, w)
            row[f"avg_road_time_from_{var.lower()}"] = weighted_avg(t_road, w)
            row[f"total_{var.lower()}"] = float(np.nansum(w))
        results.append(row)

    out = pd.DataFrame(results)
    print(f"  [{state}] rows={len(df):>9,} (road_dist_ok {n_dist_valid:>9,}, "
          f"road_time_ok {n_time_valid:>9,})  ->  {len(out):>6,} tract-year panel rows")
    return out


def main() -> None:
    assert OD_DIR.exists(), f"OD dir missing: {OD_DIR}"
    assert ROAD_LOOKUP.exists(), f"Road-distance lookup missing: {ROAD_LOOKUP}"

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    states = sorted({f.name.split("_")[2] for f in OD_DIR.glob("*.parquet")})
    print(f"[INFO] OD dir:        {OD_DIR}")
    print(f"[INFO] Road lookup:   {ROAD_LOOKUP}")
    print(f"[INFO] Output:        {OUT_PATH}")
    print(f"[INFO] States:        {len(states)}")
    print()

    t_load = time.time()
    print("[LOAD] Reading road-distance lookup into memory...")
    road = pd.read_parquet(
        ROAD_LOOKUP,
        columns=["h_tract", "w_tract", "road_dist_km", "road_time_min", "success"],
    )
    # Drop the 'success' flag — its information is encoded as NaN in road_dist_km
    # (failed queries already have NaN for both dist and time per query script).
    # But also explicitly set rows where success == 0 to NaN for safety.
    fail_mask = road["success"] == 0
    if fail_mask.any():
        road.loc[fail_mask, ["road_dist_km", "road_time_min"]] = np.nan
    road = road.drop(columns=["success"])
    print(f"       {len(road):,} pairs loaded in {time.time()-t_load:.1f}s "
          f"(missing dist: {road['road_dist_km'].isna().sum():,}; "
          f"missing time: {road['road_time_min'].isna().sum():,})")
    print()

    t0 = time.time()
    print(f"[AGGREGATE] processing {len(states)} states...")
    per_state_panels: list[pd.DataFrame] = []
    for i, st in enumerate(states, 1):
        t_st = time.time()
        try:
            panel = process_state(st, road)
        except Exception as e:
            print(f"  [{st}] ERROR: {e}")
            continue
        per_state_panels.append(panel)
        elapsed = time.time() - t_st
        print(f"  [{i:2d}/{len(states)}] state={st} done ({elapsed:5.1f}s, "
              f"total {time.time()-t0:5.1f}s)", flush=True)
        gc.collect()

    print()
    print("[MERGE] concatenating per-state panels...")
    final = pd.concat(per_state_panels, ignore_index=True)
    del per_state_panels
    gc.collect()
    print(f"       final shape: {final.shape}")
    print(f"       unique tract-year cells: {len(final):,}")

    # Sort for deterministic output
    final = final.sort_values(["h_tract", "year"]).reset_index(drop=True)

    print("[WRITE] saving parquet...")
    pa_tbl = pa.Table.from_pandas(final, preserve_index=False)
    pq.write_table(pa_tbl, OUT_PATH, compression="zstd")
    print(f"       wrote: {OUT_PATH}")
    print(f"       file size: {OUT_PATH.stat().st_size / 1e6:.1f} MB")

    # ---- Summary --------------------------------------------------------------------
    print()
    print("[SUMMARY]")
    s000_dist = final["avg_road_dist_from_s000"].dropna()
    s000_time = final["avg_road_time_from_s000"].dropna()
    print(f"  rows:                  {len(final):,}")
    print(f"  unique h_tracts:       {final['h_tract'].nunique():,}")
    print(f"  years:                 {sorted(final['year'].unique())}")
    print(f"  avg_road_dist_from_s000 (km):  "
          f"non-null={len(s000_dist):,}, "
          f"median={s000_dist.median():.2f}, mean={s000_dist.mean():.2f}, "
          f"p95={s000_dist.quantile(0.95):.2f}")
    print(f"  avg_road_time_from_s000 (min): "
          f"non-null={len(s000_time):,}, "
          f"median={s000_time.median():.2f}, mean={s000_time.mean():.2f}, "
          f"p95={s000_time.quantile(0.95):.2f}")

    print(f"[DONE] total elapsed: {time.time()-t0:.1f}s")


if __name__ == "__main__":
    main()

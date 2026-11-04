#!/usr/bin/env python3
"""
Phase 0 of the OSRM road-distance pipeline — DUCKDB-FREE FALLBACK.

Same goal as build_unique_tract_pairs.py, but uses only pyarrow + pandas
(no duckdb). Slower and somewhat more RAM-hungry, but works everywhere.

Streams state-by-state, dedupes within each state with pyarrow's
group_by(no aggregate), then accumulates per-state tables. Final
across-state dedupe at the end. Joins H/W lat/lon from
tract2010_points_from_shapefile.parquet, computes haversine, writes
unique_tract_pairs.parquet.

Run on user's Mac:
  cd .
  python3 scripts/data_process/build_unique_tract_pairs_nodb.py

Approx runtime: 20-60 min on a modern Mac. Approx peak RAM: ~4-6 GB
for ~100 M unique pairs.
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
OD_DIR = PROJECT_ROOT / "data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both"
POINTS_PATH = PROJECT_ROOT / "data_raw/LODES/OD_related/cache/tract2010_points_from_shapefile.parquet"
OUT_PATH = PROJECT_ROOT / "data_raw/LODES/OD_related/cache/unique_tract_pairs.parquet"


def discover_states() -> list[str]:
    return sorted({f.name.split("_")[2] for f in OD_DIR.glob("*.parquet")})


def haversine_km(lat1, lon1, lat2, lon2):
    """Vectorized haversine distance in kilometers (numpy)."""
    R = 6371.0088
    lat1r = np.radians(lat1)
    lat2r = np.radians(lat2)
    dphi = np.radians(lat2 - lat1)
    dlmb = np.radians(lon2 - lon1)
    a = np.sin(dphi / 2.0) ** 2 + np.cos(lat1r) * np.cos(lat2r) * np.sin(dlmb / 2.0) ** 2
    return 2 * R * np.arcsin(np.minimum(1.0, np.sqrt(a)))


def main() -> None:
    assert OD_DIR.exists(), f"OD directory not found: {OD_DIR}"
    assert POINTS_PATH.exists(), f"Tract-points lookup not found: {POINTS_PATH}"

    n_files = len(list(OD_DIR.glob("*.parquet")))
    states = discover_states()
    print(f"[INFO] OD files: {n_files} across {len(states)} states")
    print(f"[INFO] Tract-points lookup: {POINTS_PATH}")
    print(f"[INFO] Output: {OUT_PATH}")
    print()

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Step 1: per-state dedupe (use pandas drop_duplicates — works on all
    # pyarrow versions; pyarrow.Table.group_by requires pyarrow >= 7).
    # ------------------------------------------------------------------
    t0 = time.time()
    print(f"[STEP 1/3] Streaming dedupe across {len(states)} states...")
    per_state_dfs: list[pd.DataFrame] = []
    for i, st in enumerate(states, 1):
        t_st = time.time()
        files = sorted(OD_DIR.glob(f"od_full_{st}_*.parquet"))
        year_dfs = [
            pq.read_table(f, columns=["h_tract", "w_tract"]).to_pandas()
            for f in files
        ]
        state_df = (
            pd.concat(year_dfs, ignore_index=True)
              .drop_duplicates(["h_tract", "w_tract"])
              .reset_index(drop=True)
        )
        per_state_dfs.append(state_df)
        cum = sum(len(d) for d in per_state_dfs)
        print(f"  [{i:2d}/{len(states)}] {st}: state_unique={len(state_df):>10,}  "
              f"cum_rows={cum:>12,}  "
              f"({time.time()-t_st:5.1f}s, total {time.time()-t0:5.1f}s)",
              flush=True)
        del year_dfs, state_df
        gc.collect()

    # ------------------------------------------------------------------
    # Step 2: across-state dedupe + lat/lon join in pandas
    # ------------------------------------------------------------------
    print()
    t1 = time.time()
    print("[STEP 2/3] Concatenating + final dedupe across states...")
    final_df = (
        pd.concat(per_state_dfs, ignore_index=True)
          .drop_duplicates(["h_tract", "w_tract"])
          .reset_index(drop=True)
    )
    del per_state_dfs
    gc.collect()
    print(f"           unique pairs across full US 2010-2019: {len(final_df):,}   "
          f"({time.time()-t1:.1f}s)")

    print("           loading tract2010 lat/lon lookup...")
    pts = pq.read_table(
        POINTS_PATH,
        columns=["tract_id", "intpt_lat", "intpt_lon"],
    ).to_pandas()
    pts["tract_id"] = pts["tract_id"].astype(str)

    print("           joining h_tract...")
    final_df = final_df.merge(
        pts.rename(columns={"tract_id": "h_tract",
                            "intpt_lat": "h_intpt_lat",
                            "intpt_lon": "h_intpt_lon"}),
        on="h_tract", how="left",
    )
    print("           joining w_tract...")
    final_df = final_df.merge(
        pts.rename(columns={"tract_id": "w_tract",
                            "intpt_lat": "w_intpt_lat",
                            "intpt_lon": "w_intpt_lon"}),
        on="w_tract", how="left",
    )
    del pts
    gc.collect()

    miss_h = final_df["h_intpt_lat"].isna().sum()
    miss_w = final_df["w_intpt_lat"].isna().sum()
    print(f"           pairs missing h coord: {miss_h:,}")
    print(f"           pairs missing w coord: {miss_w:,}")
    print()

    # ------------------------------------------------------------------
    # Step 3: haversine + write parquet
    # ------------------------------------------------------------------
    t2 = time.time()
    print("[STEP 3/3] Computing haversine + writing parquet...")
    final_df["straight_line_km"] = haversine_km(
        final_df["h_intpt_lat"].to_numpy(),
        final_df["h_intpt_lon"].to_numpy(),
        final_df["w_intpt_lat"].to_numpy(),
        final_df["w_intpt_lon"].to_numpy(),
    )

    pa_tbl = pa.Table.from_pandas(
        final_df[
            ["h_tract", "w_tract",
             "h_intpt_lat", "h_intpt_lon",
             "w_intpt_lat", "w_intpt_lon",
             "straight_line_km"]
        ],
        preserve_index=False,
    )
    pq.write_table(pa_tbl, OUT_PATH, compression="zstd")
    print(f"           wrote: {OUT_PATH}   ({time.time()-t2:.1f}s)")
    print()

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    print("[SUMMARY]")
    pf = pq.ParquetFile(OUT_PATH)
    print(f"  output rows : {pf.metadata.num_rows:,}")
    print(f"  output cols : {pf.schema_arrow.names}")
    print(f"  file size   : {OUT_PATH.stat().st_size / 1e6:,.1f} MB")

    sld = final_df["straight_line_km"]
    intra = (final_df["h_tract"] == final_df["w_tract"]).sum()
    over_200 = (sld > 200).sum()
    missing = sld.isna().sum()
    print(f"  {'n_pairs':>16s} : {len(final_df):,}")
    print(f"  {'n_intra_tract':>16s} : {intra:,}")
    print(f"  {'n_over_200km':>16s} : {over_200:,}")
    print(f"  {'n_missing_dist':>16s} : {missing:,}")
    print(f"  {'mean_km':>16s} : {sld.mean():.3f}")
    print(f"  {'median_km':>16s} : {sld.median():.3f}")
    print(f"  {'p95_km':>16s} : {sld.quantile(0.95):.3f}")
    print(f"  {'p99_km':>16s} : {sld.quantile(0.99):.3f}")
    print(f"  {'max_km':>16s} : {sld.max():.3f}")

    workload = len(final_df) - intra - over_200 - missing
    print()
    print(f"[INFO] OSRM workload after filters: {workload:,} pairs to query")
    print(f"       (skip {intra:,} intra-tract, {over_200:,} > 200 km, "
          f"{missing:,} missing coords)")
    print(f"[DONE] total elapsed: {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()

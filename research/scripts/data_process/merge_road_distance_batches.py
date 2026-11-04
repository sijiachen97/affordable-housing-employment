#!/usr/bin/env python3
"""
Merge per-batch parquet files from query_osrm_road_distances.py into
one consolidated tract_pair_road_distance_<vintage>.parquet.

Default output path: ~/data/tract_pair_road_distance_2021.parquet
(can be set via env var OUTPUT_PATH).

Run on EC2 (or on Mac after scp-ing the batches dir back):
  python3 merge_road_distance_batches.py
"""

from __future__ import annotations

import os
import time
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

BATCHES_DIR = Path(os.environ.get(
    "BATCHES_DIR",
    os.path.expanduser("~/data/road_distances_batches"),
))
OUTPUT_PATH = Path(os.environ.get(
    "OUTPUT_PATH",
    os.path.expanduser("~/data/tract_pair_road_distance_2021.parquet"),
))


def main() -> None:
    assert BATCHES_DIR.exists(), f"Not found: {BATCHES_DIR}"
    files = sorted(BATCHES_DIR.glob("batch_*.parquet"))
    assert files, f"No batch_*.parquet files found in {BATCHES_DIR}"

    print(f"[INFO] Found {len(files)} batch files in {BATCHES_DIR}")
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    writer = None
    total_rows = 0
    for i, f in enumerate(files, 1):
        tbl = pq.read_table(f)
        if writer is None:
            writer = pq.ParquetWriter(OUTPUT_PATH, tbl.schema, compression="zstd")
        writer.write_table(tbl)
        total_rows += tbl.num_rows
        if i % 20 == 0 or i == len(files):
            print(f"  [{i:>4}/{len(files)}] merged, cum rows: {total_rows:,}")
    writer.close()
    print(f"[DONE] wrote {OUTPUT_PATH} ({total_rows:,} rows, "
          f"{OUTPUT_PATH.stat().st_size/1e6:.1f} MB) "
          f"in {time.time()-t0:.1f}s")

    # Quick summary
    df = pd.read_parquet(OUTPUT_PATH, columns=["road_dist_km", "road_time_min", "success"])
    succ = int(df["success"].sum())
    fail = int((df["success"] == 0).sum())
    print(f"[SUMMARY] success={succ:,}  failed={fail:,}  "
          f"({succ/(succ+fail)*100:.2f}% success)")
    df_ok = df[df["success"] == 1]
    print(f"  road_dist_km: median={df_ok['road_dist_km'].median():.2f}, "
          f"mean={df_ok['road_dist_km'].mean():.2f}, "
          f"max={df_ok['road_dist_km'].max():.2f}")
    print(f"  road_time_min: median={df_ok['road_time_min'].median():.2f}, "
          f"mean={df_ok['road_time_min'].mean():.2f}, "
          f"max={df_ok['road_time_min'].max():.2f}")


if __name__ == "__main__":
    main()

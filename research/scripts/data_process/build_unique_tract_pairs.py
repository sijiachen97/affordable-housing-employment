#!/usr/bin/env python3
"""
Phase 0 of the OSRM road-distance pipeline.

Scans the 504 state-year OD parquet files at
  data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both/

Streams state-by-state (so RAM use stays bounded), reading only
(h_tract, w_tract) columns. Accumulates unique pairs in an on-disk DuckDB
table, then joins the existing tract-level lookup at
  data_raw/LODES/OD_related/cache/tract2010_points_from_shapefile.parquet
to attach H/W internal-point lat/lon, computes haversine straight-line
distance for sanity check, and writes:
  data_raw/LODES/OD_related/cache/unique_tract_pairs.parquet

Output columns:
  h_tract, w_tract,
  h_intpt_lat, h_intpt_lon, w_intpt_lat, w_intpt_lon,
  straight_line_km

Run on user's Mac:
  cd .
  python3 scripts/data_process/build_unique_tract_pairs.py

Approx runtime on a modern Mac: 10-30 minutes for ~80-150 M unique pairs.
Approx peak RAM: ~3 GB. Approx peak disk in tmp: ~5-10 GB.

Override paths via env vars: PROJECT_ROOT, TMP_DIR.
Override threading via env var: DUCKDB_THREADS (default 4).
"""

from __future__ import annotations

import os
import time
from pathlib import Path

import duckdb
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

TMP_DIR = Path(os.environ.get("TMP_DIR", "/tmp/lihtc_osrm_phase0"))
TMP_DB = TMP_DIR / "pairs_inventory.duckdb"
TMP_DUCKDB_SPILL = TMP_DIR / "duckdb_spill"

DUCKDB_THREADS = int(os.environ.get("DUCKDB_THREADS", "4"))
DUCKDB_MEM = os.environ.get("DUCKDB_MEM", "6GB")


def discover_states() -> list[str]:
    """Pull state codes (e.g. 'ca', 'tx') from filenames like od_full_ca_2018.parquet."""
    states = sorted({f.name.split("_")[2] for f in OD_DIR.glob("*.parquet")})
    return states


def main() -> None:
    assert OD_DIR.exists(), f"OD directory not found: {OD_DIR}"
    assert POINTS_PATH.exists(), f"Tract-points lookup not found: {POINTS_PATH}"

    n_files = len(list(OD_DIR.glob("*.parquet")))
    states = discover_states()
    print(f"[INFO] OD files: {n_files} across {len(states)} states")
    print(f"[INFO] Tract-points lookup: {POINTS_PATH}")
    print(f"[INFO] Output: {OUT_PATH}")
    print(f"[INFO] Tmp DB:  {TMP_DB}  (will be deleted after success)")
    print(f"[INFO] Threads={DUCKDB_THREADS}, memory_limit={DUCKDB_MEM}")
    print()

    TMP_DIR.mkdir(parents=True, exist_ok=True)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    if TMP_DB.exists():
        TMP_DB.unlink()
    if (TMP_DB.with_suffix(".duckdb.wal")).exists():
        (TMP_DB.with_suffix(".duckdb.wal")).unlink()

    con = duckdb.connect(str(TMP_DB))
    con.execute(f"PRAGMA memory_limit='{DUCKDB_MEM}'")
    con.execute(f"PRAGMA temp_directory='{TMP_DUCKDB_SPILL}'")
    con.execute(f"PRAGMA threads={DUCKDB_THREADS}")

    # Use a primary-key table so INSERT OR IGNORE handles cross-state dedupe.
    con.execute("""
        CREATE TABLE pairs(
            h_tract VARCHAR NOT NULL,
            w_tract VARCHAR NOT NULL,
            PRIMARY KEY (h_tract, w_tract)
        )
    """)

    t0 = time.time()
    print(f"[STEP 1/3] Streaming dedupe across {len(states)} states...")
    for i, st in enumerate(states, 1):
        glob = str(OD_DIR / f"od_full_{st}_*.parquet")
        t_st = time.time()
        con.execute(f"""
            INSERT OR IGNORE INTO pairs
            SELECT DISTINCT h_tract, w_tract FROM read_parquet('{glob}')
        """)
        n = con.execute("SELECT COUNT(*) FROM pairs").fetchone()[0]
        print(f"  [{i:2d}/{len(states)}] {st}: cum_unique={n:>12,}  "
              f"(state {time.time()-t_st:5.1f}s, total {time.time()-t0:5.1f}s)",
              flush=True)

    n_pairs = con.execute("SELECT COUNT(*) FROM pairs").fetchone()[0]
    print(f"[STEP 1/3] Done. unique pairs across full US 2010-2019: {n_pairs:,}")
    print()

    t1 = time.time()
    print("[STEP 2/3] Joining tract2010 lat/lon lookup onto h_tract and w_tract...")
    con.execute(f"""
        CREATE TABLE pts AS
        SELECT tract_id, intpt_lat, intpt_lon
        FROM read_parquet('{POINTS_PATH}')
    """)
    n_pts = con.execute("SELECT COUNT(*) FROM pts").fetchone()[0]
    print(f"           tract-points lookup rows: {n_pts:,}")

    con.execute("""
        CREATE TABLE pairs_with_coords AS
        SELECT
            p.h_tract,
            p.w_tract,
            ph.intpt_lat AS h_intpt_lat,
            ph.intpt_lon AS h_intpt_lon,
            pw.intpt_lat AS w_intpt_lat,
            pw.intpt_lon AS w_intpt_lon
        FROM pairs p
        LEFT JOIN pts ph ON ph.tract_id = p.h_tract
        LEFT JOIN pts pw ON pw.tract_id = p.w_tract
    """)

    miss_h = con.execute("SELECT COUNT(*) FROM pairs_with_coords WHERE h_intpt_lat IS NULL").fetchone()[0]
    miss_w = con.execute("SELECT COUNT(*) FROM pairs_with_coords WHERE w_intpt_lat IS NULL").fetchone()[0]
    print(f"           pairs missing h coord: {miss_h:,}")
    print(f"           pairs missing w coord: {miss_w:,}   ({time.time()-t1:.1f}s)")
    print()

    t2 = time.time()
    print("[STEP 3/3] Computing haversine straight-line distance and writing parquet...")
    con.execute(f"""
        COPY (
            SELECT
                h_tract,
                w_tract,
                h_intpt_lat,
                h_intpt_lon,
                w_intpt_lat,
                w_intpt_lon,
                CASE
                    WHEN h_intpt_lat IS NULL OR w_intpt_lat IS NULL THEN NULL
                    ELSE 2 * 6371.0088 * ASIN(
                        LEAST(1.0, SQRT(
                            POW(SIN(RADIANS(w_intpt_lat - h_intpt_lat) / 2), 2)
                            + COS(RADIANS(h_intpt_lat)) * COS(RADIANS(w_intpt_lat))
                              * POW(SIN(RADIANS(w_intpt_lon - h_intpt_lon) / 2), 2)
                        ))
                    )
                END AS straight_line_km
            FROM pairs_with_coords
        )
        TO '{OUT_PATH}' (FORMAT PARQUET, COMPRESSION ZSTD)
    """)
    print(f"           wrote: {OUT_PATH}   ({time.time()-t2:.1f}s)")
    print()

    print("[SUMMARY]")
    pf = pq.ParquetFile(OUT_PATH)
    print(f"  output rows : {pf.metadata.num_rows:,}")
    print(f"  output cols : {pf.schema_arrow.names}")
    print(f"  file size   : {OUT_PATH.stat().st_size / 1e6:,.1f} MB")
    stats = con.execute(f"""
        SELECT
            COUNT(*)                                                   AS n_pairs,
            SUM(CASE WHEN h_tract = w_tract THEN 1 ELSE 0 END)         AS n_intra_tract,
            SUM(CASE WHEN straight_line_km > 200 THEN 1 ELSE 0 END)    AS n_over_200km,
            SUM(CASE WHEN straight_line_km IS NULL THEN 1 ELSE 0 END)  AS n_missing_dist,
            ROUND(AVG(straight_line_km),    3)                         AS mean_km,
            ROUND(MEDIAN(straight_line_km), 3)                         AS median_km,
            ROUND(quantile_cont(straight_line_km, 0.50), 3)            AS p50_km,
            ROUND(quantile_cont(straight_line_km, 0.95), 3)            AS p95_km,
            ROUND(quantile_cont(straight_line_km, 0.99), 3)            AS p99_km,
            ROUND(MAX(straight_line_km), 3)                            AS max_km
        FROM read_parquet('{OUT_PATH}')
    """).fetchall()[0]
    cols = ["n_pairs", "n_intra_tract", "n_over_200km", "n_missing_dist",
            "mean_km", "median_km", "p50_km", "p95_km", "p99_km", "max_km"]
    for c, v in zip(cols, stats):
        if isinstance(v, int):
            print(f"  {c:>16s} : {v:,}")
        else:
            print(f"  {c:>16s} : {v}")

    osrm_workload = stats[0] - stats[1] - stats[2] - stats[3]
    print()
    print(f"[INFO] OSRM workload after filters: {osrm_workload:,} pairs to query")
    print(f"       (skip {stats[1]:,} intra-tract, {stats[2]:,} > 200 km, "
          f"{stats[3]:,} missing coords)")

    con.close()
    # Clean up temp DB
    try:
        TMP_DB.unlink(missing_ok=True)
        wal = TMP_DB.with_suffix(".duckdb.wal")
        if wal.exists():
            wal.unlink()
    except Exception as e:
        print(f"[WARN] could not clean up tmp DB: {e}")

    print(f"[DONE] total elapsed: {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()

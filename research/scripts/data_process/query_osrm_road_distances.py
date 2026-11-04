#!/usr/bin/env python3
"""
Phase 2 of the OSRM road-distance pipeline.

Runs ON THE EC2 INSTANCE where osrm-routed is listening on localhost:5000.

For each unique h_tract in unique_tract_pairs.parquet:
  - Look up all (w_intpt_lon, w_intpt_lat) destinations for that h
  - Send batched /table queries to OSRM (one source, many destinations per call)
  - Save (h_tract, w_tract, road_dist_km, road_time_min, success) rows
  - Checkpoint every N h_tracts to per-batch parquet files

Per-batch files in OUTPUT_DIR/ can be merged with merge_road_distance_batches.py.

Run on EC2:
  cd ~
  python3 query_osrm_road_distances.py

Environment variables (optional overrides):
  INPUT_PATH      path to unique_tract_pairs.parquet (default ~/data/unique_tract_pairs.parquet)
  OUTPUT_DIR      where to write per-batch parquets (default ~/data/road_distances_batches)
  OSRM_URL        OSRM HTTP endpoint (default http://localhost:5000)
  BATCH_SIZE      destinations per /table call (default 1000)
  WORKERS         concurrent HTTP threads (default 8)
  CHECKPOINT      flush per-batch parquet every N h_tracts (default 100)
  MAX_TABLE_SIZE  must match osrm-routed --max-table-size (default 10000)
"""

from __future__ import annotations

import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pandas as pd
import requests

# ------------------------------------------------------------------ config
OSRM_URL       = os.environ.get("OSRM_URL", "http://localhost:5000")
INPUT_PATH     = Path(os.environ.get("INPUT_PATH",
                      os.path.expanduser("~/data/unique_tract_pairs.parquet")))
OUTPUT_DIR     = Path(os.environ.get("OUTPUT_DIR",
                      os.path.expanduser("~/data/road_distances_batches")))
BATCH_SIZE     = int(os.environ.get("BATCH_SIZE", "1000"))
WORKERS        = int(os.environ.get("WORKERS", "8"))
CHECKPOINT     = int(os.environ.get("CHECKPOINT", "100"))
MAX_TABLE_SIZE = int(os.environ.get("MAX_TABLE_SIZE", "10000"))

assert BATCH_SIZE + 1 <= MAX_TABLE_SIZE, \
    f"BATCH_SIZE+1 ({BATCH_SIZE+1}) must be <= MAX_TABLE_SIZE ({MAX_TABLE_SIZE})"


# ------------------------------------------------------------------ HTTP
SESSION = requests.Session()
# Pool size matches concurrency to avoid connection thrashing.
_adapter = requests.adapters.HTTPAdapter(pool_connections=WORKERS, pool_maxsize=WORKERS)
SESSION.mount("http://", _adapter)


def query_table(h_lon: float, h_lat: float,
                w_coords: list[tuple[float, float]]) -> tuple[list, list]:
    """Send one /table query (1 source × N destinations). Returns (distances_m, durations_s)."""
    coords = f"{h_lon:.6f},{h_lat:.6f};" + ";".join(
        f"{lon:.6f},{lat:.6f}" for lon, lat in w_coords
    )
    n = len(w_coords)
    dst_idx = ";".join(str(i + 1) for i in range(n))
    url = (f"{OSRM_URL}/table/v1/driving/{coords}"
           f"?sources=0&destinations={dst_idx}&annotations=distance,duration")
    r = SESSION.get(url, timeout=180)
    r.raise_for_status()
    data = r.json()
    if data.get("code") != "Ok":
        raise RuntimeError(f"OSRM error: {data.get('code')} - {data.get('message')}")
    # OSRM returns 1×N matrices for 1 source × N destinations
    return data["distances"][0], data["durations"][0]


def process_h_tract(h_tract: str, h_lon: float, h_lat: float,
                    w_df: pd.DataFrame) -> list[tuple]:
    """All destinations for one h_tract. Returns list of result tuples."""
    out = []
    for i in range(0, len(w_df), BATCH_SIZE):
        chunk = w_df.iloc[i:i + BATCH_SIZE]
        w_coords = list(zip(chunk["w_intpt_lon"].tolist(),
                            chunk["w_intpt_lat"].tolist()))
        w_tracts = chunk["w_tract"].tolist()
        try:
            dists_m, durs_s = query_table(h_lon, h_lat, w_coords)
            for w_tract, d, t in zip(w_tracts, dists_m, durs_s):
                if d is None or t is None:
                    out.append((h_tract, w_tract, None, None, 0))
                else:
                    out.append((h_tract, w_tract, d / 1000.0, t / 60.0, 1))
        except Exception:
            # Whole chunk failed — record as failures, keep moving.
            for w_tract in w_tracts:
                out.append((h_tract, w_tract, None, None, 0))
    return out


def load_done_h_tracts(done_file: Path) -> set[str]:
    if not done_file.exists():
        return set()
    with done_file.open() as f:
        return {line.strip() for line in f if line.strip()}


def append_done(done_file: Path, h_tracts: list[str]) -> None:
    with done_file.open("a") as f:
        for h in h_tracts:
            f.write(f"{h}\n")


def write_batch(out_path: Path, rows: list[tuple]) -> None:
    df = pd.DataFrame(rows, columns=[
        "h_tract", "w_tract", "road_dist_km", "road_time_min", "success",
    ])
    df.to_parquet(out_path, compression="zstd")


def main() -> None:
    assert INPUT_PATH.exists(), f"Input file not found: {INPUT_PATH}"
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    done_file = OUTPUT_DIR / "done_h_tracts.txt"

    # Verify OSRM is alive before doing any work
    try:
        r = SESSION.get(f"{OSRM_URL}/route/v1/driving/-77.0365,38.8977;-77.0091,38.8895",
                        timeout=15)
        r.raise_for_status()
        assert r.json().get("code") == "Ok"
        print(f"[OK]  OSRM responding at {OSRM_URL}")
    except Exception as e:
        sys.exit(f"[FAIL] OSRM not responding at {OSRM_URL}: {e}")

    print(f"[INFO] Loading pair table: {INPUT_PATH}")
    t_load = time.time()
    df = pd.read_parquet(INPUT_PATH)
    print(f"[INFO] Loaded {len(df):,} pairs across {df['h_tract'].nunique():,} unique h_tracts "
          f"({time.time() - t_load:.1f}s)")

    done = load_done_h_tracts(done_file)
    print(f"[INFO] Previously completed h_tracts: {len(done):,}")
    if done:
        df = df[~df["h_tract"].isin(done)]
        print(f"[INFO] Remaining pairs: {len(df):,}")

    # Group by h_tract; sort by destination count desc so big sources finish first
    print("[INFO] Grouping by h_tract...")
    h_groups = sorted(
        df.groupby("h_tract"),
        key=lambda kv: -len(kv[1]),
    )
    print(f"[INFO] h_tracts to process: {len(h_groups):,}")
    print(f"[INFO] Config: WORKERS={WORKERS}, BATCH_SIZE={BATCH_SIZE}, "
          f"CHECKPOINT={CHECKPOINT}")
    print()

    batch_id_base = int(time.time())
    batch_idx = 0
    completed = 0
    batch_rows: list[tuple] = []
    batch_h_done: list[str] = []

    t_start = time.time()

    def _submit(item):
        h_tract, group = item
        h_lon = float(group.iloc[0]["h_intpt_lon"])
        h_lat = float(group.iloc[0]["h_intpt_lat"])
        return h_tract, process_h_tract(h_tract, h_lon, h_lat, group)

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futures = {ex.submit(_submit, item): item[0] for item in h_groups}
        for fut in as_completed(futures):
            try:
                h_tract, rows = fut.result()
            except Exception as e:
                print(f"  [ERROR] h_tract {futures[fut]}: {e}")
                continue
            batch_rows.extend(rows)
            batch_h_done.append(h_tract)
            completed += 1

            if completed % CHECKPOINT == 0:
                batch_idx += 1
                out_path = OUTPUT_DIR / f"batch_{batch_id_base}_{batch_idx:05d}.parquet"
                write_batch(out_path, batch_rows)
                append_done(done_file, batch_h_done)

                elapsed = time.time() - t_start
                rate_h = completed / elapsed
                eta_s = (len(h_groups) - completed) / max(rate_h, 1e-6)
                pairs_so_far = sum(1 for _ in batch_rows) if False else len(batch_rows)
                print(f"  [{completed:>6,}/{len(h_groups):,}] "
                      f"saved {out_path.name} ({len(batch_rows):,} rows), "
                      f"rate {rate_h:.1f} h/s, ETA {eta_s/60:.1f} min",
                      flush=True)
                batch_rows = []
                batch_h_done = []

    # Flush any remaining rows
    if batch_rows:
        batch_idx += 1
        out_path = OUTPUT_DIR / f"batch_{batch_id_base}_{batch_idx:05d}.parquet"
        write_batch(out_path, batch_rows)
        append_done(done_file, batch_h_done)
        print(f"  [final] saved {out_path.name} ({len(batch_rows):,} rows)")

    total = time.time() - t_start
    print()
    print(f"[DONE] {completed:,} h_tracts processed in {total/60:.1f} min "
          f"({completed/total:.1f} h/s)")
    print(f"[DONE] Per-batch parquets in: {OUTPUT_DIR}")
    print("[DONE] Run merge_road_distance_batches.py to consolidate.")


if __name__ == "__main__":
    main()

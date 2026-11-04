from __future__ import annotations

import argparse
import csv
import sys
import subprocess
from collections import defaultdict
from pathlib import Path


RACE_MAP = {
    "1": "nh_white",
    "2": "nh_black",
    "3": "nh_aian",
    "4": "nh_api",
    "5": "hispanic",
}


def age_bucket(age_code: str) -> str:
    code = int(age_code)
    # SEER age codes:
    # 00=0, 01=1-4, 02=5-9, 03=10-14, 04=15-19, 05=20-24, 06=25-29, 07=30-34, ... 11=50-54, 12=55-59, ... 19=90+
    if code <= 6:
        return "age_under_29"  # 00-06: 0-29
    if 7 <= code <= 11:
        return "age_30_54"  # 07-11: 30-54
    return "age_55_plus"  # 12-19: 55+


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Aggregate SEER tract-year population demographics.")
    p.add_argument("--input", type=Path, required=True, help="Path to fixed-width input .txt file")
    p.add_argument("--output", type=Path, required=True, help="Path to output CSV")
    p.add_argument(
        "--progress-every",
        type=int,
        default=250_000,
        help="Print progress every N lines (default: 250000)",
    )
    p.add_argument(
        "--scale",
        type=int,
        default=10_000,
        help="Implied-decimal scale factor (default: 10000)",
    )
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    total_sum: dict[tuple[str, str, str, str], int] = defaultdict(int)
    race_sum: dict[tuple[tuple[str, str, str, str], str], int] = defaultdict(int)
    age_sum: dict[tuple[tuple[str, str, str, str], str], int] = defaultdict(int)

    total_lines = None
    try:
        result = subprocess.run(
            ["wc", "-l", str(args.input)],
            capture_output=True,
            text=True,
            check=True,
        )
        total_lines = int(result.stdout.strip().split()[0])
    except OSError:
        total_lines = None
    except Exception:
        total_lines = None

    def progress(i: int) -> None:
        if total_lines:
            pct = (i / total_lines) * 100
            print(f"Processed {i:,}/{total_lines:,} lines ({pct:.1f}%)", file=sys.stderr)
        else:
            print(f"Processed {i:,} lines", file=sys.stderr)

    with args.input.open("r", newline="") as f:
        for i, line in enumerate(f, 1):
            if not line:
                continue

            year = line[0:4]
            state_fips = line[6:8]
            county_fips = line[8:11]
            tract = line[11:17]
            race = line[17:18]
            age = line[19:21]
            pop_raw = line[21:30]

            if not pop_raw.strip():
                continue

            try:
                pop_int = int(pop_raw)
            except ValueError:
                continue

            tract_fips2010 = f"{state_fips}{county_fips}{tract}"
            key = (year, state_fips, county_fips, tract_fips2010)

            total_sum[key] += pop_int

            race_group = RACE_MAP.get(race)
            if race_group:
                race_sum[(key, race_group)] += pop_int

            age_group = age_bucket(age)
            age_sum[(key, age_group)] += pop_int

            if args.progress_every > 0 and i % args.progress_every == 0:
                progress(i)

    # Final progress line
    if args.progress_every > 0:
        progress(i)

    args.output.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "state",
        "county",
        "tract_fips2010",
        "year",
        "total_population",
        "nh_white",
        "nh_black",
        "nh_aian",
        "nh_api",
        "hispanic",
        "age_under_29",
        "age_30_54",
        "age_55_plus",
    ]

    with args.output.open("w", newline="") as out_f:
        writer = csv.DictWriter(out_f, fieldnames=fieldnames)
        writer.writeheader()

        for (year, state_fips, county_fips, tract_fips2010), total in total_sum.items():
            row = {
                "state": state_fips,
                "county": county_fips,
                "tract_fips2010": tract_fips2010,
                "year": year,
                "total_population": total / args.scale,
                "nh_white": race_sum.get(((year, state_fips, county_fips, tract_fips2010), "nh_white"), 0)
                / args.scale,
                "nh_black": race_sum.get(((year, state_fips, county_fips, tract_fips2010), "nh_black"), 0)
                / args.scale,
                "nh_aian": race_sum.get(((year, state_fips, county_fips, tract_fips2010), "nh_aian"), 0)
                / args.scale,
                "nh_api": race_sum.get(((year, state_fips, county_fips, tract_fips2010), "nh_api"), 0)
                / args.scale,
                "hispanic": race_sum.get(((year, state_fips, county_fips, tract_fips2010), "hispanic"), 0)
                / args.scale,
                "age_under_29": age_sum.get(((year, state_fips, county_fips, tract_fips2010), "age_under_29"), 0)
                / args.scale,
                "age_30_54": age_sum.get(((year, state_fips, county_fips, tract_fips2010), "age_30_54"), 0)
                / args.scale,
                "age_55_plus": age_sum.get(((year, state_fips, county_fips, tract_fips2010), "age_55_plus"), 0)
                / args.scale,
            }
            writer.writerow(row)

    print(f"Wrote {len(total_sum)} rows to {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
mkdir -p "$HERE/work/stage_a" "$HERE/work/stage_b" "$HERE/work/stage_h/matching" "$HERE/work/stage_j/matching" "$HERE/estimates"
if [ ! -e "$HERE/work/stage_c" ]; then ln -s "$ROOT/stage_c" "$HERE/work/stage_c"; fi
Rscript "$HERE/scripts/prepare_7km_cache.R" "$ROOT" "$HERE/work"
Rscript "$HERE/scripts/prepare_7km_eligibility.R" "$HERE/work/stage_a" "$HERE/work/stage_b"
Rscript "$HERE/scripts/match_7km_H.R" "$HERE/work/stage_a" "$HERE/work/stage_b" "$HERE/work/stage_h/matching"
Rscript "$HERE/scripts/estimate_7km_isolated.R" "$HERE/work" "$HERE/estimates"
Rscript "$HERE/scripts/validate_7km_isolated.R" "$HERE/work" "$HERE/estimates"
Rscript "$HERE/scripts/report_7km_isolated.R" "$ROOT" "$HERE"
python3 "$HERE/scripts/report_7km_isolated.py" "$HERE"

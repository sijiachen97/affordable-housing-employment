#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
mkdir -p "$HERE/work/stage_a" "$HERE/work/stage_b" "$HERE/work/stage_h/matching" "$HERE/work/stage_j/matching" "$HERE/estimates"
Rscript "$HERE/prepare.R" "$ROOT" "$HERE/work"
Rscript "$HERE/match_guarded_regions.R" "$HERE/work/stage_a" "$HERE/work/stage_b" "$HERE/work/stage_h/matching"
Rscript "$HERE/estimate_guarded_regions.R" "$HERE/work" "$HERE/estimates"
Rscript "$HERE/validate.R" "$HERE/work" "$HERE/estimates"
Rscript "$HERE/compare.R" "$ROOT" "$HERE"
Rscript "$HERE/plot_standalone.R" "$HERE"
python3 "$HERE/report.py" "$HERE"

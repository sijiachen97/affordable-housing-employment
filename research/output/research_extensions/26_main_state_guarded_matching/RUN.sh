#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export LIHTC_EXPANDED_MAIN_OUTPUT="$HERE"
Rscript "$HERE/main_state_guarded.R"
Rscript "$HERE/commute_level.R" "$HERE"
Rscript "$HERE/audit_guards.R" "$HERE"
Rscript "$HERE/compare_versions.R" "$HERE"
python3 "$HERE/validate_and_report.py" "$HERE"

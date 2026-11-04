#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export LIHTC_REFRESH_OUTPUT="$HERE"
Rscript "$HERE/prepare_panel.R"
Rscript "$HERE/match_intensity.R"
Rscript "$HERE/validate_design.R"
Rscript "$HERE/estimate_core.R"
Rscript "$HERE/estimate_extensions.R"
Rscript "$HERE/estimate_industry.R" rac
Rscript "$HERE/estimate_industry.R" wac
Rscript "$HERE/descriptives.R"
Rscript "$HERE/coverage.R"
Rscript "$HERE/present.R"
python3 "$HERE/report.py" "$HERE"

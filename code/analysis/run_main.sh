#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export LIHTC_EXPANDED_MAIN_OUTPUT="$PWD/output/research_extensions/26_main_state_guarded_matching"
export LIHTC_REFRESH_OUTPUT="$PWD/output/research_extensions/28_paper_state_guarded_refresh"
mkdir -p "$LIHTC_EXPANDED_MAIN_OUTPUT" "$LIHTC_REFRESH_OUTPUT/primary_wac"
Rscript code/analysis/matching/main_state_guarded.R
for script in prepare_panel match_intensity validate_design estimate_core estimate_extensions; do
  Rscript "code/analysis/main/$script.R"
done
Rscript code/analysis/main/estimate_industry.R rac
Rscript code/analysis/main/estimate_industry.R wac
for script in descriptives coverage present estimate_primary_wac; do
  Rscript "code/analysis/main/$script.R"
done

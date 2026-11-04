#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
for script in figures event_figures new_figures primary_figure extra_figures; do
  Rscript "code/analysis/figures/$script.R"
done
python3 code/analysis/figures/build.py
python3 code/analysis/figures/export_paper_tables.py

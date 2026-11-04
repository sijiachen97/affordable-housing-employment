# Research workflow: affordable housing and employment

## Working with the research source

`research/` contains the original research code, including data construction and estimation. `code/` retains the smaller, separately documented portfolio utilities. Run research scripts with **`research/` as the working directory**. Original project-root paths have been changed to `.` in these copies; configure any remaining legacy/external input paths before execution. Do not point the copies at the original research folder if you want to keep its outputs unchanged.

Notebook outputs, execution counts and cell metadata have been cleared. Notebook cell order and analysis specifications are retained; the notebooks contain successive specifications and are not advertised as a clean, unattended pipeline. No respondent-level data or model caches are included. `docs/SOURCE_MANIFEST.json` records original relative filenames, source hashes and adaptations.

## Main production path

| Stage | Code under `research/` | Inputs / outputs |
| --- | --- | --- |
| Download employment records | `scripts/data_process/download_2010_2019_lodes.R`; `download_primary_rac_2010_2019.R` | LODES RAC/WAC/OD source files; primary-job sensitivity inputs |
| Treatment and baseline controls | `scripts/data_process/notebooks/data prep - lihtc property.ipynb`; `data prep - 2010 census data (controls).ipynb` | HUD project records and Census/ACS extracts → treatment histories and baseline controls |
| Employment and panel merge | `scripts/data_process/notebooks/data prep - merge lodes outcomes.ipynb`; `data prep - merge panels (LIHTC + ACS + LODES).ipynb` | RAC/WAC employment aggregates, treatment and controls → tract-year panel |
| Commute inputs and outcomes | `build_tract2010_points_from_tigerline.R`, `compute_od_pair_distance_from_shapefile_points.R`, `build_unique_tract_pairs_nodb.py`, `query_osrm_road_distances.py`, `merge_road_distance_batches.py`, `build_residence_panel_road.py` in `scripts/data_process/` | Geographic points and OD flows → route distances and residence-based commute panel |
| Current state matching | `output/research_extensions/26_main_state_guarded_matching/main_state_guarded.R` | Prepared SEER-population panel → `matched_pairs.csv`, balance and retention tables |
| Main regressions and extensions | `output/research_extensions/28_paper_state_guarded_refresh/RUN.sh` | Prepare design, intensity matching, validation, main outcomes, nearby/distant outcomes, industries, descriptives and result tables |
| Spatial redistribution | `output/research_extensions/23_spatial_spillover/` | Region construction, alternative matching stages and stage-o guarded estimates; stage-n supplies the 7-km inputs |
| Paper figures | `output/research_extensions/28_paper_state_guarded_refresh/paper_preview/*.R` | Saved main and spatial estimates → paper figures |

The main estimation engine is `28_paper_state_guarded_refresh/engine.R`, used by `estimate_core.R`, `estimate_extensions.R` and `estimate_industry.R`. This is the current state-matched refresh, rather than the older county-matched specification. The `output/` path is retained because production code was stored there in the original project; the repository includes source files, not generated research datasets.

## Main estimation commands (after preparing inputs)

```sh
cd research
export LIHTC_EXPANDED_MAIN_OUTPUT="$PWD/output/research_extensions/26_main_state_guarded_matching"
Rscript "$LIHTC_EXPANDED_MAIN_OUTPUT/main_state_guarded.R"
bash output/research_extensions/28_paper_state_guarded_refresh/RUN.sh
```

These commands start at the prepared-panel stage. The original stage-26 `RUN.sh` also performs comparisons against earlier saved estimates; those comparisons require the earlier outputs. Spatial stage-o similarly requires upstream region caches; its `RUN.sh` is not a replacement for constructing them.

## Remaining reproducibility work

- The notebook panel merge is included, but a verified bridge from its panel to `data_panels/2010_2019_did_panel_with_seer.csv` has not yet been located. Obtain SEER tract population through the official source and reconcile merge keys and population definitions before running the regressions.
- Some preparation notebooks use legacy LIHTC/LODES layouts, now mapped to `research/legacy_inputs/LIHTC` and `research/legacy_inputs/LODES`. Set these to the downloaded inputs; do not infer that similarly named files are interchangeable.
- Spatial scripts preserve the research stages and their dependencies, including alternative/diagnostic stages. Their full raw-to-stage-o execution order has not been rerun or certified here.
- Alternative OD builders are retained as preparation variants. Older LODES5 `get_lodes_*` scripts are omitted; use the 2010–2019 downloader. The county-trajectory matching script is included only as an upstream dependency for older spatial caches, not as the main state-matched specification.
- National routing and all regressions have not been rerun for this repository update. The source inclusion does not certify numerical reproduction of the paper.

See [CODE_GUIDE.md](CODE_GUIDE.md) for source-data download links and the standalone routing utility instructions.

## Software referenced by the source

R packages: `MatchIt`, `Matrix`, `arrow`, `data.table`, `dplyr`, `fixest`, `lehdr`, `purrr`, `sf`, `tidyverse`.

Python imports (including standard-library modules): `__future__`, `concurrent`, `csv`, `duckdb`, `gc`, `glob`, `numpy`, `os`, `pandas`, `pathlib`, `pyarrow`, `requests`, `sys`, `time`, `tqdm`, `typing`.

These are detected imports, not a pinned or tested environment lockfile. The requirements for the smaller `code/` utilities do not necessarily cover the complete research notebooks.

# Affordable housing: code guide

All executable research code is under `code/`. `code/data_process/` constructs inputs; `code/analysis/` estimates models and produces tables/figures. Run commands from the repository root. The original research folders are unchanged.

The code is selected against the supplied final paper/slides and their production dependencies, rather than copied as an archive of every experiment. [Source manifest](SOURCE_MANIFEST.json) records original filenames, selected notebook cells, hashes and adaptations. [Source review](SOURCE_REVIEW.json) lists the reviewed source inventory and inclusion/exclusion decisions. No microdata, model caches or saved notebook outputs are shared.

## Final version and output correspondence

Reference: `writing/main_revised_v21.tex` and its `generated_guarded/tables_figures.tex`, corresponding to the final state-matched paper. The current main estimation comes from stage 28, using the state-matched assignments produced by stage 26.

| Paper component | Included code |
| --- | --- |
| LIHTC treatment histories, baseline controls and tract-year panel | Four preparation notebooks in `code/data_process/` |
| LODES download and geographic distance preparation | `download_2010_2019_lodes.R`, `build_tract2010_points_from_tigerline.R`, `compute_od_pair_distance_from_shapefile_points.R` |
| Road-network commuting panel | `build_unique_tract_pairs_nodb.py` → `query_osrm_road_distances.py` → `merge_road_distance_batches.py` → `build_residence_panel_road.py` |
| Nearby/farther outcomes at 5, 10 and 20 km | `code/data_process/build_near_far_panel.R`, extracted from the original preparation block |
| Main state matching | `code/analysis/matching/main_state_guarded.R` |
| Main outcomes, wage tiers, commute and income heterogeneity | `code/analysis/main/estimate_core.R`, with `engine.R` |
| Construction intensity, primary-job RAC and nearby/farther regressions | `code/analysis/main/estimate_extensions.R` |
| Industry outcomes | `code/analysis/main/estimate_industry.R` |
| Primary WAC appendix | `download_primary_wac.R` and `code/analysis/main/estimate_primary_wac.R` |
| Spatial redistribution appendix | `code/analysis/spatial/estimate_guarded_regions.R` (final stage O), its matching/validation scripts and necessary preparation ancestors in `code/data_process/spatial/` |
| Main and appendix figures | `code/analysis/figures/`: event figures, wage/industry/commute figures, primary comparison, final balance and near/far figures |
| Final LaTeX tables | `code/analysis/figures/build.py` + `append_sections.py` generate the results preview; `export_paper_tables.py` is the actual manuscript table exporter |

## Run order

1. Download the sources below and run the preparation notebooks and LODES/geography scripts. Configure their input locations first. The older LIHTC/LODES layouts are now under `legacy_inputs/LIHTC` and `legacy_inputs/LODES`; those source layouts are not silently equated with the current analysis-input layout.
2. Prepare `data_panels/2010_2019_did_panel_with_seer.csv`, the road-distance/commute inputs and the primary-job data. Run the extracted `build_primary_rac_panel.R` and `build_near_far_panel.R` blocks after their inputs exist.
3. Run the main and spatial analysis, then figures:

```sh
bash code/analysis/run_main.sh
bash code/analysis/run_spatial.sh
bash code/analysis/run_figures.sh
```

The shell entrypoints keep source code in `code/` and generated results in `output/`; they do not download or recreate missing raw inputs. They are derived from the production commands, with updated source locations. `run_figures.sh` expects both main and spatial estimation outputs. The LaTeX export is written to `output/paper_assets/tables_figures.tex`; its manuscript-relative image paths are preserved for integration into the paper.

## Important input and dependency details

- `run_main.sh` needs the SEER-population panel, commute panel, primary RAC panel, primary WAC download chunks, near/far panel and industry employment inputs. Source scripts are present, but the original SEER merge code still has not been located; do not substitute another population denominator.
- The final spatial estimator uses guarded state matches. `data_process/spatial/legacy_county_pairs.R` is retained **only because original upstream geography code checks frozen county-pair inputs**. Its estimates are not the paper's final main results. Older spatial estimators, reports and alternative stages are excluded.
- The original 2010–2019 downloader's RAC/WAC sections are commented out; its active section downloads OD. Those commented source blocks and the panel notebooks document the research inputs, but an unattended full raw-data rebuild still needs that step configured. Raw and cleaned directory handoffs must be reconciled before running a national rebuild.
- OSRM requires a configured server and the research road-network vintage. The nationwide route computation and the complete regression suite were not rerun during this reorganization.

## Source data: where to download

| Source | Download location and selection | Used for |
| --- | --- | --- |
| LODES employment | [Census LODES 7 archive](https://lehd.ces.census.gov/data/lodes/LODES7/). Select state folders and years 2010–2019. Use OD `main` files and all jobs (`JT00`) for the within-state flow sample; RAC/WAC are separate inputs to the full paper. | Employment and residence–workplace flows |
| 2010 tract geography | [Census TIGER/Line 2010 tract downloads](https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010/). Obtain all county files needed for each state; retain the complete shapefile components after extraction. | Tract IDs, internal points, and geometric centroids |
| Road network | [Geofabrik U.S. extracts and historical files](https://download.geofabrik.de/north-america/us.html). Historical 2021 data are listed there. | OSRM road routing |
| LIHTC properties | [HUD LIHTC program data](https://www.huduser.gov/portal/datasets/lihtc.html), property-level database. Record the release date; retain construction type and placed-in-service timing. | Treatment definition and project scale |
| Baseline tract covariates | [Census 2006–2010 ACS 5-year API catalog](https://api.census.gov/data/2010/acs/acs5.html). Select tract-level tables. | Matching covariates in the full paper |
| Annual tract population | [NCI/SEER census tract population estimates](https://seer.cancer.gov/censustract-pops/), following the provider's request/access process. | Population denominator in the full paper |

## Software

R packages referenced: `MatchIt`, `Matrix`, `arrow`, `data.table`, `dplyr`, `fixest`, `lehdr`, `purrr`, `sf`, `tidyverse`.

Install Python packages with `pip install -r requirements.txt`. Jupyter is needed for the preparation/analysis notebooks.

Dependencies are not a fully pinned environment. See [Validation](VALIDATION.md) for what was and was not executed.

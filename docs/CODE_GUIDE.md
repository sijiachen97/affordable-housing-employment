# Affordable housing: code guide

All executable research code is under `code/`. `code/data_process/` constructs inputs; `code/analysis/` estimates models and produces tables/figures. Run commands from the repository root. The original research folders are unchanged.

The code is selected against the supplied final paper/slides and their production dependencies, rather than copied as an archive of every experiment. [Source manifest](SOURCE_MANIFEST.json) records original filenames, selected notebook cells, hashes and adaptations. [Source review](SOURCE_REVIEW.json) lists the reviewed source inventory and inclusion/exclusion decisions. No microdata, model caches or saved notebook outputs are shared.

## Final version and output correspondence


| Paper component | Included code |
| --- | --- |
| LIHTC treatment histories, baseline controls and tract-year panel | Numbered Python scripts `01`–`06` in `code/data_process/` |
| LODES download and geographic distance preparation | `download_lodes.R`, `build_tract2010_points_from_tigerline.R`, `compute_od_pair_distance_from_shapefile_points.R` |
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

Use `python code/replicate.py list` to see the ordered stages. You do not need to select individual scripts. Start from the repository root with Python and R installed:

```sh
python -m pip install -r requirements.txt
cp config/paths.example.json config/paths.local.json
python code/replicate.py run all --config config/paths.local.json --dry-run
```

Download the manually supplied sources below, edit input paths in the local config if needed, and then run stages in order:

```sh
python code/replicate.py run download-lodes
python code/replicate.py run seer --config config/paths.local.json
python code/replicate.py run panel --config config/paths.local.json
python code/replicate.py run geometry
# Start your OSRM server before routing; its map vintage affects exact replication.
export OSRM_URL=http://localhost:5000
python code/replicate.py run routing
python code/replicate.py run commuting
python code/replicate.py run primary-inputs
python code/replicate.py run main
python code/replicate.py run spatial
python code/replicate.py run figures
python code/replicate.py run verify
```

`check STAGE` reports missing inputs. `run STAGE` checks inputs and stops on command failure, saving logs under `output/replication_logs/`. `run all` performs the same sequence, but requires the manual downloads and running OSRM service first. This complete national sequence has **not** yet been rerun as a whole; see [Validation](VALIDATION.md).

The local config supports alternative raw inputs for the main panel. Keep output paths at their defaults for estimation: existing R models use the canonical `data_panels/` and `data_raw/` paths. Geometry and routing also use the canonical paths below. Do not point output paths at an original research archive.

### Manual input placement

- HUD: `data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv`.
- NHGIS: both `nhgis*_ds172_2010_tract.csv` (2010 SF1) and `nhgis*_ds176_20105_tract.csv` (2006–2010 ACS) under `data_raw/LIHTC/2010_census_data/data_raw/nhgis0004_csv/`. Keep source column names. Script `02_build_controls.py` lists the required table codes and fails if they are missing; an arbitrary ACS API extract is not a drop-in substitute.
- SEER: `data_raw/SEER_data/data_raw/us.2006_2023.tract.level.pops.txt`. Script `05` streams the original fixed-width file, scales population by 10,000, and aggregates age/race/sex counts. Script `06` left-joins them onto the baseline panel, preserving unmatched rows. Do not substitute a different population series.
- TIGER: extract 2010 tract shapefiles and their sidecar files under `data_raw/LODES/tiger2010_tract/unzipped/`.
- LODES: the download stage creates tract-level RAC/WAC/same-tract OD files and full within-state OD flows. It uses LODES 7, all jobs JT00, and the original state/year availability restrictions. Primary-job downloads run separately in `primary-inputs`.

### Outputs and checks

The main analysis panel is `data_panels/2010_2019_did_panel_with_seer.csv`. Main results are written to `output/research_extensions/28_paper_state_guarded_refresh/`; final spatial results to `output/research_extensions/23_spatial_spillover/stage_o/`; manuscript tables to `output/paper_assets/`.

`verify` compares main matched-pair-by-year coefficients, standard errors, p-values and sample sizes with archived production values in `reference/expected_main_results.csv`. It reports mismatches rather than changing estimates. This covers main aggregate result rows, not every spatial result or plotted point.

The final spatial estimator uses guarded state matches. `data_process/spatial/legacy_county_pairs.R` remains only because upstream geography code checks those inputs; it is not the final main estimator.

The original session log identifies the 2021 Geofabrik `us-210101.osm.pbf` map and MLD routing. Exact road-distance replication still requires confirmation of the OSRM image/build, extraction profile and map checksum; see [recovered routing configuration](OSRM_REPLICATION.md). Using an arbitrary current map can produce different distances. Route failures are missing distances, not zero commutes; intra-tract routes retain the source straight-line fallback.

## Source data: where to download

| Source | Download location and selection | Used for |
| --- | --- | --- |
| LODES employment | [Census LODES 7 archive](https://lehd.ces.census.gov/data/lodes/LODES7/). Select state folders and years 2010–2019. Use OD `main` files and all jobs (`JT00`) for the within-state flow sample; RAC/WAC are separate inputs to the full paper. | Employment and residence–workplace flows |
| 2010 tract geography | [Census TIGER/Line 2010 tract downloads](https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010/). Obtain all county files needed for each state; retain the complete shapefile components after extraction. | Tract IDs, internal points, and geometric centroids |
| Road network | [Geofabrik U.S. extracts and historical files](https://download.geofabrik.de/north-america/us.html). Historical 2021 data are listed there. | OSRM road routing |
| LIHTC properties | [HUD LIHTC program data](https://www.huduser.gov/portal/datasets/lihtc.html), property-level database. Record the release date; retain construction type and placed-in-service timing. | Treatment definition and project scale |
| Baseline tract covariates | [IPUMS NHGIS](https://www.nhgis.org/). Request tract-level 2010 SF1 and 2006–2010 ACS CSV extracts with the source table codes used in `02_build_controls.py`; account/extract preparation may be required. | Matching covariates in the full paper |
| Annual tract population | [NCI/SEER census tract population estimates](https://seer.cancer.gov/censustract-pops/), following the provider's request/access process. | Population denominator in the full paper |

## Software

R packages referenced: `MatchIt`, `Matrix`, `arrow`, `data.table`, `dplyr`, `fixest`, `lehdr`, `purrr`, `sf`, `tidyverse`.

Install Python packages with `pip install -r requirements.txt`. The selected notebook transformations are now numbered command-line scripts; Jupyter is not required.

Dependencies are not a fully pinned environment. See [Validation](VALIDATION.md) for what was and was not executed.

Recorded local software versions are in [environment.json](environment.json). They document the validation environment, not a fully locked cross-platform environment.

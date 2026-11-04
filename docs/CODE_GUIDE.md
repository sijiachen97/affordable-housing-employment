# Affordable housing, employment, and commuting

## Source data: where to download

Links checked November 4, 2026. Downloading these sources is not yet sufficient to reproduce the paper: the upstream processing and estimation steps listed below are not included in this repository.

| Source | Download location and selection | Used for |
| --- | --- | --- |
| LODES employment | [Census LODES 7 archive](https://lehd.ces.census.gov/data/lodes/LODES7/). Select state folders and years 2010–2019. Use OD `main` files and all jobs (`JT00`) for the within-state flow sample; RAC/WAC are separate inputs to the full paper. | Employment and residence–workplace flows |
| 2010 tract geography | [Census TIGER/Line 2010 tract downloads](https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010/). Obtain all county files needed for each state; retain the complete shapefile components after extraction. | Tract IDs, internal points, and geometric centroids |
| Road network | [Geofabrik U.S. extracts and historical files](https://download.geofabrik.de/north-america/us.html). Historical 2021 data are listed there. | OSRM road routing |
| LIHTC properties | [HUD LIHTC program data](https://www.huduser.gov/portal/datasets/lihtc.html), property-level database. Record the release date; retain construction type and placed-in-service timing. | Treatment definition in the full paper; not read by the current commuting scripts |
| Baseline tract covariates | [Census 2006–2010 ACS 5-year API catalog](https://api.census.gov/data/2010/acs/acs5.html). Select tract-level tables. | Matching covariates in the full paper |
| Annual tract population | [NCI/SEER census tract population estimates](https://seer.cancer.gov/censustract-pops/), following the provider's request/access process. | Population denominator in the full paper |

Do not substitute LODES 8/2020 boundaries for the LODES 7/2010 geography without a documented harmonization step. Preserve the exact release date and checksums of downloaded inputs. The precise historical OSM extract and OSRM build used for the research still need to be recorded; the year in the output filename alone is insufficient. SEER's county population download is not a substitute for tract population.

## Included research code

The repository now includes data-construction and main-analysis source in `research/`, in addition to the focused utilities described below. See [Research workflow](RESEARCH_WORKFLOW.md) for the file-by-file roles, execution order, and unresolved input handoffs. The earlier selection-only completeness inventory has been superseded by that workflow; full numerical replication has not been certified.

## Workflow

1. `build_unique_tract_pairs_nodb.py`: stream processed OD files, deduplicate residence–workplace tract pairs, attach tract coordinates, and calculate straight-line distances.
2. `query_osrm_road_distances.py`: query an OSRM routing service in parallel batches, saving checkpointed Parquet outputs with route success indicators.
3. `merge_road_distance_batches.py`: consolidate routing batches into a lookup.
4. `build_residence_panel_road.py`: join distances to employment flows and calculate employment-weighted commuting measures by residence tract and year.

## Inputs and execution

The pipeline expects upstream, processed inputs; it does not download or clean raw LODES files. Set `PROJECT_ROOT` to a prepared data directory containing:

- `data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both/od_full_<state>_<year>.parquet`
- `data_raw/LODES/OD_related/cache/tract2010_points_from_shapefile.parquet`

See each script for its input columns. Preserve tract identifiers as strings, including leading zeroes. A configured OSRM server and appropriate road-network extract are required for routing. The research uses a fixed road network, not historical annual road networks.

```sh
export PROJECT_ROOT=/path/to/prepared-data
python code/build_unique_tract_pairs_nodb.py
export INPUT_PATH="$PROJECT_ROOT/data_raw/LODES/OD_related/cache/unique_tract_pairs.parquet"
export OUTPUT_DIR=/path/to/routing-batches
export OSRM_URL=http://localhost:5000
python code/query_osrm_road_distances.py
export BATCHES_DIR="$OUTPUT_DIR"
export OUTPUT_PATH="$PROJECT_ROOT/data_raw/LODES/OD_related/cache/tract_pair_road_distance_2021.parquet"
python code/merge_road_distance_batches.py
python code/build_residence_panel_road.py
```

Failed routes are missing, not zero-distance commutes. Distance averages exclude missing distances and nonpositive weights; intra-tract pairs use the existing straight-line fallback. Interpretation therefore depends on route coverage and this fallback. Full national routing is resource-intensive and was not rerun for this portfolio.

# Affordable housing, employment, and commuting

This project studies neighborhood employment following Low-Income Housing Tax Credit development. It distinguishes jobs held by residents from jobs located in the neighborhood. The research combines HUD project records, LODES employment data, and population data, using matching and a staggered event-study design.

The selected code demonstrates a separate data-engineering component: constructing road-distance commuting measures from residence–workplace flows. These scripts do not estimate the event study. The nearby/distant job analysis uses straight-line distances; the road-distance measure here serves the commuting analysis.

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

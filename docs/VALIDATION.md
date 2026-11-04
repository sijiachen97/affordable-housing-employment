# Validation and remaining replication work

## Executed on November 4, 2026

- Rebuilt treatment histories from LIHTC records, baseline controls from NHGIS extracts, employment outcomes from existing tract-level LODES files, and the baseline tract-year panel. Joined the original saved SEER demographic aggregate with the newly reconstructed merge script.
- Compared all **729,060 rows and all columns** of the resulting panel with the archived paper input. Keys/order/schema matched; strings matched exactly and numeric comparisons passed at relative tolerance 1e-12 and absolute tolerance 1e-8.
- Preserved **3,780 rows with unmatched SEER population**, as in the archived panel. These were not imputed or dropped.
- Tested fixed-width population scaling/leading-zero identifiers using synthetic data, and rejection of duplicate panel keys without overwriting an existing output.
- Earlier checks found the three archived production figures `es_pooled_main_combined.pdf`, `es_pooled_commute.pdf`, and `primary_comparison.pdf` byte-for-byte identical to final manuscript assets.

The SEER aggregation source was located under `data_raw/SEER_data/scripts/` and is now included. The merge is a reconstructed, explicit left join validated against the original input, not a recovered original merge script.

## Not yet certified end to end

The 6.4 GB raw SEER file was not fully reaggregated in this pass; the real-data panel comparison used the saved aggregate. The revised national LODES downloader, nationwide OSRM routes, and complete matching/regression/figure sequence were not rerun. The original OSRM map extract, profile and version still need confirmation for exact commuting replication. Source data releases may have changed since the original analysis.

The `verify` stage provides archived aggregate targets for a future estimation run. A successful comparison against the archived file itself tests the comparator, not a fresh regression reproduction. No raw microdata or model caches are included.

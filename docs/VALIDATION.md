# Validation and remaining issues

Consolidation checks, November 4, 2026: 38 R files, 7 Python files, 4 notebooks (49 code cells), and 3 shell entrypoints passed syntax checks. Notebook outputs and execution counts were cleared. Source hashes and adapted-file hashes are in SOURCE_MANIFEST.json.

The following stage-28 production PDFs are byte-for-byte identical to the assets included in the final manuscript:

- `es_pooled_main_combined.pdf`
- `es_pooled_commute.pdf`
- `primary_comparison.pdf`

The original national routing, matching and regression suites were not rerun. The SEER merge source is still missing; preparation scripts also retain legacy directory handoffs and commented RAC/WAC download sections. These must be configured before claiming end-to-end raw-data replication. The selected spatial preparation includes older pair checks only as dependencies of the final stage-O calculation.

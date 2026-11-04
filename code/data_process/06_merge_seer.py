"""Reconstruct the final population merge; validate against the archived panel.

This is a new, explicit handoff, not a claim that the missing original merge
script was recovered. Original population aggregation is in 05_aggregate_seer.py.
"""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd
from support.paths import path, output


def normalize_ids(series):
    result = series.astype('string').str.replace(r'\.0$', '', regex=True).str.zfill(11)
    if not result.str.fullmatch(r'\d{11}').all():
        raise ValueError('Missing or invalid 2010 tract identifiers')
    return result


def merge_panel(base, population, destination, reference=None):
    demo = pd.read_csv(population, dtype={'tract_fips2010': 'string'})
    demo = demo[demo.year.between(2010, 2019)].copy()
    demo['tract_id'] = normalize_ids(demo.pop('tract_fips2010'))
    if demo.duplicated(['tract_id', 'year']).any():
        raise ValueError('Duplicate SEER tract-year keys')
    demo = demo.rename(columns={c: 'seer_' + c for c in demo if c not in ['tract_id', 'year']})
    population_columns = [c for c in demo if c.startswith('seer_')]
    reference_reader = None
    if reference:
        reference_reader = iter(pd.read_csv(reference, dtype={'tract_id': 'string'}, chunksize=100000))
    destination = Path(destination); destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + '.partial')
    rows = unmatched = 0
    seen = set()
    for chunk in pd.read_csv(base, dtype={'tract_id': 'string'}, chunksize=100000):
        chunk = chunk.loc[:, ~chunk.columns.str.startswith('Unnamed:')].copy()
        chunk['tract_id'] = normalize_ids(chunk.tract_id)
        keys = list(zip(chunk.tract_id, chunk.year))
        if len(set(keys)) != len(keys) or any(k in seen for k in keys):
            raise ValueError('Duplicate base-panel tract-year keys')
        seen.update(keys)
        if set(population_columns) & set(chunk):
            raise ValueError('Input panel already contains SEER fields')
        merged = chunk.merge(demo, on=['tract_id', 'year'], how='left', validate='one_to_one', sort=False)
        merged = merged.rename(columns={'state': 'state_x'})
        missing = int(merged.seer_total_population.isna().sum()); unmatched += missing
        # Preserve the published left join: missing population is retained, not filled or dropped.
        if reference_reader is not None:
            try:
                ref = next(reference_reader)
            except StopIteration as exc:
                raise ValueError('Reference has fewer rows than rebuilt panel') from exc
            ref['tract_id'] = normalize_ids(ref.tract_id)
            if list(merged.columns) != list(ref.columns) or not merged[['tract_id','year']].reset_index(drop=True).equals(ref[['tract_id','year']].reset_index(drop=True)):
                raise ValueError('Reference column set/order or row keys differ')
            for col in merged:
                if col in ['tract_id', 'state_x']:
                    same = merged[col].astype('string').reset_index(drop=True).equals(ref[col].astype('string').reset_index(drop=True))
                else:
                    same = np.allclose(pd.to_numeric(merged[col], errors='raise'), pd.to_numeric(ref[col], errors='raise'), rtol=1e-12, atol=1e-8, equal_nan=True)
                if not same:
                    raise ValueError(f'Reference mismatch in {col}, starting row {rows}')
        merged.to_csv(temporary, mode='w' if rows == 0 else 'a', header=rows == 0, index=False)
        rows += len(merged)
    if reference_reader is not None:
        try:
            next(reference_reader)
        except StopIteration:
            pass
        else:
            raise ValueError('Reference has extra rows')
    temporary.replace(destination)
    report = {'rows': rows, 'unmatched_population_rows': unmatched, 'reference_checked': bool(reference), 'all_columns_match_reference': True if reference else None}
    destination.with_suffix('.validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, help='Optional original final panel; compare every row/column before publishing output')
    args = parser.parse_args()
    merge_panel(path('base_panel'), path('seer_summary'), output('analysis_panel'), args.reference)

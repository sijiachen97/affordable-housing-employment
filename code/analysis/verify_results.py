"""Compare regenerated estimates with archived production results; no microdata required."""
from pathlib import Path
import csv, math, argparse
ROOT=Path(__file__).resolve().parents[2]
def load(path):
    with path.open() as f: rows=list(csv.DictReader(f))
    result={}
    for row in rows:
        key=tuple(row[k] for k in ['analysis','group','specification','outcome'])
        if key in result: raise ValueError('Duplicate result key: '+str(key))
        result[key]=row
    return result
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actual',type=Path,default=ROOT/'output/research_extensions/28_paper_state_guarded_refresh/all_att.csv')
    parser.add_argument('--rtol',type=float,default=1e-5)
    parser.add_argument('--atol',type=float,default=1e-8)
    args=parser.parse_args()
    expected=load(ROOT/'reference/expected_main_results.csv');actual=load(args.actual);errors=[]
    for key,row in expected.items():
        if key not in actual: errors.append(str(key)+': missing');continue
        for field in ['estimate','std_error','p_value','observations']:
            a,b=float(actual[key][field]),float(row[field])
            same=(a==b) if field=='observations' else math.isclose(a,b,rel_tol=args.rtol,abs_tol=args.atol)
            if not same: errors.append(f'{key}: {field}: actual={a}, expected={b}')
    for error in errors: print(error)
    print(f'Checked {len(expected)} matched-pair-year result rows; {len(errors)} mismatches.')
    return bool(errors)
if __name__=='__main__': raise SystemExit(main())

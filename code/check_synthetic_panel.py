"""Check weighted aggregation, failed routes, and intra-tract fallback using fake flows."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import numpy as np
import pandas as pd

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    od = root/'data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both'
    cache = root/'data_raw/LODES/OD_related/cache'
    od.mkdir(parents=True)
    cache.mkdir()
    df = pd.DataFrame({'h_tract': ['001']*3, 'w_tract': ['001', '002', '003'],
                       'year': [2019]*3, 'dist_centroid_km': [1., 8., 20.]})
    for col in ['S000','SA01','SA02','SA03','SE01','SE02','SE03','SI01','SI02','SI03']:
        df[col] = [2, 3, 5]
    df.to_parquet(od/'od_full_xx_2019.parquet', index=False)
    pd.DataFrame({'h_tract': ['001']*3, 'w_tract': ['001','002','003'],
                  'road_dist_km': [np.nan, 10., 99.], 'road_time_min': [np.nan,20.,99.],
                  'success': [0,1,0]}).to_parquet(cache/'tract_pair_road_distance_2021.parquet', index=False)
    subprocess.run([sys.executable, str(Path(__file__).with_name('build_residence_panel_road.py'))],
                   env={**os.environ,'PROJECT_ROOT':tmp}, check=True)
    row = pd.read_parquet(root/'data_panels/od_commute_panel_residence_road.parquet').iloc[0]
    assert row['h_tract'] == '001'
    assert np.isclose(row['avg_road_dist_from_s000'], 6.4)
    assert np.isclose(row['avg_road_time_from_s000'], 20.)
    assert row['total_s000'] == 10
    print('PASS: identifiers, weighted means, failed-route exclusion, and intra-tract fallback.')

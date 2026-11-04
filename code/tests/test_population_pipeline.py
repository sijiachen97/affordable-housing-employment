import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import pandas as pd

CODE = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(CODE))
spec = importlib.util.spec_from_file_location('seer_merge',CODE/'data_process/06_merge_seer.py')
module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class PopulationPipelineTests(unittest.TestCase):
    def test_fixed_width_scale_race_and_age(self):
        # Two different race/age groups, fractional population, same leading-zero tract.
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp);raw=tmp/'seer.txt';out=tmp/'sums.csv'
            raw.write_text('2010  '+'01'+'001'+'020100'+'1'+'1'+'06'+f'{12345:09d}'+'\n'+'2010  '+'01'+'001'+'020100'+'5'+'2'+'07'+f'{20000:09d}'+'\n')
            subprocess.run([sys.executable,str(CODE/'data_process/05_aggregate_seer.py'),'--input',str(raw),'--output',str(out)],check=True,capture_output=True)
            row=pd.read_csv(out,dtype={'tract_fips2010':str}).iloc[0]
            self.assertEqual(row.tract_fips2010,'01001020100')
            self.assertAlmostEqual(row.total_population,3.2345)
            self.assertAlmostEqual(row.age_under_29,1.2345)
            self.assertAlmostEqual(row.hispanic,2.0)

    def test_duplicate_input_cannot_replace_existing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp);base=tmp/'base.csv';demo=tmp/'demo.csv';dest=tmp/'result.csv'
            base.write_text('tract_id,year,state\n01001020100,2010,al\n01001020100,2010,al\n')
            demo.write_text('tract_fips2010,year,state,county,total_population\n01001020100,2010,01,001,3.2345\n')
            dest.write_text('keep existing completed output\n')
            with self.assertRaisesRegex(ValueError,'Duplicate base-panel'):
                module.merge_panel(base,demo,dest)
            self.assertEqual(dest.read_text(),'keep existing completed output\n')

if __name__=='__main__':unittest.main()

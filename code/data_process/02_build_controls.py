# Production cells extracted from data prep - 2010 census data (controls).ipynb; estimator and transformation rules unchanged.
from support.paths import path, output
# NHGIS 2010 Controls — Robust Merge via GISJOIN (Fix for 0-row merge)
# 
# Problem seen: inner merge on geoid11 returned 0 rows even though each side looked fine.
# Common cause: one file's GEOID construction differs (padding, missing, prefixed fields).
# 
# Solution: use NHGIS's native key **GISJOIN** to merge SF1 and ACS. It's present in both extracts
# and is the most robust join key across NHGIS files. We still compute geoid11 for downstream use.
# The script also prints diagnostics on key overlap so you can see what happened.
#
# Output: tract_controls_2010_from_nhgis.csv

import pandas as pd
from pathlib import Path

DATA_DIR = path('nhgis_dir')

sf1_path = next(DATA_DIR.glob("nhgis*_ds172_2010_tract.csv"))
acs_path = next(DATA_DIR.glob("nhgis*_ds176_20105_tract.csv"))
print(f"SF1 file: {sf1_path}")
print(f"ACS file: {acs_path}")

# --- helper to build geoid11 from components (fallback only) ---
def build_geoid11(df, state_col="STATEA", county_col="COUNTYA", tract_col="TRACTA"):
    s = df[state_col].astype(str).str.extract(r"(\d+)")[0].str.zfill(2)
    c = df[county_col].astype(str).str.extract(r"(\d+)")[0].str.zfill(3)
    t = df[tract_col].astype(str).str.extract(r"(\d+)")[0].str.zfill(6)
    return s + c + t

# =============================
# 1) Load SF1 2010 (ds172)
# =============================
sf1 = pd.read_csv(sf1_path, dtype=str)

# Ensure GISJOIN exists
if "GISJOIN" not in sf1.columns:
    raise KeyError("SF1 missing GISJOIN — please include 'GISJOIN' in NHGIS extract.")

# Numeric fields (will coerce errors to NaN)
need_sf1 = [
    # P1 Total population
    "H7V001",
    # P13 Median age (both sexes)
    "H77001",
    # H1 Housing units total; H3 Occupancy total & vacant
    "IFC001", "IFE001", "IFE003",
    # P3 Race total & White alone for minority share
    "H7X001", "H7X002",
]
for col in need_sf1:
    if col not in sf1.columns:
        raise KeyError(f"SF1 missing expected column: {col}")
    sf1[col] = pd.to_numeric(sf1[col], errors="coerce")

# Also keep the component codes to build GEOID later
for k in ["STATEA","COUNTYA","TRACTA"]:
    if k not in sf1.columns:
        raise KeyError(f"SF1 missing key column: {k}")

sf1["geoid11"] = build_geoid11(sf1)

sf1_keep = sf1[[
    "GISJOIN", "geoid11", "STATEA", "COUNTYA", "TRACTA",
    "H7V001", "H77001", "IFC001", "IFE001", "IFE003", "H7X001", "H7X002"
]].copy().rename(columns={
    "H7V001": "pop2010_total",
    "H77001": "median_age_2010",
    "IFC001": "housing_units_2010",
    "IFE001": "units_total_2010",
    "IFE003": "units_vacant_2010",
    "H7X001": "race_total_2010",
    "H7X002": "white_alone_2010",
})

sf1_keep["vacancy_rate_2010"] = (sf1_keep["units_vacant_2010"] / sf1_keep["units_total_2010"]).clip(0,1)
# Prefer P1 total for denominator; fallback to race_total
_den = sf1_keep["pop2010_total"].where(sf1_keep["pop2010_total"].notna(), sf1_keep["race_total_2010"]) 
sf1_keep["minority_share_2010"] = (1 - sf1_keep["white_alone_2010"].div(_den)).clip(0,1)

# =============================
# 2) Load ACS 2006–2010 (ds176)
# =============================
acs = pd.read_csv(acs_path, dtype=str)

if "GISJOIN" not in acs.columns:
    raise KeyError("ACS missing GISJOIN — please include 'GISJOIN' in NHGIS extract.")

need_acs = [
    # Median household income (B19013)
    "JOIE001",
    # Poverty: total denom & below-poverty numerator (B17021)
    "JOGE001", "JOGE002",
    # Education: total 25+ (B15002) and HS+/SomeCollege+ bins
    "JN9E001",
    "JN9E011","JN9E012","JN9E013","JN9E014","JN9E015","JN9E016","JN9E017","JN9E018",
    "JN9E028","JN9E029","JN9E030","JN9E031","JN9E032","JN9E033","JN9E034","JN9E035",
]
for col in need_acs:
    if col not in acs.columns:
        raise KeyError(f"ACS missing expected column: {col}")
    acs[col] = pd.to_numeric(acs[col], errors="coerce")

# Compute controls
acs["median_hh_income_2010"] = acs["JOIE001"]
acs["poverty_status_total_2010"] = acs['JOGE001']
acs["poverty_rate_2010"] = (acs["JOGE002"] / acs["JOGE001"]).clip(0,1)

male_hsplus = acs[["JN9E011","JN9E012","JN9E013","JN9E014","JN9E015","JN9E016","JN9E017","JN9E018"]].sum(axis=1, skipna=True)
fem_hsplus  = acs[["JN9E028","JN9E029","JN9E030","JN9E031","JN9E032","JN9E033","JN9E034","JN9E035"]].sum(axis=1, skipna=True)
acs["share_high_school_or_higher_2010"] = ((male_hsplus + fem_hsplus) / acs["JN9E001"]).clip(0,1)

male_baplus = acs[["JN9E015","JN9E016","JN9E017","JN9E018"]].sum(axis=1, skipna=True)
fem_baplus  = acs[["JN9E032","JN9E033","JN9E034","JN9E035"]].sum(axis=1, skipna=True)
acs["share_bachelor_or_higher_2010"] = ((male_baplus + fem_baplus) / acs["JN9E001"]).clip(0,1)

acs_keep = acs[[
    "GISJOIN",
    "median_hh_income_2010", "poverty_status_total_2010", "poverty_rate_2010",
    "share_high_school_or_higher_2010", "share_bachelor_or_higher_2010"
]].copy()

# =============================
# 3) Diagnostics on keys & merge via GISJOIN
# =============================
# Basic counts
print(f"SF1 rows: {len(sf1_keep):,}; ACS rows: {len(acs_keep):,}")

# Key overlap
sf1_keys = set(sf1_keep["GISJOIN"].dropna().unique())
acs_keys = set(acs_keep["GISJOIN"].dropna().unique())
intersect = sf1_keys & acs_keys
print(f"GISJOIN overlap: {len(intersect):,} (SF1 unique: {len(sf1_keys):,}; ACS unique: {len(acs_keys):,})")

# Show a small sample of non-overlapping keys (if any)
miss_in_acs = list(sf1_keys - acs_keys)[:5]
miss_in_sf1 = list(acs_keys - sf1_keys)[:5]
if miss_in_acs:
    print("Example GISJOIN present in SF1 but not ACS:", miss_in_acs)
if miss_in_sf1:
    print("Example GISJOIN present in ACS but not SF1:", miss_in_sf1)

# Merge
controls_2010 = (sf1_keep.merge(acs_keep, on="GISJOIN", how="inner")
                          .rename(columns={"geoid11":"geoid"}))

print(f"Merged rows: {len(controls_2010):,}")

# Final tidy & save
num_cols = [c for c in controls_2010.columns if c not in ["GISJOIN","geoid","STATEA","COUNTYA","TRACTA"]]
for c in num_cols:
    controls_2010[c] = pd.to_numeric(controls_2010[c], errors="coerce")

    
# ===============.  Save file .============================
out_path = output('controls_csv')
controls_2010.to_csv(out_path, index=False)
print(f"Saved {len(controls_2010):,} tracts → {out_path}")
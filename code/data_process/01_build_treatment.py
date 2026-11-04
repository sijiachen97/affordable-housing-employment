# Production cells extracted from data prep - lihtc property.ipynb; estimator and transformation rules unchanged.
from support.paths import path, output
# Step 1 (revised): LIHTC tract×year treatment panel
# Cumulative units from full history (1987→), but analysis window 2010–2019
# --------------------------------------------------------------------------------
# Fix: corrected parentheses on `treated` assignment to avoid syntax error

import pandas as pd
import numpy as np
from pathlib import Path

LIHTC_PATH = path('lihtc_csv')
OUT_DIR = path('treatment_dir')
OUT_DIR.mkdir(parents=True, exist_ok=True)

YEAR_MIN, YEAR_MAX = 2010, 2019

def as_int(s):
    return pd.to_numeric(s, errors="coerce").astype("Int64")

import pandas as pd

def clean_fips2010(s: pd.Series) -> pd.Series:
    """Return valid 11-digit 2010 tract GEOIDs or NA. Never fabricate by padding."""
    raw = s.astype(str).str.strip()
    digits = raw.str.replace(r"\D", "", regex=True)

    # Must be exactly 11 digits
    mask11 = digits.str.len() == 11

    # Plausibility checks
    state  = pd.to_numeric(digits.str[:2], errors="coerce")
    county = digits.str[2:5]
    tract  = digits.str[5:11]

    valid_state  = state.between(1, 56, inclusive="both")
    valid_county = county.ne("000")
    valid_tract  = tract.ne("000000")

    valid = mask11 & valid_state & valid_county & valid_tract
    out = digits.where(valid)
    return out.astype("string")


raw = pd.read_csv(LIHTC_PATH, dtype=str, low_memory=False)
raw.columns = raw.columns.str.strip().str.upper()

for c in ["FIPS2010","YR_PIS","TYPE"]:
    if c not in raw.columns:
        raise ValueError(f"Missing required column: {c}")

tract = clean_fips2010(raw["FIPS2010"])
pis   = as_int(raw["YR_PIS"]).where(lambda s: ~s.isin([8888,9999]))
ctype = raw["TYPE"].astype(str).str.strip()

def pull(col):
    return as_int(raw[col]) if col in raw.columns else pd.Series(pd.NA, index=raw.index, dtype="Int64")

n_units = pull("N_UNITS")
li_units = pull("LI_UNITS")
n0 = pull("N_0BR"); n1 = pull("N_1BR"); n2 = pull("N_2BR"); n3 = pull("N_3BR"); n4 = pull("N_4BR")

prop = pd.DataFrame({
    "tract_id": tract,
    "pis_year": pis,
    "type": ctype,
    "n_units": n_units,
    "li_units": li_units,
    "n_0br": n0,
    "n_1br": n1,
    "n_2br": n2,
    "n_3br": n3,
    "n_4br": n4,
}).dropna(subset=["tract_id"])

prop = prop.loc[prop["type"].eq("1")].copy()
prop = prop.loc[prop["pis_year"].notna()].copy()
prop["year"] = prop["pis_year"].astype(int)

flows_all = (
    prop.groupby(["tract_id","year"], as_index=False)
        .agg(
            n_new_projects=("year","size"),
            n_new_units_total=("n_units", lambda s: s.fillna(0).astype("Int64").sum()),
            n_new_units_li=("li_units", lambda s: s.fillna(0).astype("Int64").sum()),
            br0_new_units=("n_0br", lambda s: s.fillna(0).astype("Int64").sum()),
            br1_new_units=("n_1br", lambda s: s.fillna(0).astype("Int64").sum()),
            br2_new_units=("n_2br", lambda s: s.fillna(0).astype("Int64").sum()),
            br3_new_units=("n_3br", lambda s: s.fillna(0).astype("Int64").sum()),
            br4_new_units=("n_4br", lambda s: s.fillna(0).astype("Int64").sum()),
        )
)

first_pis = flows_all.groupby("tract_id", as_index=False)["year"].min().rename(columns={"year":"first_pis_year"})

years_win = pd.DataFrame({"year": np.arange(YEAR_MIN, YEAR_MAX+1, dtype=int)})
tracts = first_pis[["tract_id"]].drop_duplicates()
panel = tracts.merge(years_win, how="cross")

panel = panel.merge(flows_all, on=["tract_id","year"], how="left")
for c in ["n_new_projects","n_new_units_total","n_new_units_li","br0_new_units","br1_new_units","br2_new_units","br3_new_units","br4_new_units"]:
    if c in panel.columns:
        panel[c] = panel[c].fillna(0).astype("Int64")

panel = panel.merge(first_pis, on="tract_id", how="left")
panel["ever_treated"] = panel["first_pis_year"].notna().astype("Int64")

if not flows_all.empty:
    year_min_global = int(flows_all["year"].min())
else:
    year_min_global = YEAR_MIN

grid_full = (
    tracts.merge(pd.DataFrame({"year": np.arange(year_min_global, YEAR_MAX+1, dtype=int)}), how="cross")
          .merge(flows_all, on=["tract_id","year"], how="left")
          .fillna({"n_new_units_total":0, "n_new_units_li":0})
          .sort_values(["tract_id","year"]).reset_index(drop=True)
)

grid_full["n_units_total_cum_full"] = grid_full.groupby("tract_id")["n_new_units_total"].cumsum().astype("Int64")
grid_full["n_units_li_cum_full"]    = grid_full.groupby("tract_id")["n_new_units_li"].cumsum().astype("Int64")

panel = panel.merge(
    grid_full.loc[grid_full["year"].between(YEAR_MIN, YEAR_MAX),
                  ["tract_id","year","n_units_total_cum_full","n_units_li_cum_full"]],
    on=["tract_id","year"], how="left"
)

panel = panel.sort_values(["tract_id","year"]).reset_index(drop=True)
panel["event_time"] = (panel["year"] - panel["first_pis_year"]).where(panel["ever_treated"].astype(bool))
panel["treated"] = ((panel["ever_treated"] == 1) & (panel["year"] >= panel["first_pis_year"]))
panel["treated"] = panel["treated"].astype("Int64")

cols = [
    "tract_id","year","first_pis_year","ever_treated","event_time","treated",
    "n_new_projects","n_new_units_total","n_new_units_li",
    "br0_new_units","br1_new_units","br2_new_units","br3_new_units","br4_new_units",
    "n_units_total_cum_full","n_units_li_cum_full"
]
cols = [c for c in cols if c in panel.columns]
lihtc_treatment_panel_fullcum = panel[cols].copy()

out = OUT_DIR / f"lihtc_treatment_panel_newbuild_fullcum_2010_2019.csv"
lihtc_treatment_panel_fullcum.to_csv(out, index=False)
print("Saved:", out)
print(lihtc_treatment_panel_fullcum.head().to_string(index=False))
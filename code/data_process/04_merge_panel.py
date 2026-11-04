# Production cells extracted from data prep - merge panels (LIHTC + ACS + LODES).ipynb; estimator and transformation rules unchanged.
from support.paths import path, output
import pandas as pd

# File paths
lihtc_fp = path('treatment_dir') / 'lihtc_treatment_panel_newbuild_fullcum_2010_2019.csv'
controls_fp = path('controls_csv')
lodes_fp = path('employment_panel')

# Load datasets
lihtc = pd.read_csv(lihtc_fp, dtype={"tract_id": str})
controls = pd.read_csv(controls_fp)
lodes = pd.read_parquet(lodes_fp)

# -------------------------
# Standardize keys
# -------------------------
# IDs to 11-digit strings
def z11(x): return x.astype(str).str.zfill(11)

lodes["tract_id"] = z11(lodes["tract_id"])
lihtc["tract_id"] = z11(lihtc["tract_id"])
controls["geoid"] = z11(controls["geoid"])

# Year to int
lodes["year"] = lodes["year"].astype(int)
lihtc["year"] = lihtc["year"].astype(int)

# -------------------------
# Build panel (base = LODES so untreated tracts remain)
# -------------------------
panel = lodes.merge(
    lihtc,
    on=["tract_id", "year"],
    how="left",
    validate="m:1"  # many LODES rows to at most 1 LIHTC row per tract-year
).merge(
    controls,
    left_on="tract_id", right_on="geoid",
    how="left",
    validate="m:1"
).drop(columns=["geoid"])  # keep only tract_id

# -------------------------
# Fill sensible defaults for untreated years
# -------------------------
# These should be zeros when no LIHTC activity that year / ever
zero_cols = [
    "ever_treated", "treated",
    "n_new_projects", "n_new_units_total", "n_new_units_li",
    "br0_new_units", "br1_new_units", "br2_new_units", "br3_new_units", "br4_new_units",
    "n_units_total_cum_full", "n_units_li_cum_full"
]
for c in zero_cols:
    if c in panel.columns:
        panel[c] = panel[c].fillna(0).astype(int)

# Keep timing as NA for never-treated
for c in ["first_pis_year", "event_time"]:
    if c in panel.columns:
        # leave as NA if missing
        panel[c] = panel[c].astype("Int64")

# -------------------------
# Optional: restrict to 2010–2019 if needed (LODES should already be)
# -------------------------
panel = panel[(panel["year"] >= 2010) & (panel["year"] <= 2019)].copy()

# -------------------------
# Order columns for analysis ergonomics
# -------------------------
id_cols = ["tract_id", "year"]

treat_core = [c for c in ["ever_treated","treated","event_time","first_pis_year"] if c in panel.columns]
treat_intensity = [c for c in [
    "n_new_projects","n_new_units_total","n_new_units_li",
    "br0_new_units","br1_new_units","br2_new_units","br3_new_units","br4_new_units",
    "n_units_total_cum_full","n_units_li_cum_full"
] if c in panel.columns]

# All LODES outcome cols (keep existing order as much as possible)
lodes_outcome_prefixes = ("rac_", "wac_", "od_")
lodes_cols = [c for c in panel.columns if c.startswith(lodes_outcome_prefixes)]

# Controls (2010 cross-section, repeated by year)
control_cols = [
    "pop2010_total","median_age_2010","housing_units_2010","units_total_2010","units_vacant_2010",
    "race_total_2010","white_alone_2010","vacancy_rate_2010","minority_share_2010",
    "median_hh_income_2010","poverty_status_total_2010","poverty_rate_2010",
    "share_high_school_or_higher_2010","share_bachelor_or_higher_2010",
    "STATEA","COUNTYA","TRACTA","GISJOIN"
]
control_cols = [c for c in control_cols if c in panel.columns]

# Everything else (to append at the end)
keep_order = id_cols + treat_core + treat_intensity + lodes_cols + control_cols
other_cols = [c for c in panel.columns if c not in keep_order]
panel = panel[keep_order + other_cols]

# -------------------------
# Basic diagnostics (printed)
# -------------------------
n_rows = len(panel)
n_tracts = panel["tract_id"].nunique()
n_treated = panel.groupby("tract_id")["ever_treated"].max().sum() if "ever_treated" in panel.columns else pd.NA

print(f"Panel rows: {n_rows:,}")
print(f"Unique tracts: {n_tracts:,}")
print(f"Treated tracts (ever): {int(n_treated) if pd.notna(n_treated) else 'NA'}")

# Check duplicates
dups = panel.duplicated(subset=["tract_id","year"]).sum()
print("Duplicate tract_id-year rows:", dups)

# # -------------------------
# # Save
# # -------------------------
# panel.to_parquet(2010_2019_tract_panel_parquet, index=False)
# panel.to_csv(2010_2019_tract_panel_csv, index=False)

# print("Saved:")
# print(" -", 2010_2019_tract_panel_parquet)
# print(" -", 2010_2019_tract_panel_csv)

# -------------------------
# (Optional) Handy weights & scales for later regressions
# Uncomment if useful:
# if "pop2010_total" in panel.columns:
#     panel["weight_pop2010"] = panel["pop2010_total"].clip(lower=1)
#     # Example intensity per 1k residents:
#     if "n_new_units_total" in panel.columns:
#         panel["n_new_units_per_1k"] = 1000 * panel["n_new_units_total"] / panel["weight_pop2010"]


panel = panel.rename(columns = str.lower)

# Move [STATEA, COUNTYA, TRACTA] (and optionally state) right after [tract_id, year]
move_after = ['state', "statea", "countya", "tracta"]

    

# Reorder columns: keep everything else in original order
cols = list(panel.columns)

# Find indices
id_pos = cols.index("year") + 1  # insert after 'year'
for c in reversed(move_after):   # reverse to maintain order when inserting
    if c in cols:
        cols.insert(id_pos, cols.pop(cols.index(c)))

# Reorder panel
panel = panel[cols]


panel = panel.rename(columns={'pop2010_total': 'pop_total_2010', 'white_alone_2010': 'white_alone_pop_2010'})
panel = panel.rename(columns={'n_units_total_cum_full': 'n_units_total_cum_1987_onwards', 'n_units_li_cum_full': 'n_units_li_cum_1987_onwards'})
panel = panel.rename(columns={'od_same_total': 'od_same_tract_commute_total'})


# Columns to rename
acs_cols = [
    'pop_total_2010','median_age_2010','housing_units_2010','units_total_2010',
    'units_vacant_2010','white_alone_pop_2010','vacancy_rate_2010',
    'minority_share_2010','median_hh_income_2010','poverty_status_total_2010',
    'poverty_rate_2010','share_bachelor_or_higher_2010',
    'share_some_college_or_higher_2010'
]

# Keep only those that exist in panel
acs_cols = [c for c in acs_cols if c in panel.columns]

# Build rename dictionary: remove "_2010", then prefix "acs2010_"
rename_map = {c: "acs2010_" + c.replace("_2010", "") for c in acs_cols}


# Apply renaming
panel = panel.rename(columns=rename_map)

to_drop = ["gisjoin", "race_total_2010", "acs2010_units_total"]
# Drop GISJOIN if present
for col in to_drop:
    if col in panel.columns:
        panel = panel.drop(columns= col)


# Optional check
print(panel.columns)  # preview columns



assert not panel.duplicated(['tract_id', 'year']).any(), 'Duplicate tract-year keys'
panel.to_csv(output('base_panel'), index=False)
# Production cells extracted from data prep - merge lodes outcomes.ipynb; estimator and transformation rules unchanged.
from support.paths import path, output
"""
LODES outcome builders in Python
- Mirrors your R logic for RAC, WAC, and OD
- Uses pandas; expects Parquet inputs with 2010-tract GEOIDs
- Industry buckets reflect the revised mapping:
  * Construction & Real Estate: CNS04 (NAICS 23), CNS11 (NAICS 53)
  * Local Services: CNS07 (Retail), CNS08 (Transport/Warehouse), CNS16 (Health),
                    CNS18 (Accommodation/Food), CNS19 (Other Services),
                    CNS14 (Admin & Support, Waste Mgmt)
  * Professional / High-Skill / Tradable: CNS09 (Information), CNS10 (Finance),
                    CNS12 (Prof/Tech), CNS13 (Management), CNS15 (Education)
  * Goods / Wholesale / Public / Regional: CNS01 (Ag), CNS02 (Mining), CNS03 (Utilities),
                    CNS05 (Manufacturing), CNS06 (Wholesale), CNS17 (Arts/Ent/Rec),
                    CNS20 (Public Admin)
- Race buckets: White alone (CR01), Minorities (CR02+CR03+CR04+CR05+CR07)
- Education buckets: less than HS (CD01), HS only (CD02), some college or BA+ (CD03+CD04), HS+ (CD02+CD03+CD04)

Note: Some columns might be absent depending on the pull. The helpers below treat
missing columns as zeros when summing.
"""

import pandas as pd
from typing import List

# -----------------------------
# Helpers
# -----------------------------

def _normalize_id_year(df: pd.DataFrame) -> pd.DataFrame:
    """Ensure join keys have consistent dtypes:
    - tract_id as 11-char zero-padded string (2010 tract GEOID)
    - year as int32
    """
    tract_cols = ["tract_id", "geoid", "h_tract", "w_tract"]
    tcol = None
    for c in tract_cols:
        if c in df.columns:
            tcol = c
            break
    if tcol is None:
        raise KeyError("No tract id column found among: tract_id/geoid/h_tract/w_tract")

    df["tract_id"] = (
        df[tcol]
        .astype(str)
        .str.replace(r"\.0$", "", regex=True)
        .str.replace(r"[^0-9]", "", regex=True)
        .str.zfill(11)
    )

    if "year" not in df.columns:
        raise KeyError("Expected 'year' in dataframe")
    df["year"] = df["year"].astype("int32", copy=False)
    return df


def _safe_sum(df: pd.DataFrame, cols: List[str]) -> pd.Series:
    existing = [c for c in cols if c in df.columns]
    if not existing:
        return pd.Series(0, index=df.index)
    return df[existing].sum(axis=1)


def build_industry_buckets(df: pd.DataFrame, prefix: str) -> pd.DataFrame:
    out = pd.DataFrame(index=df.index)
    out[f"{prefix}ind_constr_realest"] = _safe_sum(df, ["CNS04", "CNS11"])
    out[f"{prefix}ind_local_services"] = _safe_sum(df, ["CNS07", "CNS08", "CNS16","CNS17", "CNS18", "CNS19", "CNS14"])
    out[f"{prefix}ind_professional"] = _safe_sum(df, ["CNS09", "CNS10", "CNS12", "CNS13", "CNS15"])
    out[f"{prefix}ind_goods_public"] = _safe_sum(df, ["CNS01", "CNS02", "CNS03", "CNS05", "CNS06", "CNS20"])
    return out


def build_race_buckets(df: pd.DataFrame, prefix: str) -> pd.DataFrame:
    out = pd.DataFrame(index=df.index)
    out[f"{prefix}race_white"] = df.get("CR01", 0)
    out[f"{prefix}race_minorities"] = _safe_sum(df, ["CR02", "CR03", "CR04", "CR05", "CR07"])
    return out


def build_edu_buckets(df: pd.DataFrame, prefix: str) -> pd.DataFrame:
    out = pd.DataFrame(index=df.index)
    out[f"{prefix}edu_le_hs"] = df.get("CD01", 0)
    out[f"{prefix}edu_hs_+"] = _safe_sum(df, ["CD02", "CD03", "CD04"])
    out[f"{prefix}edu_somecoll_or_ba+"] = _safe_sum(df, ["CD03", "CD04"])
    return out

def build_age_buckets(df: pd.DataFrame, prefix: str) -> pd.DataFrame:
    """Age groups from LODES CA01..CA03
    CA01: Age 29 or younger, CA02: 30–54, CA03: 55 or older
    """
    out = pd.DataFrame(index=df.index)
    out[f"{prefix}age_u29"]   = df.get("CA01", 0)
    out[f"{prefix}age_30_54"] = df.get("CA02", 0)
    out[f"{prefix}age_55p"]   = df.get("CA03", 0)
    return out

def build_earn_buckets(df: pd.DataFrame, prefix: str) -> pd.DataFrame:
    """Earnings groups from LODES CE01..CE03
    CE01: ≤ $1250/month, CE02: $1251–$3333, CE03: ≥ $3333
    """
    out = pd.DataFrame(index=df.index)
    out[f"{prefix}earn_le_1250"]   = df.get("CE01", 0)
    out[f"{prefix}earn_1251_3333"] = df.get("CE02", 0)
    out[f"{prefix}earn_ge_3333"]   = df.get("CE03", 0)
    return out



def construct_outcomes(df: pd.DataFrame, kind: str) -> pd.DataFrame:
    kind = kind.lower()
    assert kind in {"rac", "wac"}

    # normalize IDs/dtypes and keep state if present
    df = _normalize_id_year(df.copy())
    base_cols = [c for c in ["tract_id", "year", "state"] if c in df.columns]
    base = df[base_cols].copy()
    base[f"{kind}_total"] = df.get("C000", 0)

    # Buckets (with prefixes so RAC vs WAC never collide)
    ind  = build_industry_buckets(df, f"{kind}_")
    race = build_race_buckets(df, f"{kind}_")
    edu  = build_edu_buckets(df, f"{kind}_")
    age  = build_age_buckets(df, f"{kind}_")
    earn = build_earn_buckets(df, f"{kind}_")

    out = pd.concat([base, ind, race, edu, age, earn], axis=1)
    return out



def construct_outcomes_od(od_df: pd.DataFrame) -> pd.DataFrame:
    if {"tract_id", "year"}.issubset(od_df.columns):
        od_df = od_df.copy()
        od_df["tract_id"] = (
            od_df["tract_id"].astype(str)
            .str.replace(r"\.0$", "", regex=True)
            .str.replace(r"[^0-9]", "", regex=True)
            .str.zfill(11)
        )
        od_df["year"] = od_df["year"].astype("int32", copy=False)

    cols = set(od_df.columns)

    if {"tract_id", "year", "od_same_total"}.issubset(cols):
        out = od_df[["tract_id", "year", "od_same_total"]].copy()
        out = out.rename(columns={"od_same_total": "od_same_total_prefixed"})
        out = out.rename(columns={"od_same_total_prefixed": "od_same_total"})
        out["od_same_total"] = out["od_same_total"]
        out = out.rename(columns={"od_same_total": "od_same_total"})
        out = out.rename(columns={"od_same_total": "od_same_total"})
        out["od_same_total"] = out["od_same_total"]
        out = out.rename(columns={"od_same_total": "od_same_total"})
        out["tract_id"] = out["tract_id"].astype(str)
        return out.sort_values(["tract_id", "year"]).reset_index(drop=True)

    if ("S000" in cols) and ("year" in cols) and ("h_geoid" in cols or "h_geocode" in cols) and not ({"w_geoid", "w_geocode"} & cols):
        hcol = "h_geoid" if "h_geoid" in cols else "h_geocode"
        out = od_df[[hcol, "year", "S000"]].rename(columns={hcol: "tract_id", "S000": "od_same_total"}).copy()
        out["tract_id"] = out["tract_id"].astype(str)
        return out.sort_values(["tract_id", "year"]).reset_index(drop=True)

    hcol = "h_geoid" if "h_geoid" in cols else ("h_geocode" if "h_geocode" in cols else None)
    wcol = "w_geoid" if "w_geoid" in cols else ("w_geocode" if "w_geocode" in cols else None)
    if hcol is None or wcol is None:
        raise KeyError(f"OD columns not found. Have: {sorted(cols)}")

    if "year" not in cols:
        raise KeyError("Expected 'year' column in OD dataframe")

    temp = od_df[[hcol, wcol, "S000", "year"]].copy()
    same = temp[temp[hcol] == temp[wcol]].copy()
    same = same.rename(columns={hcol: "tract_id"})
    same = same.groupby(["tract_id", "year"], as_index=False)["S000"].sum()
    same = same.rename(columns={"S000": "od_same_total"})
    same["tract_id"] = (
        same["tract_id"].astype(str)
        .str.replace(r"\.0$", "", regex=True)
        .str.replace(r"[^0-9]", "", regex=True)
        .str.zfill(11)
    )
    same["year"] = same["year"].astype("int32", copy=False)
    return same.sort_values(["tract_id", "year"]).reset_index(drop=True)

if __name__ == "__main__":
    import os

    base_dir = str(path('lodes_dir'))

    rac_raw = pd.read_parquet(os.path.join(base_dir, "lodes_rac_outcomes_tract2010_2010_2019.parquet"))
    wac_raw = pd.read_parquet(os.path.join(base_dir, "lodes_wac_outcomes_tract2010_2010_2019.parquet"))

    od_path_file = os.path.join(base_dir, "lodes_od_same_tract2010_2010_2019.parquet")
    if os.path.exists(od_path_file):
        od_raw = pd.read_parquet(od_path_file)
    else:
        raise FileNotFoundError("OD parquet not found: expected 'lodes_od_same_tract2010_2010_2019.parquet'")

    rac_out = construct_outcomes(rac_raw, kind="rac")
    wac_out = construct_outcomes(wac_raw, kind="wac")
    od_out  = construct_outcomes_od(od_raw)

    panel = (
        rac_out.merge(wac_out, on=["tract_id","state","year"], how="outer")
               .merge(od_out,  on=["tract_id","year"], how="outer")
               .sort_values(["tract_id","year"]).reset_index(drop=True)
    )

    out_path = output('employment_panel')
    panel.to_parquet(out_path, index=False)
    print("Saved:", out_path, "Rows:", len(panel))
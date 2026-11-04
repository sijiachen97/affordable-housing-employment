library(lehdr)
library(dplyr)
library(purrr)
library(data.table)
library(arrow)

# Force outputs into the LODES project directory
setwd("./legacy_inputs/LODES")

# 50 states + DC; exclude PR and USVI for OD/WAC (they're not in regular production)
all_states <- c(
  "al","ak","az","ar","ca","co","ct","de","dc","fl","ga",
  "hi","id","il","in","ia","ks","ky","la","me","md","ma","mi",
  "mn","ms","mo","mt","ne","nv","nh","nj","nm","ny","nc","nd",
  "oh","ok","or","pa","ri","sc","sd","tn","tx","ut","vt","va",
  "wa","wv","wi","wy"
)

# ------------------------------
# 1) Year ranges by state (OD/WAC)
# ------------------------------
years_wac_od <- function(st) {
  # Default: full 2010–2019
  yrs <- 2010:2019
  # Exceptions per tech doc (OD/WAC not available in these state-years):
  if (st == "ak") yrs <- 2010:2016         # Alaska: 2017–2019 missing
  if (st == "ar") yrs <- 2010:2018         # Arkansas: 2019 missing
  if (st == "ms") yrs <- 2010:2018         # Mississippi: 2019 missing
  if (st == "ma") yrs <- 2011:2019         # Massachusetts: 2010 missing
  yrs
}

# # ------------------------------
# # 2) RAC years (simpler): 2010–2019 for all states we keep
# # ------------------------------
# years_rac <- 2010:2019
# 
# # ------------------------------
# # 3) Thin wrappers for lehdr pulls (LODES7 -> 2010 tracts)
# # ------------------------------
# get_rac <- function(st) {
#   grab_lodes(state = st, year = years_rac,
#              lodes_type = "rac", job_type = "JT00", segment = "S000",
#              agg_geo = "tract", state_part = "main", version = "LODES7") |>
#     mutate(state = st)
# }
# 
# get_wac <- function(st) {
#   yrs <- years_wac_od(st)
#   if (length(yrs) == 0) return(dplyr::tibble())  # safety
#   grab_lodes(state = st, year = yrs,
#              lodes_type = "wac", job_type = "JT00", segment = "S000",
#              agg_geo = "tract", state_part = "main", version = "LODES7") |>
#     mutate(state = st)
# }
# 
# 
# # ------------------------------
# # 4) Download without 404s
# # ------------------------------
# rac_raw <- map_dfr(all_states, get_rac)
# write_parquet(rac_raw, "lodes_rac_outcomes_tract2010_2010_2019.parquet")
# 
# wac_raw <- map_dfr(all_states, get_wac)
# write_parquet(wac_raw, "lodes_wac_outcomes_tract2010_2010_2019.parquet")
# 
# # ------------------------------
# # 5) OD Pipeline
# # ------------------------------
# 
# # ---- Output directory for small OD Parquet chunks ----
# dir.create("out_od_parquet", showWarnings = FALSE)
# 
# 
# # ---- Streamed OD downloader → same-tract collapse → Parquet writer ----
# process_od_state_yearly <- function(st) {
#   yrs <- years_wac_od(st)
#   if (!length(yrs)) return(invisible(NULL))
#   for (yr in yrs) {
#     message(sprintf("[OD] %s %d", st, yr))
#     
#     
#     # Pull a single state-year to keep memory small
#     od_one <- grab_lodes(
#       state = st, year = yr,
#       lodes_type = "od", job_type = "JT00", segment = "S000",
#       agg_geo = "tract", state_part = "main", version = "LODES7"
#     )
#     
#     
#     # Drop extra columns early to reduce RAM, then same-tract aggregate
#     # data.table syntax for speed
#     od_small <- as.data.table(od_one)[, .(h_tract, w_tract, S000, year)]
#     od_same <- od_small[h_tract == w_tract,
#                         .(tract_id = h_tract,
#                           year,
#                           od_same_total = sum(S000)),
#                         by = .(h_tract, year)][, .(tract_id, year, od_same_total)]
#     
#     
#     # Write one Parquet per state-year
#     write_parquet(od_same,
#                   sink = sprintf("out_od_parquet/od_same_%s_%d.parquet", st, yr))
#     
#     
#     # Clean up
#     rm(od_one, od_small, od_same); gc()
#   }
# }
# 
# 
# # ---- Run the streamed writer over all states ----
# invisible(lapply(all_states, process_od_state_yearly))
# 
# 
# # ---- Bind OD back together from Parquet chunks ----
# # (This keeps the in-memory object small: already aggregated to same-tract totals)
# od_ds <- open_dataset("out_od_parquet", format = "parquet")
# od_out <- collect(od_ds) %>% arrange(tract_id, year)
# 
# 
# 
# # ---- (Optional) Save the combined OD panel, or merge with your RAC/WAC now ----
# write_parquet(od_out, "lodes_od_same_tract2010_2010_2019.parquet")

# ------------------------------
# 6) OD FULL (all origin-destination pairs)
#    - Stream by state-year
#    - Skip if cached
#    - Save after each state-year to avoid losing progress
# ------------------------------

# ---- Output directory for full OD Parquet chunks ----
dir.create("data_derivatives/out_od_full_parquet", showWarnings = FALSE)


# ---- Streamed OD downloader → Parquet writer (full OD) ----
process_od_full_state_yearly <- function(st) {
  yrs <- years_wac_od(st)
  if (!length(yrs)) return(invisible(NULL))
  for (yr in yrs) {
    out_path <- sprintf("data_derivatives/out_od_full_parquet/od_full_%s_%d.parquet", st, yr)
    if (file.exists(out_path)) {
      message(sprintf("[OD-FULL] %s %d (cached)", st, yr))
      next
    }

    message(sprintf("[OD-FULL] %s %d", st, yr))

    # Pull a single state-year to keep memory bounded
    od_one <- grab_lodes(
      state = st, year = yr,
      lodes_type = "od", job_type = "JT00", segment = "S000",
      agg_geo = "tract", state_part = "main", version = "LODES7"
    )

    # Keep only necessary columns; store year for convenience
    od_cols <- c(
      "h_tract", "w_tract", "S000",
      "SA01", "SA02", "SA03",
      "SE01", "SE02", "SE03",
      "SI01", "SI02", "SI03"
    )
    keep_cols <- intersect(od_cols, names(od_one))
    od_small <- as.data.table(od_one)[, ..keep_cols]
    od_small[, year := yr]

    # Write to temp then rename for safer caching
    tmp_path <- paste0(out_path, ".tmp")
    write_parquet(od_small, tmp_path)
    file.rename(tmp_path, out_path)

    # Clean up
    rm(od_one, od_small); gc()
  }
}


# ---- Run the streamed full OD writer over all states ----
invisible(lapply(all_states, process_od_full_state_yearly))


# ---- Optional: combine full OD chunks when you need them ----
# od_full_ds <- open_dataset("data_derivatives/out_od_full_parquet", format = "parquet")
# od_full <- collect(od_full_ds)
# write_parquet(od_full, "lodes_od_full_tract2010_2010_2019.parquet")



# # --------------------------------------------------------
# # 4. Construct outcome buckets (functions defined earlier)
# # --------------------------------------------------------
# 
# rac_out <- construct_outcomes(rac_raw, type = "rac")
# wac_out <- construct_outcomes(wac_raw, type = "wac")
# od_out  <- construct_outcomes_od(od_raw)
# 
# # --------------------------------------------------------
# # 5. Merge into a single national tract × year outcome panel
# # --------------------------------------------------------
# 
# panel <- rac_out %>%
#   full_join(wac_out, by = c("tract_id","year")) %>%
#   full_join(od_out,  by = c("tract_id","year")) %>%
#   arrange(tract_id, year)
# 
# # Save to disk
# 
# write_parquet(panel, "lodes_outcomes_tract2010_2010_2019.parquet")

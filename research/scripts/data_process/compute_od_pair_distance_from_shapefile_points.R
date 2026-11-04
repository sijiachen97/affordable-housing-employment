#!/usr/bin/env Rscript

# Computes straight-line distances (km) for each (h_tract, w_tract) pair in LODES OD files,
# using local TIGER/Line 2010 tract shapefiles-derived points (no API calls).
#
# Outputs BOTH:
# - internal-point distance (st_point_on_surface)  -> dist_intpt_km
# - geometric-centroid distance (st_centroid)     -> dist_centroid_km
#
# Run:
#   Rscript "./legacy_inputs/LODES/R code/compute_od_pair_distance_from_shapefile_points.R"
#
# Requires:
#   - OD parquet chunks in: ./legacy_inputs/LODES/data_derivatives/out_od_full_parquet/*.parquet
#   - Points cache:         ./legacy_inputs/LODES/data_derivatives/cache/tract2010_points_from_shapefile.parquet
#
# Output:
#   - OD+dist parquet chunks in: ./legacy_inputs/LODES/data_derivatives/out_od_full_parquet_with_dist_both/*.parquet

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

LODES_ROOT <- "./legacy_inputs/LODES"
OD_INPUT <- file.path(LODES_ROOT, "data_derivatives/out_od_full_parquet")  # folder of state-year Parquet chunks
POINTS_PATH <- file.path(LODES_ROOT, "data_derivatives", "cache", "tract2010_points_from_shapefile.parquet")
OUT_DIR <- file.path(LODES_ROOT, "data_derivatives/out_od_full_parquet_with_dist_both")


haversine_km <- function(lat1, lon1, lat2, lon2) {
  R <- 6371.0088
  to_rad <- function(x) x * pi / 180
  phi1 <- to_rad(lat1)
  phi2 <- to_rad(lat2)
  dphi <- to_rad(lat2 - lat1)
  dlmb <- to_rad(lon2 - lon1)
  a <- sin(dphi / 2)^2 + cos(phi1) * cos(phi2) * sin(dlmb / 2)^2
  2 * R * asin(pmin(1, sqrt(a)))
}


ensure_dir <- function(path) dir.create(path, showWarnings = FALSE, recursive = TRUE)


list_od_files <- function(input) {
  if (file.exists(input) && !dir.exists(input)) return(normalizePath(input))
  if (!dir.exists(input)) stop(sprintf("OD_INPUT not found: %s", input))
  sort(list.files(input, pattern = "\\.parquet$", full.names = TRUE))
}


load_points <- function(path) {
  if (!file.exists(path)) stop(sprintf("Points cache not found: %s", path))
  pts <- as.data.table(read_parquet(path))
  need <- c("tract_id", "intpt_lat", "intpt_lon", "centroid_lat", "centroid_lon")
  miss <- setdiff(need, names(pts))
  if (length(miss)) stop(sprintf("Points cache missing columns: %s", paste(miss, collapse = ", ")))

  pts[, tract_id := as.character(tract_id)]
  pts[, intpt_lat := as.numeric(intpt_lat)]
  pts[, intpt_lon := as.numeric(intpt_lon)]
  pts[, centroid_lat := as.numeric(centroid_lat)]
  pts[, centroid_lon := as.numeric(centroid_lon)]

  setkey(pts, tract_id)
  pts
}


add_dist_to_one_file <- function(file_path, pts, out_dir) {
  ensure_dir(out_dir)
  out_path <- file.path(out_dir, basename(file_path))
  if (file.exists(out_path)) {
    message(sprintf("[DIST] cached %s", basename(file_path)))
    return(invisible(NULL))
  }

  message(sprintf("[DIST] %s", basename(file_path)))
  dt <- as.data.table(read_parquet(file_path))

  # Join internal points and centroids for h_tract and w_tract
  dt <- merge(dt, pts, by.x = "h_tract", by.y = "tract_id", all.x = TRUE)
  setnames(
    dt,
    old = c("intpt_lat", "intpt_lon", "centroid_lat", "centroid_lon"),
    new = c("h_intpt_lat", "h_intpt_lon", "h_centroid_lat", "h_centroid_lon")
  )

  dt <- merge(dt, pts, by.x = "w_tract", by.y = "tract_id", all.x = TRUE)
  setnames(
    dt,
    old = c("intpt_lat", "intpt_lon", "centroid_lat", "centroid_lon"),
    new = c("w_intpt_lat", "w_intpt_lon", "w_centroid_lat", "w_centroid_lon")
  )

  dt[, dist_intpt_km := haversine_km(h_intpt_lat, h_intpt_lon, w_intpt_lat, w_intpt_lon)]
  dt[, dist_centroid_km := haversine_km(h_centroid_lat, h_centroid_lon, w_centroid_lat, w_centroid_lon)]

  tmp <- paste0(out_path, ".tmp")
  write_parquet(dt, tmp)
  file.rename(tmp, out_path)
  invisible(NULL)
}


main <- function() {
  pts <- load_points(POINTS_PATH)
  files <- list_od_files(OD_INPUT)
  if (!length(files)) stop("No OD parquet files found.")

  message(sprintf("[POINTS] %d tracts loaded", nrow(pts)))
  message(sprintf("[INPUT] %d OD file(s)", length(files)))

  for (i in seq_along(files)) {
    add_dist_to_one_file(files[[i]], pts, OUT_DIR)
    gc()
  }

  message("[DONE]")
}


if (identical(environment(), globalenv())) {
  main()
}

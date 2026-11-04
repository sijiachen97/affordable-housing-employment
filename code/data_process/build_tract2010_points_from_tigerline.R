#!/usr/bin/env Rscript

# Build 2010 tract internal points + geometric centroids from TIGER/Line shapefiles (local).
#
# Expected inputs (after downloading + unzipping state tract zips):
#   ./legacy_inputs/LODES/data_raw/tiger2010_tract/unzipped/*.shp
#
# Output:
#   ./legacy_inputs/LODES/data_derivatives/cache/tract2010_points_from_shapefile.parquet
#
# Columns:
#   tract_id (11-char GEOID10)
#   intpt_lat, intpt_lon          (internal point; st_point_on_surface)
#   centroid_lat, centroid_lon    (geometric centroid; st_centroid)

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(arrow)
})

LODES_ROOT <- "data_raw/LODES"
SHAPE_DIR <- file.path(LODES_ROOT, "tiger2010_tract", "unzipped")
OUT_PATH <- file.path(LODES_ROOT, "OD_related", "cache", "tract2010_points_from_shapefile.parquet")

dir.create(dirname(OUT_PATH), showWarnings = FALSE, recursive = TRUE)

shps <- list.files(SHAPE_DIR, pattern = "\\.shp$", full.names = TRUE)
if (!length(shps)) stop(sprintf("No .shp files found in %s", SHAPE_DIR))

read_one <- function(path) {
  message(sprintf("[READ] %s", basename(path)))
  x <- suppressWarnings(st_read(path, quiet = TRUE))
  nm <- names(x)
  geoid_col <- intersect(nm, c("GEOID10", "GEOID"))
  if (!length(geoid_col)) stop(sprintf("Missing GEOID column in %s", basename(path)))
  geoid_col <- geoid_col[[1]]

  x <- x %>% transmute(tract_id = as.character(.data[[geoid_col]]), geometry = geometry)

  # Use a projected CRS for centroid calculations, then transform back to lon/lat.
  x_5070 <- st_transform(x, 5070) # NAD83 / Conus Albers
  centroid_5070 <- st_centroid(x_5070$geometry)
  intpt_5070 <- st_point_on_surface(x_5070$geometry)

  centroid_ll <- st_transform(st_sfc(centroid_5070, crs = 5070), 4326)
  intpt_ll <- st_transform(st_sfc(intpt_5070, crs = 5070), 4326)

  c_xy <- st_coordinates(centroid_ll)
  i_xy <- st_coordinates(intpt_ll)

  tibble(
    tract_id = x$tract_id,
    intpt_lat = i_xy[, "Y"],
    intpt_lon = i_xy[, "X"],
    centroid_lat = c_xy[, "Y"],
    centroid_lon = c_xy[, "X"]
  )
}

pts <- bind_rows(lapply(shps, read_one)) %>%
  filter(!is.na(tract_id), nchar(tract_id) == 11) %>%
  distinct(tract_id, .keep_all = TRUE)

message(sprintf("[OUT] tracts=%d -> %s", nrow(pts), OUT_PATH))
write_parquet(pts, OUT_PATH)

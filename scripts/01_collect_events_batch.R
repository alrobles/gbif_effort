#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(optparse); library(yaml)
  library(dplyr); library(dbplyr); library(readr)
  library(terra); library(gbifdb); library(tibble)
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# -------- CLI --------
opt_list <- list(
  make_option("--config",      type="character", default="config/config.yml"),
  make_option("--taxon",       type="character", help="One GBIF class (e.g. Mammalia)"),
  make_option("--threads",     type="integer",   default=16),
  make_option("--strict-uncert", action="store_true", default=FALSE,
              help="If set, drop rows with NA uncertainty; otherwise keep NA or <= threshold")
)
opt <- parse_args(OptionParser(option_list = opt_list))
stopifnot(!is.null(opt$taxon) && nzchar(opt$taxon))

# -------- Config & paths --------
cfg         <- yaml::read_yaml(opt$config)
threads     <- as.integer(opt$threads)
taxon       <- opt$taxon

gbifdb_dir  <- Sys.getenv("GBIFDB_DIR", unset = cfg$gbifdb_dir %||% "gbifdata")
tables_dir  <- cfg$output$tables_dir %||% "output/tables"
maps_dir    <- cfg$output$maps_dir   %||% "output/maps"
tmpl_path   <- cfg$world_template_path %||% "data/study_area/world_template.tif"

dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(maps_dir,   recursive = TRUE, showWarnings = FALSE)
stopifnot(dir.exists(gbifdb_dir))
stopifnot(file.exists(tmpl_path))

# Thread controls for DuckDB / Arrow / BLAS
Sys.setenv(
  DUCKDB_MAX_THREADS = as.character(threads),
  ARROW_NUM_THREADS  = as.character(threads),
  OMP_NUM_THREADS    = as.character(threads),
  OPENBLAS_NUM_THREADS = as.character(threads),
  MKL_NUM_THREADS    = as.character(threads)
)

# -------- Template grid (must be lon/lat degrees) --------
r_tmpl <- terra::rast(tmpl_path)
stopifnot(terra::is.lonlat(r_tmpl))
dx <- terra::res(r_tmpl)[1]
dy <- terra::res(r_tmpl)[2]

# -------- Filters --------
yr_min <- cfg$year_range[[1]]
yr_max <- cfg$year_range[[2]]
unc_m  <- cfg$uncertainty_m %||% Inf

# -------- GBIF local (Parquet) --------
gbif <- gbifdb::gbif_local(dir = gbifdb_dir)

# Build query: years + uncertainty + taxon + valid coords + snap to grid
q <- gbif %>%
  filter(year >= !!yr_min, year <= !!yr_max) %>%
  { if (opt$`strict-uncert`)
    filter(., !is.na(coordinateuncertaintyinmeters) & coordinateuncertaintyinmeters <= !!unc_m)
    else
      filter(., is.na(coordinateuncertaintyinmeters) | coordinateuncertaintyinmeters <= !!unc_m) } %>%
  filter(class == !!taxon,
         !is.na(decimallatitude), !is.na(decimallongitude),
         !is.na(eventdate)) %>%
  filter(decimallongitude != 0 | decimallatitude != 0) %>%
  mutate(
    longitude = round(decimallongitude / !!dx) * !!dx,
    latitude  = round(decimallatitude  / !!dy) * !!dy
  ) %>%
  distinct(class, longitude, latitude, eventdate) %>%
  group_by(class, longitude, latitude) %>%
  tally(name = "n")

df <- collect(q)

if (nrow(df) == 0) {
  message("No rows after filtering for taxon: ", taxon)
  quit(status = 0)
}

# ---- effort table (lon, lat, n) ----
effort_df <- df %>% select(longitude, latitude, n)

# Write CSV
out_csv <- file.path(tables_dir, sprintf("%s_effort_df.csv", taxon))
readr::write_csv(effort_df, out_csv)

# Write raster (XYZ → GeoTIFF)
xyz <- effort_df %>% rename(x = longitude, y = latitude, z = n)
rast_eff <- terra::rast(xyz, type = "xyz", crs = "EPSG:4326")
out_tif  <- file.path(maps_dir, sprintf("%s_effort_df.tif", taxon))
terra::writeRaster(rast_eff, out_tif, overwrite = TRUE,
                   gdal = c("COMPRESS=LZW","PREDICTOR=2","TILED=YES","BLOCKXSIZE=256","BLOCKYSIZE=256","BIGTIFF=YES"))

message("Done: ", taxon,
        "\n  CSV: ", out_csv,
        "\n  TIF: ", out_tif)
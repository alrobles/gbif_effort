# ───────────────────────────────────────────────────────────────
# 0) User knobs (override here while testing)
# ───────────────────────────────────────────────────────────────
CFG_PATH       <- "config/config.yml"
OVERRIDE_TAXA  <- c("Mammalia")      # set NULL to use config taxa
WRITE_OUTPUTS  <- TRUE               # write CSVs to output/tables
STRICT_UNCERT  <- FALSE              # FALSE = keep NA uncertainty; TRUE = drop NAs
USE_AOI_CLIP   <- TRUE               # TRUE = polygon clip after collect; FALSE = bbox-only
THREADS        <- 56                 # threads for DuckDB / Arrow / BLAS

# ───────────────────────────────────────────────────────────────
# 1) Libraries & helpers
# ───────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(yaml)
  library(dplyr)
  library(dbplyr)
  library(readr)
  library(terra)
  library(gbifdb)
  library(tibble)
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Optional: install/load any runtime deps you wrap in utils (if present)
if (file.exists("R/utils_install.R")) {
  source("R/utils_install.R")
  if (exists("ensure_runtime_deps")) ensure_runtime_deps()
}

# ───────────────────────────────────────────────────────────────
# 2) Load config and environment
# ───────────────────────────────────────────────────────────────
cfg <- yaml::read_yaml(CFG_PATH)

# Allow override of taxa for this interactive run
taxa <- if (is.null(OVERRIDE_TAXA)) cfg$taxa else OVERRIDE_TAXA
stopifnot(length(taxa) >= 1)

# GBIF snapshot directory (prefer .env; fallback to cfg; else "gbifdata")
gbifdb_dir <- Sys.getenv("GBIFDB_DIR", unset = cfg$gbifdb_dir %||% "gbifdata")
tables_dir <- cfg$output$tables_dir %||% "output/tables"
maps_dir   <- cfg$output$maps_dir   %||% "output/maps"
dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)

# AOI path and world template path
aoi_path    <- cfg$study_area_path %||% "data/study_area/AOI.gpkg"
tmpl_path   <- cfg$world_template_path %||% "data/study_area/world_template.tif"

stopifnot(file.exists(aoi_path))
stopifnot(file.exists(tmpl_path))

# Years / uncertainty
yr_min <- cfg$year_range[[1]]
yr_max <- cfg$year_range[[2]]
unc_m  <- cfg$uncertainty_m %||% Inf

message("Config summary:")
message("  GBIFDB_DIR : ", gbifdb_dir)
message("  AOI path   : ", aoi_path)
message("  Template   : ", tmpl_path)
message("  Taxa       : ", paste(taxa, collapse = ", "))
message("  Years      : ", yr_min, "–", yr_max)
message("  Uncert (m) : ", unc_m)
message("  Threads    : ", THREADS)

# Thread controls (keeps engines from oversubscribing the node)
Sys.setenv(
  DUCKDB_MAX_THREADS = as.character(THREADS),
  ARROW_NUM_THREADS  = as.character(THREADS),
  OMP_NUM_THREADS    = as.character(THREADS),
  OPENBLAS_NUM_THREADS = as.character(THREADS),
  MKL_NUM_THREADS    = as.character(THREADS)
)

# ───────────────────────────────────────────────────────────────
# 3) Read world template; derive grid; read AOI & bbox
# ───────────────────────────────────────────────────────────────
r_tmpl <- terra::rast(tmpl_path)
stopifnot(terra::is.lonlat(r_tmpl))  # we expect degrees (WGS84/CRS84/4326)

grid_dx <- terra::res(r_tmpl)[1]
grid_dy <- terra::res(r_tmpl)[2]
message(sprintf("Template grid: Δlon=%.6f°, Δlat=%.6f°", grid_dx, grid_dy))

aoi <- terra::vect(aoi_path)


if (!grepl("4326|WGS|CRS84", terra::crs(aoi), ignore.case = TRUE)) {
  aoi <- terra::project(aoi, "EPSG:4326")
}
bb <- terra::ext(aoi)
xmin <- terra::xmin(bb); xmax <- terra::xmax(bb)
ymin <- terra::ymin(bb); ymax <- terra::ymax(bb)
message(sprintf("AOI bbox: xmin=%.6f, xmax=%.6f, ymin=%.6f, ymax=%.6f", xmin, xmax, ymin, ymax))

# ───────────────────────────────────────────────────────────────
# 4) Connect to local GBIF Parquet snapshot via gbifdb
# ───────────────────────────────────────────────────────────────
stopifnot(dir.exists(gbifdb_dir))
gbif <- gbifdb::gbif_local(dir = gbifdb_dir)

# Helper to build the base query (common filters)
base_query <- function() {
  q <- gbif %>%
    filter(year >= !!yr_min, year <= !!yr_max) %>%
    { if (STRICT_UNCERT) filter(., !is.na(coordinateuncertaintyinmeters) & coordinateuncertaintyinmeters <= !!unc_m)
      else filter(., is.na(coordinateuncertaintyinmeters) | coordinateuncertaintyinmeters <= !!unc_m) } %>%
    filter(!is.na(decimallatitude), !is.na(decimallongitude), !is.na(eventdate)) %>%
    filter(decimallongitude != 0 | decimallatitude != 0)
  q
}

# ───────────────────────────────────────────────────────────────
# 5) Stage-by-stage diagnostics for a single taxon (first in list)
# ───────────────────────────────────────────────────────────────
probe_taxon <- taxa[[1]]

# get how many events are in the same long lat accumulated in 30
# years of sampling 

#
q0 <- base_query() %>% 
  filter(class == !!probe_taxon) %>%  
  mutate(longitude = round(decimallongitude / !!grid_dx) * !!grid_dx,
         latitude  = round(decimallatitude  / !!grid_dy) * !!grid_dy
  ) %>% 
  distinct(class, longitude, latitude, eventdate) %>% 
  group_by(class, longitude, latitude)  %>%
  count() 

n1 <- q0 %>% collect() 
n1 

pts  <- terra::vect(n1, geom = c("longitude", "latitude"), crs = "EPSG:4326")
plot(pts)
world_template <- rast(tmpl_path)
extracted_df <- terra::extract(x = world_template, y = pts, xy = TRUE)

effort_df <- cbind(n1, extracted_df) |> 
  na.exclude() |>
  group_by(class, x, y) |> 
  summarise(n = sum(n)) |> 
  ungroup() |> 
  select(x, y, n) 

names(effort_df) <- c("longitude", "latitude", OVERRIDE_TAXA)
raster_effort <- rast(effort_df)

## then write ouputs in dirs. One output csv and one output in raster
write_csv(effort_df, file.path(tables_dir, stringr::str_glue("{OVERRIDE_TAXA}_effort_df.csv")))
writeRaster(raster_effort, file.path(maps_dir, stringr::str_glue("{OVERRIDE_TAXA}_effort_df.tif")))

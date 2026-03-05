run_stage1_collect_events <- function(cfg) {
  ensure_runtime_deps()
  library(dplyr); library(readr); library(terra); library(gbifdb); library(tibble)

  gbifdb_dir <- Sys.getenv("GBIFDB_DIR", cfg$gbifdb_dir)
  tables_dir <- cfg$output$tables_dir %||% "output/tables"
  maps_dir   <- cfg$output$maps_dir   %||% "output/maps"

  world_r_path <- file.path(maps_dir, "world_1_120.tif")
  world_v_path <- file.path(maps_dir, "world.shp")
  if (!file.exists(world_r_path) || !file.exists(world_v_path)) {
    land <- make_world_land_mask(world_r_path, world_v_path, res_deg = cfg$wgs84_cell_deg)
    world_r <- land$r; world_v <- land$v
  } else {
    world_r <- terra::rast(world_r_path)
    world_v <- terra::vect(world_v_path)
  }

  gbif <- gbifdb::gbif_local(dir = gbifdb_dir)
  yr_min <- cfg$year_range[[1]]; yr_max <- cfg$year_range[[2]]; unc_m <- cfg$uncertainty_m

  get_taxon_tbl <- function(taxon) {
    gbif %>%
      filter(year >= !!yr_min, year <= !!yr_max) %>%
      filter(coordinateuncertaintyinmeters < !!unc_m) %>%
      mutate(
        latitude  = round(120 * decimallatitude) / 120,
        longitude = round(120 * decimallongitude) / 120
      ) %>%
      filter(class == !!taxon,
             !is.na(latitude), !is.na(longitude),
             !is.na(eventdate),
             !is.na(institutioncode), !is.na(collectioncode)) %>%
      filter(longitude != 0 | latitude != 0) %>%
      distinct(class, eventdate, longitude, latitude) %>%
      collect()
  }

  data_list <- lapply(cfg$taxa, get_taxon_tbl)
  gbif_data <- bind_rows(data_list)

  pts <- terra::vect(gbif_data, geom = c("longitude","latitude"), crs = terra::crs(world_r))
  ext <- terra::extract(world_r, pts, cells = TRUE) %>% as_tibble()
  gbif_data <- dplyr::bind_cols(gbif_data, ext)

  gbif_data_thin <- gbif_data %>%
    as_tibble() %>%
    filter(!is.na(world)) %>%
    select(class, eventdate, longitude, latitude, cell) %>%
    group_by(cell, eventdate) %>%
    slice(1) %>% ungroup() %>%
    select(class, eventdate, longitude, latitude) %>%
    distinct()

  for (taxon in cfg$taxa) {
    out_csv <- out_path(tables_dir, sprintf("02_gbif_events_%s.csv", taxon))
    gbif_data_thin %>%
      filter(class == taxon) %>%
      select(eventdate, longitude, latitude) %>%
      write_csv(out_csv)
  }
  message("Stage 1 complete.")
}
``

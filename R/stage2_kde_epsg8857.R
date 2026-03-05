run_stage2_kde <- function(cfg, taxon = NULL) {
  ensure_runtime_deps()
  library(dplyr); library(readr); library(terra); library(ks); library(stringr)

  tables_dir <- cfg$output$tables_dir %||% "output/tables"
  maps_dir   <- cfg$output$maps_dir   %||% "output/maps"
  res_m      <- cfg$resolution_m
  epsg       <- cfg$equal_area_epsg
  aoi_path   <- cfg$study_area_path

  if (is.null(taxon)) taxon <- cfg$taxa[[1]]
  in_csv  <- file.path(tables_dir, sprintf("02_gbif_events_%s.csv", taxon))
  stopifnot(file.exists(in_csv))

  ev <- read_csv(in_csv, show_col_types = FALSE)
  stopifnot(all(c("longitude","latitude") %in% names(ev)))

  aoi_v <- if (!is.null(aoi_path) && file.exists(aoi_path)) terra::vect(aoi_path) else NULL

  world_shp <- file.path(maps_dir, "world.shp"); stopifnot(file.exists(world_shp))
  world_v <- terra::vect(world_shp)

  v_wgs84 <- terra::vect(ev, geom = c("longitude","latitude"), crs = "EPSG:4326")
  v_proj  <- terra::project(v_wgs84, sprintf("EPSG:%s", epsg))
  world_proj <- terra::project(world_v, sprintf("EPSG:%s", epsg))

  r_template <- terra::rast(ext = terra::ext(v_proj), resolution = res_m, crs = sprintf("EPSG:%s", epsg))
  r_count <- terra::rasterize(v_proj, r_template, fun = "count", background = 0)
  names(r_count) <- "count"

  centroids <- as.data.frame(r_count, xy = TRUE, na.rm = TRUE)
  names(centroids) <- c("x","y","count")
  centroids <- centroids[!is.na(centroids$count) & centroids$count > 0, ]
  coords   <- as.matrix(centroids[, c("x","y")])
  weights  <- centroids$count
  stopifnot(nrow(coords) == length(weights))

  gridsize <- c(ncol(r_count), nrow(r_count))
  kde_res <- ks::kde(x = coords, w = weights, binned = TRUE, density = TRUE, gridsize = gridsize)

  x_vals <- kde_res$eval.points[[1]]
  y_vals <- kde_res$eval.points[[2]]
  z_mat  <- kde_res$estimate

  r_kde <- terra::rast(
    ncols = length(x_vals), nrows = length(y_vals),
    xmin = min(x_vals), xmax = max(x_vals),
    ymin = min(y_vals), ymax = max(y_vals),
    crs  = terra::crs(r_count)
  )
  values(r_kde) <- as.vector(z_mat[, ncol(z_mat):1])

  rng <- terra::global(r_kde, fun = c("min","max"), na.rm = TRUE)
  r_kde_norm <- (r_kde - rng[1,1]) / (rng[2,1] - rng[1,1])
  r_kde_norm <- terra::crop(r_kde_norm, world_proj, mask = TRUE)
  if (!is.null(aoi_v)) {
    aoi_proj <- terra::project(aoi_v, terra::crs(r_kde_norm))
    r_kde_norm <- terra::crop(r_kde_norm, aoi_proj, mask = TRUE)
  }

  world_r_path <- file.path(maps_dir, "world_1_120.tif"); stopifnot(file.exists(world_r_path))
  world_r <- terra::rast(world_r_path)
  r_kde_wgs84 <- terra::project(r_kde_norm, world_r, method = "bilinear")
  r_kde_wgs84 <- terra::crop(r_kde_wgs84, world_r, mask = TRUE)

  out_tif <- file.path(maps_dir, str_glue("r_kde_wgs84_{taxon}_{res_m}m.tif"))
  terra::writeRaster(r_kde_wgs84, out_tif, overwrite = TRUE)
  message("Wrote: ", out_tif)
}

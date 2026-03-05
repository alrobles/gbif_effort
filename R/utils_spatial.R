make_world_land_mask <- function(out_r_path, out_v_path, res_deg = 1/120) {
  land <- rnaturalearth::ne_countries(scale = 50, type = "land", returnclass = "sf")
  land <- sf::st_make_valid(land)
  land_v <- terra::vect(land); terra::crs(land_v) <- "EPSG:4326"
  r <- terra::rast(extent = terra::ext(-180, 180, -90, 90),
                   resolution = res_deg, crs = "EPSG:4326")
  r_land <- terra::rasterize(land_v, r, field = 1, background = NA); names(r_land) <- "world"
  dir.create(dirname(out_r_path), showWarnings = FALSE, recursive = TRUE)
  dir.create(dirname(out_v_path), showWarnings = FALSE, recursive = TRUE)
  terra::writeRaster(r_land, out_r_path, overwrite = TRUE)
  terra::writeVector(land_v, out_v_path, overwrite = TRUE)
  list(r = r_land, v = land_v)
}

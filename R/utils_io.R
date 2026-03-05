read_config <- function(path = "config/config.yml") yaml::read_yaml(path)
out_path <- function(dir, fname) {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, fname)
}
`%||%` <- function(x, y) if (is.null(x)) y else x

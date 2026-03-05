install_if_missing <- function(packages, repos = "https://cloud.r-project.org") {
  missing <- setdiff(packages, rownames(installed.packages()))
  if (length(missing)) {
    install.packages(missing, repos = repos, Ncpus = max(1L, parallel::detectCores() - 1L))
  }
  invisible(TRUE)
}
ensure_runtime_deps <- function() {
  install_if_missing(c(
    "gbifdb","ks","tidyverse","terra",
    "yaml","optparse","rnaturalearth","rnaturalearthdata","furrr"
  ))
}

#!/usr/bin/env Rscript
suppressPackageStartupMessages({ library(optparse); library(yaml) })
source("R/utils_install.R"); ensure_runtime_deps()
option_list <- list(
  make_option("--config", type = "character", default = "config/config.yml"),
  make_option("--taxon",  type = "character", default = NULL)
)
opt <- parse_args(OptionParser(option_list = option_list), positional_arguments = TRUE)
cfg <- yaml::read_yaml(opt$options$config)
source("R/utils_io.R"); source("R/utils_spatial.R"); source("R/stage2_kde_epsg8857.R")
run_stage2_kde(cfg, taxon = opt$options$taxon)

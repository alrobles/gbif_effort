#!/usr/bin/env Rscript
suppressPackageStartupMessages({ library(optparse); library(yaml) })
source("R/utils_install.R"); ensure_runtime_deps()
option_list <- list(
  make_option("--config", type = "character", default = "config/config.yml"),
  make_option("--taxa",   type = "character", action = "store", default = NULL)
)
opt <- parse_args(OptionParser(option_list = option_list), positional_arguments = TRUE)
cfg <- yaml::read_yaml(opt$options$config)
if (!is.null(opt$options$taxa)) cfg$taxa <- strsplit(opt$options$taxa, "\\s+")[[1]]
source("R/utils_io.R"); source("R/utils_spatial.R"); source("R/stage1_collect_events.R")
run_stage1_collect_events(cfg)


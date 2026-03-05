#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(optparse)
  library(gbifdb)
})

option_list <- list(
  make_option("--dir",     type = "character", default = NULL, help = "Local directory to store snapshot (will be created)"),
  make_option("--version", type = "character", default = NULL, help = "Snapshot date YYYY-MM-DD (default: latest)"),
  make_option("--bucket",  type = "character", default = "gbif-open-data-us-east-1", help = "GBIF S3 bucket (regional)")
)
opt <- parse_args(OptionParser(option_list = option_list))

# Resolve directory
gbif_dir <- opt$dir
if (is.null(gbif_dir) || gbif_dir == "") {
  # fallback to env or default in gbifdb
  gbif_dir <- Sys.getenv("GBIFDB_DIR", unset = gbifdb::gbif_dir())
}
if (!dir.exists(gbif_dir)) dir.create(gbif_dir, recursive = TRUE, showWarnings = FALSE)

# Resolve version
ver <- if (is.null(opt$version) || opt$version == "") gbifdb::gbif_version() else opt$version

cat("==> Downloading GBIF snapshot\n")
cat("    dir    :", gbif_dir, "\n")
cat("    version:", ver, "\n")
cat("    bucket :", opt$bucket, "\n")

ok <- gbifdb::gbif_download(
  version = ver,
  dir     = gbif_dir,
  bucket  = opt$bucket
)

if (isTRUE(ok)) {
  cat("✓ GBIF snapshot synced successfully.\n")
  quit(status = 0)
} else {
  cat("✗ GBIF snapshot sync reported failure.\n")
  quit(status = 1)
}

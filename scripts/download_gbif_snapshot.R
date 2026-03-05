#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(optparse)
  library(gbifdb)
})

# Ensure local ./.bin is in PATH inside R (in case container env is sanitized)
repo_bin <- file.path(getwd(), ".bin")
if (dir.exists(repo_bin)) {
  Sys.setenv(PATH = paste(repo_bin, Sys.getenv("PATH"), sep = .Platform$path.sep))
}

# Optional: sanity-check that mc is visible now
mc_ok <- tryCatch(system2("mc", args = "--version", stdout = TRUE, stderr = TRUE), error = function(e) NULL)
if (is.null(mc_ok)) {
  cat("WARNING: 'mc' not found on PATH inside R. gbifdb::gbif_download() may fail.\n")
}

option_list <- list(
  make_option("--dir",     type = "character", default = NULL, help = "Local directory for snapshot"),
  make_option("--version", type = "character", default = NULL, help = "YYYY-MM-DD (default: latest)"),
  make_option("--bucket",  type = "character", default = "gbif-open-data-us-east-1", help = "GBIF S3 bucket")
)
opt <- parse_args(OptionParser(option_list = option_list))

gbif_dir <- opt$dir
if (is.null(gbif_dir) || gbif_dir == "") {
  gbif_dir <- Sys.getenv("GBIFDB_DIR", unset = gbifdb::gbif_dir())
}
if (!dir.exists(gbif_dir)) dir.create(gbif_dir, recursive = TRUE, showWarnings = FALSE)

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
  cat("✓ GBIF snapshot synced successfully.\n"); quit(status = 0)
} else {
  cat("✗ GBIF snapshot sync reported failure.\n"); quit(status = 1)
}

# Overview

This repository provides a containerized (Apptainer) workflow to *(i)* mirror a GBIF Parquet snapshot locally and *(ii)* run a two-stage R pipeline: Stage 1 (collect unique events) and Stage 2 (KDE in EPSG:8857, cropped to an AOI).

# Prerequisites

- Linux environment with **Apptainer** (Singularity) available.

- **git** installed.

- Network egress to public S3 (HTTPS/443).

- Disk space: ~300 GB (varies by snapshot).

# Quick Start (TL;DR)

Run these from a shell after cloning:

    # 0) Clone
    git clone git@github.com:YOURUSER/gbif_effort.git
    cd gbif_effort

    # 1) Configure env (repo-local snapshot directory by default)
    cp config/.env.example .env
    # .env should contain: GBIFDB_DIR=gbifdata

    # 2) Build Apptainer image (includes gbifdb, ks, minioclient)
    bash container/build.sh

    # 3) Download GBIF snapshot (resume-safe; choose closest bucket)
    BUCKET=gbif-open-data-us-east-1 VERSION= \
    bash scripts/setup_gbif_snapshot.sh

    # 4) Stage 1 (Mammalia only as first pass)
    CONFIG=config/config.yml \
    apptainer exec --cleanenv container/gbif-kde.sif \
      Rscript scripts/01_collect_events.R --config config/config.yml --taxa Mammalia

    # 5) Stage 2 (KDE for Mammalia)
    CONFIG=config/config.yml \
    apptainer exec --cleanenv container/gbif-kde.sif \
      Rscript scripts/02_kde_world8857.R --config config/config.yml --taxon Mammalia

# Clone & Configure

    git clone git@github.com:YOURUSER/gbif_effort.git
    cd gbif_effort

    # Create runtime .env
    cp config/.env.example .env
    # .env -> GBIFDB_DIR=gbifdata   (a DIRECTORY, not a file)

**Notes.**

- The mirror will create: `gbifdata/occurrence/YYYY-MM-DD/occurrence.parquet/`

- Optional AOI (recommended for prototyping):

      data/study_area/AOI.gpkg

  Point to it in `config/config.yml`:

      study_area_path: "data/study_area/AOI.gpkg"

# Build the Apptainer Image

    bash container/build.sh
    # produces: container/gbif-kde.sif

The image is based on `rocker/geospatial` and installs: `gbifdb`, `ks`, `minioclient`, and small helper packages used by scripts.

# Download the GBIF Parquet Snapshot (Resume-Safe)

Default mirrors the latest snapshot from the US bucket into `./gbifdata`:

    BUCKET=gbif-open-data-us-east-1 VERSION= \
    bash scripts/setup_gbif_snapshot.sh

**Tips.**

- Choose a regional bucket close to your compute: e.g., `gbif-open-data-eu-central-1` or `gbif-open-data-ap-southeast-2`.

- Pin a specific release date (strict reproducibility) via `VERSION=YYYY-MM-DD`.

- *Resume-safe:* If interrupted, re-run the same command; it continues where it left off.

## Retry Loop for Flaky Networks (optional)

    export BUCKET=gbif-open-data-us-east-1
    export VERSION=
    for i in $(seq 1 30); do
      echo "Attempt $i @ $(date)"
      if bash scripts/setup_gbif_snapshot.sh; then
        echo "Mirror succeeded"; break
      fi
      echo "Mirror failed; sleeping 60s…"
      sleep 60
    done

## Expected Layout After Success

    gbifdata/
      occurrence/
        YYYY-MM-DD/
          occurrence.parquet/
            part-00000-...parquet
            part-00001-...parquet
            ...

# Verify the Local Snapshot

    apptainer exec --cleanenv container/gbif-kde.sif R -q <<'RS'
    library(gbifdb); library(dplyr)
    gbif <- gbif_local("gbifdata")  # autodiscovers latest version
    print(gbif %>% select(class, year, decimallatitude, decimallongitude) %>%
          head() %>% collect())
    RS

# Run the Pipeline

## Stage 1: Collect Unique Events

Produces per-taxon CSV of event coordinates over land-only cells.

    CONFIG=config/config.yml \
    apptainer exec --cleanenv container/gbif-kde.sif \
      Rscript scripts/01_collect_events.R --config config/config.yml --taxa Mammalia

Outputs:

    output/tables/
      02_gbif_events_Mammalia.csv

## Stage 2: KDE → GeoTIFF

Reproject to EPSG:8857, grid/rasterize counts, KDE (ks), normalize, crop to AOI, reproject to WGS84 for distribution:

    CONFIG=config/config.yml \
    apptainer exec --cleanenv container/gbif-kde.sif \
      Rscript scripts/02_kde_world8857.R --config config/config.yml --taxon Mammalia

Outputs (name reflects resolution_m):

    output/maps/
      r_kde_wgs84_Mammalia_10000m.tif

# Configuration Knobs (config/config.yml)

- `taxa`: e.g., `["Mammalia"]` for first pass.

- `study_area_path`: e.g., `"data/study_area/AOI.gpkg"`.

- `year_range`, `uncertainty_m`.

- Stage 1 grid: `wgs84_cell_deg` (e.g., 0.0083333333 $`\approx`$ 1 km).

- Stage 2 proj/res: `equal_area_epsg: 8857`, `resolution_m` (e.g., 10000).

- KDE bandwidth: `kde.bandwidth: "auto"` or a numeric (meters).

# Recommended Repository Layout

    gbif_effort/
      R/                     # helpers + stage functions
      scripts/               # CLI entrypoints + setup helpers
      config/                # config.yml + .env.example
      container/             # apptainer.def + build.sh
      data/
        study_area/          # AOI.gpkg and small vector layers (tracked)
        world/               # small templates (tif) if desired
      gbifdata/              # local GBIF mirror (ignored)
      output/
        tables/              # CSVs (ignored)
        maps/                # GeoTIFFs (ignored)
      .gitignore

# Troubleshooting

#### Connection reset / mirror fails mid-run.

Re-run the setup script (resume-safe) or use the retry loop. If your HPC has DTNs (data transfer nodes), run there. Try a closer regional bucket.

#### `minioclient` required.

The image pre-installs the R package `minioclient`, which `gbif_download()` uses to drive the `mc mirror` operation. If you customized the image, ensure `minioclient` is installed inside the container.

#### GBIF path confusion.

`GBIFDB_DIR` is a *directory*. The mirror creates: `GBIFDB_DIR/occurrence/YYYY-MM-DD/occurrence.parquet/`.

# Reproducibility Tips

- Pin `VERSION=YYYY-MM-DD` when mirroring the snapshot.

- Commit only small AOIs/templates; ignore heavy rasters and `gbifdata`.

- Keep `--cleanenv` on `apptainer exec` to avoid host module pollution.



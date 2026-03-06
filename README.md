# What this guide covers

1.  Build the Apptainer image for a reproducible R geospatial stack.

2.  Download (mirror) the GBIF Parquet snapshot locally (resume–safe).

3.  Run Stage 1 (collect unique events / effort counts) for **Mammalia**.

This README is the LaTeX source; you can convert it to Markdown using Pandoc in R:

    library(rmarkdown)
    pandoc_convert("README_stage1.tex", to = "gfm", output = "README.md",
                   options = c("--wrap=none"))

# Prerequisites

- Linux machine or HPC environment with **Apptainer** (a.k.a. Singularity).

- **git**.

- Outbound HTTPS (443) to access public S3 buckets for GBIF snapshots.

- Disk space: recommend hundreds of GB (varies by selected snapshot and taxa).

# Repository layout (Stage–1 only)

    gbif_effort/
      container/
        apptainer.def
        build.sh
      scripts/
        01_collect_events_batch.R
        run_stage1.sh
        submit_stage1_array.slurm
        install_minio.sh
        setup_gbif_snapshot.sh
        download_gbif_snapshot.R
      config/
        config.yml
        .env.example          # GBIFDB_DIR=gbifdata
      data/
        study_area/
          world_template.tif  # 0.1° lon/lat template (tracked)
          AOI.gpkg            # saved for later (unused in Stage-1)
      gbifdata/               # GBIF Parquet mirror (ignored by git)
      output/                 # results (ignored by git)

# Clone and configure

    # 0) Clone
    git clone git@github.com:YOURUSER/gbif_effort.git
    cd gbif_effort

    # 1) Environment file (repo-local GBIF mirror by default)
    cp config/.env.example .env
    # .env should contain: GBIFDB_DIR=gbifdata

    # 2) Confirm the world template exists (0.1° lon/lat)
    ls -lh data/study_area/world_template.tif

# Build the Apptainer image

    bash container/build.sh
    # result: container/gbif-kde.sif

# Mirror the GBIF Parquet snapshot (resume–safe)

The repo provides a small wrapper that: (1) downloads a local `mc` client if missing, (2) launches an R script `gbifdb::gbif_download()` inside the container.

## Mirror the latest US snapshot into `./gbifdata`

    BUCKET=gbif-open-data-us-east-1 VERSION= \
    bash scripts/setup_gbif_snapshot.sh

## Notes

- **VERSION=** `YYYY-MM-DD` pins a specific snapshot (strict reproducibility).

- The mirror is **resume–safe**. If interrupted, re-run the same command.

- Expected layout after completion:

      gbifdata/
        occurrence/
          YYYY-MM-DD/
            occurrence.parquet/
              part-00000-...parquet
              part-00001-...parquet
              ...

# Verify the snapshot quickly

    apptainer exec --cleanenv \
      --env GBIFDB_DIR="$PWD/gbifdata" \
      container/gbif-kde.sif R -q <<'RS'
    library(gbifdb); library(dplyr)
    x <- gbif_local(Sys.getenv("GBIFDB_DIR","gbifdata"))
    print(x %>% select(class, year, decimallatitude, decimallongitude) %>%
          head() %>% collect())
    RS

# Run Stage–1 for Mammalia

Stage–1 reads the **0.1° grid** directly from `data/study_area/world_template.tif`. It **does not** apply an AOI yet (as per this first, simplified release).

## A. Run directly (host wrapper; sequential)

    THREADS=32 \
    TAXA="Mammalia" \
    CONFIG=config/config.yml \
    SIF=container/gbif-kde.sif \
    GBIFDB_DIR="$PWD/gbifdata" \
    bash scripts/run_stage1.sh

Outputs (examples):

    output/tables/Mammalia_effort_df.csv
    # (If --write-tif is enabled inside the R call, also:)
    output/maps/Mammalia_effort_df.tif

## B. SLURM array (one taxon per task; optional)

    printf "Mammalia\n" > taxa.txt

    sbatch --array=1-1 \
      --cpus-per-task=32 --mem=120G -t 24:00:00 \
      --export=THREADS=32,CONFIG=config/config.yml,SIF=container/gbif-kde.sif, \
               GBIFDB_DIR=$PWD/gbifdata,TAXA_FILE=taxa.txt \
      scripts/submit_stage1_array.slurm

# What the Stage–1 script does

1.  Reads template resolution ($`\Delta\lambda, \Delta\phi`$) from `world_template.tif` (0.1°).

2.  Queries GBIF locally (`gbifdb::gbif_local()`) with year/uncertainty/taxon filters.

3.  Snaps lon/lat to the 0.1° grid and reduces to `distinct(class, lon, lat, eventdate)`.

4.  Aggregates to counts per grid cell $`(\lambda,\phi)`$ — an effort table.

5.  Writes a CSV per taxon (and optionally a GeoTIFF).

# Configuration knobs (`config/config.yml`)

- `world_template_path`: typically `data/study_area/world_template.tif`.

- `year_range`, `uncertainty_m`.

- `output.tables_dir`, `output.maps_dir`.

# Troubleshooting

#### Container cannot find `GBIFDB_DIR`.

If you run with `--cleanenv`, forward the environment variable explicitly:

    --env GBIFDB_DIR="$PWD/gbifdata"

The provided wrappers (`run_stage1.sh`, `setup_gbif_snapshot.sh`) already pass `–env`.

#### Empty results for a taxon.

Double-check: (1) taxon class name matches GBIF (`Mammalia`), (2) widen `year_range`, (3) test uncertainty policy (keep NA vs. drop NA), and (4) verify the snapshot path.

# Quick reference (commands)

## Build image

    bash container/build.sh

## Mirror snapshot (latest US bucket)

    BUCKET=gbif-open-data-us-east-1 VERSION= \
    bash scripts/setup_gbif_snapshot.sh

## Run Stage–1 for Mammalia

    THREADS=32 TAXA="Mammalia" CONFIG=config/config.yml \
    SIF=container/gbif-kde.sif GBIFDB_DIR="$PWD/gbifdata" \
    bash scripts/run_stage1.sh


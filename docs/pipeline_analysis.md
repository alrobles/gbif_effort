# GBIF Effort Pipeline — Comprehensive Analysis

> **Repository:** [`alrobles/gbif_effort`](https://github.com/alrobles/gbif_effort)
> **Last updated:** 2026-04-04

---

## 1. Overview

**gbif_effort** is an automated, containerized data pipeline that processes [GBIF](https://www.gbif.org/) (Global Biodiversity Information Facility) occurrence records and computes **species observation effort metrics** — the count of unique observation events per geographic grid cell. These effort surfaces are a prerequisite for unbiased species-distribution modelling, conservation-gap analysis, and sampling-completeness assessments.

### Key Design Principles

| Principle | Implementation |
|---|---|
| **Reproducibility** | Apptainer (Singularity) container + pinned GBIF snapshot dates |
| **Scalability** | DuckDB/Parquet for columnar queries; SLURM array jobs for HPC |
| **Resume-safety** | MinIO-based S3 mirror syncs only missing Parquet parts |
| **Thread control** | Explicit env vars prevent CPU over-subscription on shared nodes |
| **Modularity** | Separate scripts for download → process → (future) KDE |

---

## 2. Repository Structure

```
gbif_effort/
├── installer.sh                        # Master entry-point (build + download + run)
│
├── config/
│   ├── .env.example                    # Environment variable template
│   └── config.yml                      # Pipeline parameters (taxa, filters, grid)
│
├── container/
│   ├── apptainer.def                   # Container definition (rocker/geospatial:4.4.1)
│   └── build.sh                        # Container build helper
│
├── data/
│   └── study_area/
│       ├── AOI.gpkg                    # Area of Interest polygon (GeoPackage)
│       └── world_template.tif          # 0.1° lon/lat reference grid (GeoTIFF)
│
├── gbifdata/                           # GBIF Parquet snapshot (downloaded at runtime)
│   └── .gitkeep
│
├── examples/
│   └── 01_collect_events_interactive.R # Interactive/RStudio version of Stage 1
│
└── scripts/
    ├── 01_collect_events_batch.R       # ★ Core Stage 1 processing (R)
    ├── download_gbif_snapshot.R        # GBIF S3 → local Parquet mirror (R)
    ├── install_minio.sh                # Install MinIO `mc` client
    ├── run_all.sh                      # Run all stages sequentially (template)
    ├── run_stage1.sh                   # Host wrapper: Apptainer exec → R script
    ├── setup_gbif_snapshot.sh          # Orchestrate snapshot download
    └── submit_stage1_array.slurm       # SLURM array job submission
```

---

## 3. Technology Stack

| Layer | Technology | Role |
|---|---|---|
| **Language** | R 4.4.1 | Data processing, geospatial ops |
| **Container** | Apptainer (Singularity) | Reproducible execution environment |
| **Base image** | `rocker/geospatial:4.4.1` | R + GDAL/GEOS/PROJ + terra + tidyverse |
| **Query engine** | DuckDB (via `gbifdb`) | Efficient Parquet filtering/aggregation |
| **Data format** | Apache Parquet | Columnar storage for 500 M+ records |
| **S3 client** | MinIO `mc` | Resume-safe GBIF snapshot download |
| **Orchestration** | Bash | Glue scripts, env setup |
| **HPC scheduler** | SLURM (optional) | Array job parallelism |
| **Geospatial** | `terra`, `sf`, GDAL | Grid snapping, rasterisation |
| **Configuration** | YAML + `.env` | Pipeline parameters |

### Key R Packages

- **`gbifdb`** — DuckDB-backed interface to GBIF Parquet snapshots
- **`terra`** — Raster/vector geospatial operations
- **`dplyr` / `dbplyr`** — Lazy DuckDB queries via familiar tidyverse verbs
- **`optparse`** — Command-line argument parsing
- **`yaml`** — Configuration file loading
- **`ks`** — Kernel density estimation (Stage 2, planned)
- **`rnaturalearth`** — Land-mask geometries

---

## 4. Data Pipeline — End-to-End Flow

```
┌──────────────────────────────────────────────────────────┐
│                    STAGE 0: SETUP                        │
│  installer.sh                                            │
│  ├─ Clone repo (if needed)                               │
│  ├─ Verify deps (bash, git, apptainer)                   │
│  ├─ Build Apptainer SIF  → container/gbif-kde.sif        │
│  └─ Write .env (GBIFDB_DIR)                              │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│              STAGE 1a: GBIF SNAPSHOT MIRROR              │
│  setup_gbif_snapshot.sh → download_gbif_snapshot.R       │
│  ├─ Install MinIO `mc` client                            │
│  ├─ gbifdb::gbif_download(bucket, version)               │
│  └─ Store Parquet partitions in gbifdata/                │
│                                                          │
│  Output:                                                 │
│    gbifdata/occurrence/YYYY-MM-DD/occurrence.parquet/    │
│      part-00000-*.parquet                                │
│      part-00001-*.parquet                                │
│      …                                                   │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│         STAGE 1b: EFFORT AGGREGATION (per taxon)         │
│  01_collect_events_batch.R                               │
│                                                          │
│  1. Load world_template.tif → extract grid resolution    │
│  2. Open GBIF Parquet via DuckDB                         │
│  3. Filter:                                              │
│     • year ∈ [yr_min, yr_max]                            │
│     • coordinateUncertaintyInMeters ≤ threshold          │
│     • class = <taxon>                                    │
│     • valid lat/lon (not NA, not 0/0)                    │
│  4. Snap coords → grid:                                  │
│       lon = round(lon / Δλ) × Δλ                         │
│       lat = round(lat / Δφ) × Δφ                         │
│  5. DISTINCT(class, lon, lat, eventdate)                 │
│  6. GROUP BY(lon, lat) → COUNT → effort "n"              │
│                                                          │
│  Output:                                                 │
│    output/tables/{TAXON}_effort_df.csv                   │
│    output/maps/{TAXON}_effort_df.tif   (optional)        │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│     STAGE 2: KDE & NORMALISATION (planned, not impl.)    │
│  02_kde_world8857.R  (referenced in run_all.sh)          │
│                                                          │
│  Intended steps:                                         │
│  1. Reproject effort counts → EPSG:8857 (equal-area)    │
│  2. Compute kernel density estimate (bandwidth: auto)    │
│  3. Normalise (method: max)                              │
│  4. Export final maps/tables                             │
│                                                          │
│  Output (planned):                                       │
│    output/maps/gbif_kde_*.tif                            │
│    output/tables/gbif_kde_*.csv                          │
└──────────────────────────────────────────────────────────┘
```

---

## 5. Configuration Reference

### `config/config.yml`

```yaml
# Path to GBIF Parquet snapshot (overridden by GBIFDB_DIR env var)
gbifdb_dir: "/abs/path/to/gbifdb/snapshot/occurrence.parquet"

# Study area polygon
study_area_path: "data/study_area/aoi.gpkg"

# Taxonomic classes to process (GBIF class rank)
taxa: ["Mammalia", "Amphibia", "Squamata"]

# Temporal filter
year_range: [1980, 2024]

# Spatial accuracy threshold (metres)
uncertainty_m: 1000

# Stage 1 grid resolution (WGS84 degrees)
wgs84_cell_deg: 0.0083333333333        # ≈ 1/120° ≈ 0.9 km at equator

# Stage 2 settings (planned)
equal_area_epsg: 8857
resolution_m: 1000
kde:
  bandwidth: "auto"
norm:
  method: "max"

# Output directories
output:
  tables_dir: "output/tables"
  maps_dir:   "output/maps"
  basename:   "gbif_kde"
```

### `config/.env.example`

```
GBIFDB_DIR=gbifdata
```

### `installer.sh` CLI Options

| Flag | Default | Description |
|---|---|---|
| `--bucket` | `gbif-open-data-us-east-1` | GBIF S3 bucket name |
| `--version` | *(latest)* | Snapshot date (`YYYY-MM-DD`) |
| `--taxa` | `"Mammalia"` | Space-separated GBIF class names |
| `--threads` | `16` | Thread count for DuckDB / Arrow / BLAS |
| `--submit` | `false` | `true` → submit SLURM array job |
| `--partition` | `sixhour` | SLURM partition name |
| `--account` | *(none)* | SLURM account |
| `--mem` | `16G` | SLURM memory per task |
| `--time` | `05:55:00` | SLURM walltime |

---

## 6. Execution Modes

### A. Quick Local Run (single machine)

```bash
bash installer.sh --taxa "Mammalia" --threads 16
# → output/tables/Mammalia_effort_df.csv
```

### B. HPC / SLURM Array (parallel per taxon)

```bash
bash installer.sh \
  --taxa "Mammalia Amphibia Squamata" \
  --threads 32 \
  --submit true \
  --partition compute \
  --mem 120G \
  --time 24:00:00
# → 3 array tasks, one per taxon
```

### C. Interactive / RStudio Development

Open `examples/01_collect_events_interactive.R`, set `CFG_PATH`, `OVERRIDE_TAXA`, `THREADS` at the top, and source inside RStudio. Includes optional plotting and AOI clipping.

---

## 7. Thread & Resource Control

The pipeline explicitly sets **six** environment variables to prevent CPU over-subscription on shared HPC nodes:

| Variable | Controls |
|---|---|
| `DUCKDB_MAX_THREADS` | DuckDB query parallelism |
| `ARROW_NUM_THREADS` | Apache Arrow / Parquet reading |
| `OMP_NUM_THREADS` | OpenMP-based libraries |
| `OPENBLAS_NUM_THREADS` | BLAS linear algebra |
| `MKL_NUM_THREADS` | Intel MKL linear algebra |
| `NUMEXPR_MAX_THREADS` | NumExpr (rare in R, but safe) |

All are set to the single `--threads` value passed through the pipeline.

---

## 8. Container Architecture

```
┌──────────────────────────────────────────────┐
│          Apptainer SIF                       │
│          (container/gbif-kde.sif)            │
│                                              │
│  Base: rocker/geospatial:4.4.1              │
│  ├── R 4.4.1                                │
│  ├── GDAL, GEOS, PROJ                       │
│  ├── terra, sf, tidyverse                    │
│  │                                           │
│  Added R packages:                           │
│  ├── gbifdb        (DuckDB/Parquet GBIF)    │
│  ├── ks            (Kernel Density Est.)     │
│  ├── minioclient   (S3 download)            │
│  ├── yaml          (Config parsing)         │
│  ├── optparse      (CLI arguments)          │
│  ├── rnaturalearth (Land masks)             │
│  ├── rnaturalearthdata                       │
│  └── furrr         (Parallel purrr maps)    │
│                                              │
│  Runscript: exec "$@"  (flexible entry)     │
└──────────────────────────────────────────────┘
```

Built with:

```bash
apptainer build container/gbif-kde.sif container/apptainer.def
```

---

## 9. Output Format

### Stage 1 CSV — `{TAXON}_effort_df.csv`

| Column | Type | Description |
|---|---|---|
| `longitude` | float | Grid-snapped longitude (WGS84) |
| `latitude` | float | Grid-snapped latitude (WGS84) |
| `n` | integer | Number of unique observation events in that cell |

### Stage 1 GeoTIFF — `{TAXON}_effort_df.tif` (optional, `--write-tif`)

- CRS: EPSG:4326 (WGS84)
- Resolution: matches `wgs84_cell_deg` in config
- Values: observation count per pixel

---

## 10. Current Status

| Component | Status | Notes |
|---|---|---|
| Container build | ✅ Complete | `apptainer.def` + `build.sh` |
| GBIF snapshot download | ✅ Complete | Resume-safe via MinIO |
| Stage 1 — effort aggregation | ✅ Complete | Batch + interactive + SLURM |
| Stage 2 — KDE / normalisation | 🔲 Planned | Script referenced but not written |
| CI/CD | ❌ None | No GitHub Actions workflows |
| Tests | ❌ None | No automated test suite |
| Documentation | ⚠️ Minimal | README only |

---

## 11. Potential Enhancements

1. **Implement Stage 2** (`02_kde_world8857.R`) — kernel density estimation and normalisation as outlined in `config.yml`.
2. **Add CI/CD** — GitHub Actions workflow to lint R scripts and validate config.
3. **Add tests** — Unit tests for grid-snapping logic; integration tests with a small sample Parquet file.
4. **Parameterise grid template** — Generate `world_template.tif` from config instead of shipping a static file.
5. **Multi-resolution support** — Allow different `wgs84_cell_deg` per taxon or analysis.
6. **Progress logging** — Structured log output with timestamps for long-running jobs.
7. **Error handling** — Graceful failure and retry for S3 download interruptions.

---

*This document was auto-generated from an analysis of the `alrobles/gbif_effort` repository.*

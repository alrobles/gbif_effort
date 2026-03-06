#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Defaults (override via CLI flags)
# ------------------------------------------------------------
BUCKET="gbif-open-data-us-east-1"
VERSION=""                         # empty = latest
TAXA="Mammalia"
THREADS="16"
SUBMIT="false"                     # true -> sbatch array; false -> run locally
PARTITION=""                       # e.g., compute
ACCOUNT=""                         # e.g., your allocation
MEM="64G"
WALL="12:00:00"
SIF="container/gbif-kde.sif"
CONFIG="config/config.yml"
GBIFDB_DIR_DEFAULT="gbifdata"
APPTAINER_BIN="${APPTAINER:-apptainer}"
CLEANENV="1"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: installer.sh [options]

Core options:
  --bucket NAME            GBIF bucket (default: gbif-open-data-us-east-1)
  --version YYYY-MM-DD     GBIF snapshot version; "" = latest (default: "")
  --taxa "T1 T2"           Space-separated taxa (default: "Mammalia")
  --threads N              Threads for DuckDB/Arrow/BLAS (default: 16)
  --submit true|false      Submit via SLURM array instead of local run (default: false)

SLURM options (used only when --submit true):
  --partition NAME         SLURM partition/queue (optional)
  --account NAME           SLURM account/allocation (optional)
  --mem SIZE               Memory per task (default: 64G)
  --time HH:MM:SS          Walltime per task (default: 12:00:00)

Advanced:
  --sif PATH               Apptainer image path (default: container/gbif-kde.sif)
  --config PATH            Pipeline config (default: config/config.yml)

Examples:
  bash installer.sh --taxa "Mammalia"
  bash installer.sh --taxa "Mammalia Amphibia" --threads 32 --submit true --partition compute --mem 120G --time 24:00:00
USAGE
}

abs_path() { python3 - <<'PY' "$1"
import os,sys; print(os.path.abspath(sys.argv[1]))
PY
}

die() { echo "ERROR: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

# ------------------------------------------------------------
# Parse CLI
# ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket) BUCKET="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --taxa) TAXA="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;;
    --submit) SUBMIT="$2"; shift 2;;
    --partition) PARTITION="$2"; shift 2;;
    --account) ACCOUNT="$2"; shift 2;;
    --mem) MEM="$2"; shift 2;;
    --time) WALL="$2"; shift 2;;
    --sif) SIF="$2"; shift 2;;
    --config) CONFIG="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# ------------------------------------------------------------
# Sanity checks & prep
# ------------------------------------------------------------
need bash
need git
need "${APPTAINER_BIN}"

[[ -f "${SIF}" ]] || { echo "Building Apptainer image..."; bash container/build.sh; }

# Ensure .env exists and GBIFDB_DIR is set
if [[ ! -f .env ]]; then
  echo "Creating .env from config/.env.example ..."
  cp config/.env.example .env
fi
if ! grep -q '^GBIFDB_DIR=' .env; then
  echo "GBIFDB_DIR=${GBIFDB_DIR_DEFAULT}" >> .env
fi
# Export GBIFDB_DIR and make absolute for HPC robustness
GBIFDB_DIR="$(grep '^GBIFDB_DIR=' .env | tail -1 | cut -d= -f2-)"
GBIFDB_DIR_ABS="$(abs_path "${GBIFDB_DIR}")"
mkdir -p "${GBIFDB_DIR_ABS}"

echo "Using:"
echo "  BUCKET=${BUCKET}"
echo "  VERSION=${VERSION:-latest}"
echo "  GBIFDB_DIR=${GBIFDB_DIR_ABS}"
echo "  TAXA=${TAXA}"
echo "  THREADS=${THREADS}"
echo "  SUBMIT=${SUBMIT}"

# ------------------------------------------------------------
# 1) Mirror GBIF snapshot (resume-safe)
# ------------------------------------------------------------
export BUCKET VERSION GBIFDB_DIR
bash scripts/setup_gbif_snapshot.sh

# Quick check of expected layout
if ! ls -1 "${GBIFDB_DIR_ABS}"/occurrence/*/occurrence.parquet >/dev/null 2>&1; then
  echo "WARNING: Could not find occurrence/<date>/occurrence.parquet under ${GBIFDB_DIR_ABS}"
fi

# ------------------------------------------------------------
# 2) Run Stage-1 (locally or via SLURM)
# ------------------------------------------------------------

# Common env forwarding for Apptainer (--cleanenv implies we must pass vars)
APPT_FLAGS=()
[[ "${CLEANENV}" == "1" ]] && APPT_FLAGS+=(--cleanenv)
APPT_FLAGS+=( \
  --env GBIFDB_DIR="${GBIFDB_DIR_ABS}" \
  --env DUCKDB_MAX_THREADS="${THREADS}" \
  --env ARROW_NUM_THREADS="${THREADS}" \
  --env OMP_NUM_THREADS="${THREADS}" \
  --env OPENBLAS_NUM_THREADS="${THREADS}" \
  --env MKL_NUM_THREADS="${THREADS}" \
)

if [[ "${SUBMIT}" == "false" ]]; then
  echo "Running Stage-1 locally (one taxon after another) ..."
  # Host wrapper already forwards --env to Apptainer internally
  THREADS="${THREADS}" TAXA="${TAXA}" CONFIG="${CONFIG}" SIF="${SIF}" GBIFDB_DIR="${GBIFDB_DIR_ABS}" \
  bash scripts/run_stage1.sh
  echo "Done. Outputs in output/tables (and output/maps if enabled)."
  exit 0
fi

# ---- SLURM mode ----
need sbatch
echo "Preparing SLURM array..."

# Build taxa.txt dynamically
TAXA_FILE="taxa.txt"
printf "%s\n" $TAXA > "${TAXA_FILE}"

# Compose sbatch args
SBATCH_ARGS=( --array=1-$(wc -l < "${TAXA_FILE}") --cpus-per-task="${THREADS}" --mem="${MEM}" -t "${WALL}" )
[[ -n "${PARTITION}" ]] && SBATCH_ARGS+=( -p "${PARTITION}" )
[[ -n "${ACCOUNT}"   ]] && SBATCH_ARGS+=( --account="${ACCOUNT}" )

# Export vars into the job environment
EXPORTS=THREADS="${THREADS}",CONFIG="${CONFIG}",SIF="${SIF}",GBIFDB_DIR="${GBIFDB_DIR_ABS}",TAXA_FILE="${TAXA_FILE}"

echo "Submitting SLURM array with:"
echo "  sbatch ${SBATCH_ARGS[*]} --export=${EXPORTS} scripts/submit_stage1_array.slurm"
sbatch "${SBATCH_ARGS[@]}" --export="${EXPORTS}" scripts/submit_stage1_array.slurm

echo "Submitted. Monitor with: squeue -u $USER"

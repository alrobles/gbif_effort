#!/usr/bin/env bash
set -euo pipefail

# 1) Ensure .env is loaded (so we get GBIFDB_DIR)
if [[ -f ".env" ]]; then
  set -o allexport
  source .env
  set +o allexport
fi

if [[ -z "${GBIFDB_DIR:-}" ]]; then
  echo "ERROR: GBIFDB_DIR not set. cp config/.env.example .env and set GBIFDB_DIR=/path/to/snapshot"
  exit 1
fi

# 2) Install MinIO client locally (repo-scoped), if not installed
if [[ ! -x ".bin/mc" ]]; then
  echo "Installing MinIO client (mc)..."
  bash scripts/install_minio.sh
else
  echo "MinIO client found at .bin/mc"
fi

# 3) Prepend .bin to PATH so gbifdb::gbif_download() can find 'mc'
export PATH="$(pwd)/.bin:${PATH}"

# 4) Build container if needed
if [[ ! -f "container/gbif-kde.sif" ]]; then
  echo "Building Apptainer image..."
  bash container/build.sh
fi

# 5) Choose a bucket close to your region for faster sync
#    Defaults to us-east-1; adjust to e.g. "gbif-open-data-eu-central-1" if appropriate.
BUCKET="${BUCKET:-gbif-open-data-us-east-1}"

# 6) Optional: pin a snapshot date (YYYY-MM-DD) by setting VERSION, otherwise latest
VERSION="${VERSION:-}"

echo "Starting GBIF snapshot download into: ${GBIFDB_DIR}"
echo "Bucket : ${BUCKET}"
echo "Version: ${VERSION:-latest}"

# 7) Run the R downloader inside the container, inheriting PATH with mc
CONFIG=${CONFIG:-config/config.yml}

apptainer exec \
  --env PATH="${PATH}" \
  container/gbif-kde.sif \
  Rscript scripts/download_gbif_snapshot.R \
    --dir "${GBIFDB_DIR}" \
    --bucket "${BUCKET}" \
    ${VERSION:+--version "${VERSION}"}

echo "Done."

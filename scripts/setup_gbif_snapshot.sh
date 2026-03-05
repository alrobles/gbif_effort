#!/usr/bin/env bash
set -euo pipefail

# 1) Load .env for GBIFDB_DIR
if [[ -f ".env" ]]; then
  set -o allexport
  source .env
  set +o allexport
fi

if [[ -z "${GBIFDB_DIR:-}" ]]; then
  echo "ERROR: GBIFDB_DIR not set. cp config/.env.example .env and set GBIFDB_DIR=/path/to/snapshot_dir"
  exit 1
fi

# 2) Install MinIO client locally if missing
if [[ ! -x ".bin/mc" ]]; then
  echo "Installing MinIO client (mc)..."
  bash scripts/install_minio.sh
else
  echo "MinIO client found at .bin/mc"
fi

# 3) Prepare clean PATH for the container (avoid Lmod etc.)
HOST_BIN_PATH="$(pwd)/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 4) Build container if needed
if [[ ! -f "container/gbif-kde.sif" ]]; then
  echo "Building Apptainer image..."
  bash container/build.sh
fi

# 5) Region/bucket + optional version
BUCKET="${BUCKET:-gbif-open-data-us-east-1}"
VERSION="${VERSION:-}"

echo "Starting GBIF snapshot download into: ${GBIFDB_DIR}"
echo "Bucket : ${BUCKET}"
echo "Version: ${VERSION:-latest}"

# 6) Verify mc is executable on host
./.bin/mc --version >/dev/null 2>&1 || { echo "ERROR: mc not runnable."; exit 1; }

# 7) Exec inside container with --cleanenv and explicit PATH
apptainer exec \
  --cleanenv \
  --env PATH="${HOST_BIN_PATH}" \
  container/gbif-kde.sif \
  Rscript scripts/download_gbif_snapshot.R \
    --dir "${GBIFDB_DIR}" \
    --bucket "${BUCKET}" \
    ${VERSION:+--version "${VERSION}"}

echo "Done."

#!/usr/bin/env bash
set -euo pipefail

: "${CONFIG:=config/config.yml}"
: "${SIF:=container/gbif-kde.sif}"
: "${THREADS:=16}"
: "${GBIFDB_DIR:=gbifdata}"        # repo-local by default
: "${APPTAINER:=apptainer}"
: "${CLEANENV:=1}"

# space-separated list, e.g. "Mammalia Amphibia"
: "${TAXA:=Mammalia}"

# Threads env for R/DuckDB/Arrow/BLAS
export GBIFDB_DIR
export DUCKDB_MAX_THREADS="${THREADS}"
export ARROW_NUM_THREADS="${THREADS}"
export OMP_NUM_THREADS="${THREADS}"
export OPENBLAS_NUM_THREADS="${THREADS}"
export MKL_NUM_THREADS="${THREADS}"

AE=()
[[ "${CLEANENV}" == "1" ]] && AE+=(--cleanenv)

[[ -f "${SIF}" ]] || { echo "ERROR: SIF not found: ${SIF}"; exit 1; }

echo "CONFIG=${CONFIG}"
echo "SIF=${SIF}"
echo "THREADS=${THREADS}"
echo "GBIFDB_DIR=${GBIFDB_DIR}"
echo "TAXA=${TAXA}"

for tx in ${TAXA}; do
  echo "==> Taxon: ${tx}"
  "${APPTAINER}" exec "${AE[@]}" "${SIF}" \
    Rscript scripts/01_collect_events_batch.R \
      --config "${CONFIG}" \
      --taxon "${tx}" \
      --threads "${THREADS}"
done
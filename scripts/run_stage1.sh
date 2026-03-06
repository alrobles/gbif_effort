#!/usr/bin/env bash
set -euo pipefail

: "${CONFIG:=config/config.yml}"
: "${SIF:=container/gbif-kde.sif}"
: "${THREADS:=16}"
: "${GBIFDB_DIR:=gbifdata}"
: "${APPTAINER:=apptainer}"
: "${CLEANENV:=1}"
: "${TAXA:=Mammalia}"

# Compose Apptainer exec flags
AE=()
[[ "${CLEANENV}" == "1" ]] && AE+=(--cleanenv)

# >>> Add explicit --env forwarding <<<
AE+=( \
  --env GBIFDB_DIR="${GBIFDB_DIR}" \
  --env DUCKDB_MAX_THREADS="${THREADS}" \
  --env ARROW_NUM_THREADS="${THREADS}" \
  --env OMP_NUM_THREADS="${THREADS}" \
  --env OPENBLAS_NUM_THREADS="${THREADS}" \
  --env MKL_NUM_THREADS="${THREADS}" \
)

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

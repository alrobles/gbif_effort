#!/usr/bin/env bash
#SBATCH -J gbif_stage1
#SBATCH -o slurm_stage1_%A_%a.out
#SBATCH -e slurm_stage1_%A_%a.err
#SBATCH -N 1
#SBATCH --ntasks=1                   # Run a single task
#SBATCH --cpus-per-task=16            # Number of CPU cores per task
#SBATCH --mem=16G
#SBATCH --time=05:55:00
#SBATCH --partition=sixhour

# The list of taxa is provided via a file (one per line), default: taxa.txt
: "${TAXA_FILE:=data/taxa.txt}"

# Map SLURM cpus-per-task to THREADS (can override with --export=THREADS=…)
: "${THREADS:=${SLURM_CPUS_PER_TASK:-16}}"

# Pipeline settings (override with --export=VAR=VAL)
: "${CONFIG:=config/config.yml}"
: "${SIF:=container/gbif-kde.sif}"
: "${GBIFDB_DIR:=gbifdata}"
: "${APPTAINER:=apptainer}"
: "${CLEANENV:=1}"

TX=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${TAXA_FILE}")
[[ -n "${TX}" ]] || { echo "No taxon at index ${SLURM_ARRAY_TASK_ID} in ${TAXA_FILE}"; exit 1; }

echo "Job ${SLURM_JOB_ID} | Task ${SLURM_ARRAY_TASK_ID} | Taxon=${TX} | Threads=${THREADS}"

export GBIFDB_DIR
export DUCKDB_MAX_THREADS="${THREADS}"
export ARROW_NUM_THREADS="${THREADS}"
export OMP_NUM_THREADS="${THREADS}"
export OPENBLAS_NUM_THREADS="${THREADS}"
export MKL_NUM_THREADS="${THREADS}"

AE=()
[[ "${CLEANENV}" == "1" ]] && AE+=(--cleanenv)

"${APPTAINER}" exec "${AE[@]}" "${SIF}" \
  Rscript scripts/01_collect_events_batch.R \
    --config "${CONFIG}" \
    --taxon "${TX}" \
    --threads "${THREADS}"
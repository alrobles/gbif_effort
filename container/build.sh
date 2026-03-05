#!/usr/bin/env bash
set -euo pipefail
apptainer build container/gbif-kde.sif container/apptainer.def
echo "Built: container/gbif-kde.sif"

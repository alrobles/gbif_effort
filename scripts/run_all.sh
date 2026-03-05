#!/usr/bin/env bash
set -euo pipefail
CONFIG=${CONFIG:-config/config.yml}
bash scripts/check_env.sh
Rscript scripts/01_collect_events.R --config "$CONFIG" --taxa Mammalia Amphibia Squamata
Rscript scripts/02_kde_world8857.R --config "$CONFIG" --taxon Mammalia

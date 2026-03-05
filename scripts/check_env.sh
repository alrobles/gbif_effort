#!/usr/bin/env bash
set -euo pipefail
: "${CONFIG:=config/config.yml}"
if [[ -f ".env" ]]; then
  set -o allexport; source .env; set +o allexport
fi
if [[ -z "${GBIFDB_DIR:-}" ]]; then
  echo "ERROR: GBIFDB_DIR not set (cp config/.env.example .env and edit)."; exit 1
fi
if [[ ! -e "$GBIFDB_DIR" ]]; then
  echo "ERROR: GBIFDB_DIR path not found: $GBIFDB_DIR"; exit 1
fi
echo "✓ GBIFDB_DIR=$GBIFDB_DIR ; CONFIG=$CONFIG"


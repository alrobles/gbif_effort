#!/usr/bin/env bash
set -euo pipefail

# Where to place the binary (local to the repo, so you don't need root)
BIN_DIR="${BIN_DIR:-./.bin}"
MC="${BIN_DIR}/mc"

mkdir -p "$BIN_DIR"

# Detect platform (assuming Linux x86_64 on HPC)
OS=$(uname -s)
ARCH=$(uname -m)

if [[ "$OS" != "Linux" ]]; then
  echo "This installer currently expects Linux. Detected: $OS"
  exit 1
fi

# MinIO client download URL (official)
# See https://min.io/docs/minio/linux/index.html
URL="https://dl.min.io/client/mc/release/linux-amd64/mc"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" ]]; then
  echo "Non-x86_64 architecture detected (${ARCH}); please update the URL for your arch."
  exit 1
fi

echo "Downloading MinIO client to ${MC} ..."
curl -fsSL -o "${MC}" "${URL}"
chmod +x "${MC}"

echo "MinIO client installed at ${MC}"
echo "To use, prepend ${BIN_DIR} to PATH or call it explicitly."

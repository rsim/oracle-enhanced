#!/usr/bin/env bash

set -euo pipefail

IMAGE=gvenzl/oracle-free:latest
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUT_DIR="$SCRIPT_DIR/tzdata"

docker pull "$IMAGE"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/timezlrg_*.dat "$OUT_DIR"/timezdif_*.dat

docker run --rm --entrypoint sh \
  -v "$OUT_DIR:/out" \
  "$IMAGE" \
  -c 'cp "$ORACLE_HOME"/oracore/zoneinfo/timezlrg_*.dat /out/ && chmod a+r /out/*.dat'

ls -1 "$OUT_DIR"

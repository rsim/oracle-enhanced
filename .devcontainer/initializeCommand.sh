#!/usr/bin/env bash

set -euo pipefail

IMAGE=gvenzl/oracle-free:latest
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORKSPACE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$SCRIPT_DIR/tzdata"

docker pull "$IMAGE"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/timezlrg_*.dat "$OUT_DIR"/timezdif_*.dat

docker run --rm --entrypoint sh \
  -v "$OUT_DIR:/out" \
  "$IMAGE" \
  -c 'cp "$ORACLE_HOME"/oracore/zoneinfo/timezlrg_*.dat /out/ && chmod a+r /out/*.dat'

ls -1 "$OUT_DIR"

# When opened from a git worktree, .git is a file whose `gitdir:` line points
# at the main repo's .git/worktrees/<branch>. That host path is not visible
# inside the dev container by default, so git commands inside the container
# fail with "fatal: not a git repository". Resolve the common git dir on the
# host and write it to .devcontainer/.env; docker-compose.yml bind-mounts it
# at the same path inside the container so the gitdir reference resolves.
GIT_COMMON_DIR=$(git -C "$WORKSPACE_DIR" rev-parse --git-common-dir)
case "$GIT_COMMON_DIR" in
  /*) ;;
  *) GIT_COMMON_DIR=$(cd "$WORKSPACE_DIR/$GIT_COMMON_DIR" && pwd) ;;
esac
printf 'GIT_COMMON_DIR=%s\n' "$GIT_COMMON_DIR" > "$SCRIPT_DIR/.env"

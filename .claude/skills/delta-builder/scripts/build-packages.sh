#!/usr/bin/env bash
#
# build-packages.sh — Phase 4 of the delta build: build the delta package for each version,
# one at a time, from the version's current (latest) delta branch.
#
# Cleans the tree before each build (stale obj/bin from a prior branch cause MSBuild
# failures; building one version at a time avoids cross-version artifact contamination).
# cerelease exits 0 even on a failed build, so output is scanned for failure markers and the
# run stops on the first bad build.
#
# Usage:
#   build-packages.sh 2025.09 2025.10 2026.05         # space-separated versions
#   build-packages.sh 2025.09,2025.10,2026.05         # or comma-separated
#   build-packages.sh 2026.05 --allApps               # any --flag is passed through to cerelease
REPO="${DELTA_REPO:-D:/repos/CargasEnergy.worktrees/deltas}"
[ $# -ge 1 ] || { echo "usage: $0 <version> [version...] [--cereleaseFlag...]"; exit 2; }
cd "$REPO" || { echo "repo not found: $REPO"; exit 1; }

VERSIONS=""; FLAGS=""
for a in "$@"; do
  case "$a" in
    --*) FLAGS="$FLAGS $a" ;;
    *)   VERSIONS="$VERSIONS $(tr ',' ' ' <<<"$a")" ;;
  esac
done

git fetch origin --prune >/dev/null 2>&1
built=""; failed=""
for V in $VERSIONS; do
  echo "===== build $V ${FLAGS:+($FLAGS)} ====="
  git reset --hard HEAD >/dev/null 2>&1
  git clean -fxd -e "CargasEnergyWeb/node_modules" >/dev/null 2>&1
  out=$(cerelease create-delta "$V" $FLAGS </dev/null 2>&1)
  if grep -qE "✖|FAILED:|Build FAILED|error MSB|error CS[0-9]|TypeError|fatal:" <<<"$out"; then
    echo "$out" | tail -25
    echo "!! BUILD FAILED for $V — stopping (remaining versions not built)."
    failed="$V"; break
  fi
  echo "  $V: built ok"
  built="$built $V"
done

echo ""
echo "built:${built:- (none)}"
[ -n "$failed" ] && { echo "FAILED at: $failed"; exit 1; }
echo "all requested versions built"

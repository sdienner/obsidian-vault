#!/usr/bin/env bash
#
# merge-fix-branches.sh — Phase 3 of the delta build: merge dfb fix branches into the
# next delta branch for each version (creating those next delta branches as needed).
#
# It encodes the safety steps that this process needs (each one is a real failure mode):
#   - preflight: fetch + clean tree (cerelease/merges fail on a dirty tree or stale artifacts)
#   - sync: refresh each fix branch as a LOCAL branch. cerelease merges by *local* name; a
#     branch that exists only as origin/<fb> (e.g. a teammate's) makes it crash with a
#     misleading "TypeError: Cannot read properties of undefined (reading 'failed')".
#   - precheck: SIMULATE the accumulation merges per version and report clean/conflict, so
#     real conflicts are found up front instead of hanging cerelease's interactive prompt.
#   - run: cerelease with </dev/null + grep-based failure detection (cerelease exits 0 even
#     when its merge step fails, so the exit code can't be trusted).
#   - verify: confirm each delta ends up containing the fixes the plan assigned to it.
#
# Usage (plan from a file, or "-" / omitted to read a heredoc on stdin):
#   merge-fix-branches.sh check  <plan|->     # preflight + sync + precheck (NOTHING pushed)
#   merge-fix-branches.sh run    <plan|->     # check; if clean, run the merges; then verify
#   merge-fix-branches.sh verify <plan|->     # just re-verify origin against the plan
#
# Plan: one line per fix branch ('#' comments and blank lines ignored):
#   <fixbranch> <versions-csv> [create]
#   'create' => add --createNextDeltaBranches (mint the next delta branch for those versions).
#   List the create line(s) first; normally the single widest-coverage branch carries 'create'.
#
# Example:
#   merge-fix-branches.sh run - <<'PLAN'
#   dfb/CAR-32274          2025.09,2025.10,2025.11,2025.12,2026.01,2026.02,2026.03,2026.04,2026.05 create
#   dfb/CAR-33693-2025.09  2025.09,2025.10,2025.11,2025.12,2026.01,2026.02,2026.03
#   dfb/CAR-33693-2026.04  2026.04
#   dfb/CAR-34336          2026.01,2026.02,2026.03,2026.04
#   PLAN

REPO="${DELTA_REPO:-D:/repos/CargasEnergy.worktrees/deltas}"
MODE="${1:-}"; PLAN="${2:--}"
case "$MODE" in check|run|verify) ;; *) echo "usage: $0 check|run|verify <plan|->"; exit 2;; esac
cd "$REPO" || { echo "repo not found: $REPO"; exit 1; }
[ "$PLAN" = "-" ] && SRC=/dev/stdin || SRC="$PLAN"
mapfile -t LINES < <(grep -vE '^[[:space:]]*(#|$)' "$SRC")
[ "${#LINES[@]}" -gt 0 ] || { echo "empty plan"; exit 1; }

fb_of(){ awk '{print $1}' <<<"$1"; }
vers_of(){ awk '{print $2}' <<<"$1"; }
is_create(){ awk '{print $3}' <<<"$1" | grep -qi create; }
all_versions(){ for l in "${LINES[@]}"; do tr ',' '\n' <<<"$(vers_of "$l")"; done | sort -u; }
targets(){ grep -q ",$2," <<<",$(vers_of "$1"),"; }   # targets <planline> <version>
latest_delta(){ git branch -r | grep -oE "origin/delta/$1-[A-Z]+$" | sed "s#origin/delta/##" | sort | tail -1; }
release_ref(){ for r in "origin/release/$1" "origin/$1"; do git rev-parse -q --verify "$r" >/dev/null && { echo "$r"; return; }; done; }
base_ref(){ local d; d=$(latest_delta "$1"); [ -n "$d" ] && echo "origin/delta/$d" || release_ref "$1"; }

preflight(){
  echo "## preflight (fetch + clean tree)"
  git fetch origin --prune >/dev/null 2>&1
  git cherry-pick --abort 2>/dev/null; git merge --abort 2>/dev/null
  git reset --hard HEAD >/dev/null 2>&1
  git clean -fxd -e "CargasEnergyWeb/node_modules" >/dev/null 2>&1
  echo "   ok"
}

sync_locals(){
  echo "## sync fix branches to LOCAL branches (cerelease merges by local name)"
  local miss=0
  for l in "${LINES[@]}"; do local fb; fb=$(fb_of "$l")
    if git rev-parse -q --verify "origin/$fb" >/dev/null; then
      git branch -f "$fb" "origin/$fb" >/dev/null 2>&1; echo "   ok   $fb"
    else echo "   MISSING on origin: $fb"; miss=1; fi
  done
  return $miss
}

precheck(){
  echo "## conflict pre-check (simulated per version — nothing pushed)"
  local rc=0
  for V in $(all_versions); do
    local base; base=$(base_ref "$V")
    [ -z "$base" ] && { echo "   $V: no base branch (delta or release) found"; rc=1; continue; }
    git checkout --detach "$base" >/dev/null 2>&1 || { echo "   $V: cannot checkout $base"; rc=1; continue; }
    local bad=""
    for l in "${LINES[@]}"; do
      targets "$l" "$V" || continue
      local fb; fb=$(fb_of "$l")
      if ! git merge --no-ff --no-verify -m "precheck" "$fb" >/dev/null 2>&1; then
        local u; u=$(git diff --diff-filter=U --name-only | sed 's#.*/##' | tr '\n' ' ')
        echo "   $V: CONFLICT  $fb -> ${u:-<non-content, investigate>}"
        git merge --abort 2>/dev/null; bad=1; rc=1; break
      fi
    done
    [ -z "$bad" ] && echo "   $V: clean ($base)"
  done
  return $rc
}

run_merges(){
  echo "## cerelease merges"
  for l in "${LINES[@]}"; do
    local fb vers flag out; fb=$(fb_of "$l"); vers=$(vers_of "$l"); flag=""
    is_create "$l" && flag="--createNextDeltaBranches"
    echo "   -> $fb  ($vers) ${flag:+[create]}"
    out=$(cerelease create-delta "$vers" $flag --fixBranch "$fb" --skipDeltaPackageBuild </dev/null 2>&1)
    if grep -qE "✖|FAILED:|TypeError|CONFLICT \(|fatal:" <<<"$out"; then
      echo "$out" | tail -15
      echo "   !! cerelease FAILED on $fb — stopping. Resolve manually, narrow the plan, re-run."
      return 1
    fi
  done
  echo "   all merges OK"
}

verify(){
  echo "## verify each delta contains its planned fixes"
  git fetch origin --prune >/dev/null 2>&1
  local rc=0
  for V in $(all_versions); do
    local d miss; d=$(latest_delta "$V"); miss=""
    for l in "${LINES[@]}"; do
      targets "$l" "$V" || continue
      local fb; fb=$(fb_of "$l")
      git merge-base --is-ancestor "origin/$fb" "origin/delta/$d" 2>/dev/null || miss="$miss $fb"
    done
    [ -z "$miss" ] && echo "   $V (delta-$d): ✔ all present" || { echo "   $V (delta-$d): ✗ MISSING$miss"; rc=1; }
  done
  return $rc
}

cleanup(){ git checkout --detach "$(base_ref "$(all_versions | head -1)")" >/dev/null 2>&1; }

case "$MODE" in
  check)
    preflight; sync_locals || { echo "ABORT: fix branches missing on origin"; exit 1; }
    if precheck; then echo "PRECHECK: all clean — safe to run"; else echo "PRECHECK: conflicts above — resolve before run (see skill Phase 3 Step 3)"; fi
    cleanup ;;
  run)
    preflight; sync_locals || { echo "ABORT: fix branches missing on origin"; exit 1; }
    precheck || { echo "ABORT: pre-check found conflicts — resolve them and narrow the plan before run"; cleanup; exit 1; }
    run_merges || { cleanup; exit 1; }
    verify; cleanup ;;
  verify) verify ;;
esac

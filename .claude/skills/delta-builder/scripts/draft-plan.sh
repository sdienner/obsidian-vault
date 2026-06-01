#!/usr/bin/env bash
#
# draft-plan.sh — emit a DRAFT Phase-3 merge plan from the release grid.
#
# You still own the result — it can't know about dropped ranges or fixes not yet pushed.
# But it does the mechanical cross-referencing: grid issue -> dfb branch(es) on origin ->
# plan line(s), inferring split-branch version ranges from -YYYY.MM suffixes and auto-tagging
# the widest single-branch line 'create'.
#
# Input (file arg or stdin): one line per Jira issue, from the Phase 1 grid:
#   <issue-key> <versions-csv>
# Example:
#   draft-plan.sh - <<'GRID'
#   CAR-32274 2025.09,2025.10,2025.11,2025.12,2026.01,2026.02,2026.03,2026.04,2026.05
#   CAR-33693 2025.09,2025.10,2025.11,2025.12,2026.01,2026.02,2026.03,2026.04
#   GRID
#
# Output: a draft plan on stdout (feed to merge-fix-branches.sh after review) + warnings.
REPO="${DELTA_REPO:-D:/repos/CargasEnergy.worktrees/deltas}"
SRC="${1:--}"; [ "$SRC" = "-" ] && SRC=/dev/stdin
cd "$REPO" || { echo "repo not found: $REPO"; exit 1; }
git fetch origin --prune >/dev/null 2>&1
mapfile -t ROWS < <(grep -vE '^[[:space:]]*(#|$)' "$SRC")

PLAN=(); WARN=(); widest_n=0; widest=""
add_plan(){ PLAN+=("$1|$2"); local n; n=$(tr ',' '\n' <<<"$2" | grep -c .); if [ "$n" -gt "$widest_n" ]; then widest_n=$n; widest="$1|$2"; fi; }
suffix_of(){ grep -oE '\-2[0-9]{3}\.[0-9]{2}$' <<<"$1" | tr -d '-'; }

for r in "${ROWS[@]}"; do
  key=$(awk '{print $1}' <<<"$r"); vers=$(awk '{print $2}' <<<"$r")
  mapfile -t fbs < <(git branch -r | grep -oE "origin/dfb/${key}[^[:space:]]*" | sed 's#origin/##' | sort -u)
  case "${#fbs[@]}" in
    0) WARN+=("$key: no dfb branch on origin — build & push it, then re-run");;
    1)
      add_plan "${fbs[0]}" "$vers"
      [ -n "$(suffix_of "${fbs[0]}")" ] && WARN+=("$key: only ${fbs[0]} found, and it has a version suffix — looks partial; other ranges may not be pushed yet")
      ;;
    *)
      ok=1; for b in "${fbs[@]}"; do [ -z "$(suffix_of "$b")" ] && ok=0; done
      if [ "$ok" = 0 ]; then
        WARN+=("$key: ${#fbs[@]} branches but not all carry -YYYY.MM suffixes — set versions manually:")
        for b in "${fbs[@]}"; do add_plan "$b" "<FILL>"; WARN+=("    $b"); done
        continue
      fi
      mapfile -t VL < <(tr ',' '\n' <<<"$vers" | grep . | sort -u)
      mapfile -t SB < <(for b in "${fbs[@]}"; do echo "$(suffix_of "$b") $b"; done | sort)
      for i in "${!SB[@]}"; do
        cur=$(awk '{print $1}' <<<"${SB[$i]}"); br=$(awk '{print $2}' <<<"${SB[$i]}"); nxt=""
        [ $((i+1)) -lt "${#SB[@]}" ] && nxt=$(awk '{print $1}' <<<"${SB[$((i+1))]}")
        sel=$(for v in "${VL[@]}"; do
                if [ "$v" \> "$cur" ] || [ "$v" = "$cur" ]; then
                  { [ -z "$nxt" ] || [ "$v" \< "$nxt" ]; } && echo "$v"
                fi
              done | paste -sd, -)
        add_plan "$br" "${sel:-<none>}"
      done
      ;;
  esac
done

echo "# DRAFT merge plan — REVIEW before use (split ranges inferred from suffixes; remove dropped versions)"
for p in "${PLAN[@]}"; do
  fb=${p%%|*}; vs=${p#*|}
  [ "$p" = "$widest" ] && printf "%-26s %s create\n" "$fb" "$vs" || printf "%-26s %s\n" "$fb" "$vs"
done
if [ "${#WARN[@]}" -gt 0 ]; then echo ""; echo "# WARNINGS:"; printf '#   %s\n' "${WARN[@]}"; fi

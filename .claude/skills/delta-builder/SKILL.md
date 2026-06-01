---
name: delta-builder
description: Build delta versions of Cargas Energy. Creates fix branches, merges into delta branches, and builds packages using cerelease CLI.
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
user-invocable: true
---

# Delta Builder Skill

Build delta versions of Cargas Energy by creating fix branches, merging them into delta branches, and building delta packages using the `cerelease` CLI.

## Usage

```
/delta-builder              # Start a full delta build workflow
```

## Configuration

**Repository path:** `D:/repos/CargasEnergy.worktrees/deltas`

All git and cerelease commands MUST be prefixed with:
```bash
cd D:/repos/CargasEnergy.worktrees/deltas &&
```

**Release branch naming:** Versions **2025.10 and older** use plain branch names (`2025.09`, `2025.10`); **2025.11 and newer** use the `release/` prefix (`release/2025.11`, `release/2026.05`). Old release branches may also have been deleted entirely. Always confirm the exact base branch name with `git branch -r` before checking out — don't assume a `release/` prefix.

## About Deltas

Deltas are versions of Cargas Energy that only include changes made since the last full version — smaller downloads and quicker updates.

**Versioning:** Deltas append a hyphen and letter to the full version. For example, if the last full version was 2025.05:
- First delta: `2025.05-A`
- Second delta: `2025.05-B`
- And so on

Deltas are typically released in batches across multiple full versions. A release plan table in the Jira release issue defines which issues apply to which versions.

## How to Execute

### Phase 0: Pre-flight

Before creating any branches, get the repo into a known-clean state:

1. **Fetch and prune:** `cd D:/repos/CargasEnergy.worktrees/deltas && git fetch origin --prune`
2. **Clean the working tree:** the delta worktree accumulates modified *tracked* build artifacts (`bin/*.dll`, `Deployment.js/css`) that will block `git checkout -b`. Reset them with `git reset --hard HEAD` (add `git clean -fxd -e "CargasEnergyWeb/node_modules"` if untracked junk is present).
3. **Confirm nothing is mid-flight:** `git status` should show no cherry-pick or merge in progress. If one is, finish or `git cherry-pick --abort` it first.

### Phase 1: Parse the Release Plan

1. Ask the user for the **Jira release issue key** (e.g., `CAR-12345`)
2. Fetch the issue using the Jira MCP tool (`getJiraIssue`) and read the **description**
3. Find the release plan table in the description — it maps issues (columns) to full versions (rows) with `X` marks indicating inclusion
4. Display the parsed table to the user for confirmation before proceeding

**Important:** Only look for the table in the Jira issue description. Do NOT look up other Jira issues mentioned in the description.

Example release plan:

| Release Version | CAR-30298 | CAR-28519 | CAR-31235 |
|-----------------|-----------|-----------|-----------|
| 2025.01         | X         |           | X         |
| 2025.02         | X         | X         | X         |
| 2025.03         | X         | X         | X         |

### Phase 2: Create Fix Branches

For **each issue** in the release plan, create a fix branch:

#### Step 1: Create the branch

Branch from the **earliest full version** that the issue affects. Name it with a `dfb/` prefix:

```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git checkout -b dfb/CAR-XXXXX <earliest-version-branch>
```

Example: If CAR-30298 first appears in 2025.01, branch from `2025.01`:
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git checkout -b dfb/CAR-30298 2025.01
```

**Verify the base is a valid common ancestor.** Branching from the earliest version only works if that branch is an ancestor of **every** target version's line — then one dfb feeds them all and cerelease merges in only the fix. Confirm it:
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git merge-base --is-ancestor origin/<base-branch> origin/delta/<version>-<latest-letter> && echo OK || echo "NOT an ancestor"
```
If the base is **not** an ancestor of some target line (e.g., the issue spans divergent release lines), that version needs its own version-specific dfb — see "Multi-version backports that conflict" below.

**Check for a pre-existing dfb branch first.** If `dfb/CAR-XXXXX` already exists, inspect what it carries vs its base (`git log <base>..dfb/CAR-XXXXX`). If it's mis-based or carrying unrelated commits, delete the remote (`git push origin --delete dfb/CAR-XXXXX`) and rebuild clean rather than building on top of it.

#### Step 2: Find and cherry-pick commits

Find all commits for the issue:
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git --no-pager log --all --no-merges -i --grep="CAR-XXXXX" --pretty=format:"%h %ad %an %s" --date=short
```

**Critical rules:**
- There may be **multiple commits** per issue — include all of them
- Commits may appear **more than once** if they were cherry-picked into other branches — only include unique, relevant commits (not duplicates from other branches)
- Cherry-pick in **chronological order by full commit timestamp** (use `--pretty=format:"%h %ci %s"`) — same-day commits need the time to order correctly
- **If grep returns nothing or looks incomplete,** the commit may not reference the issue key in its message. Check any existing `dfb/CAR-XXXXX` branch, the Jira issue's linked PR, or grep the fix description instead.

**Trace each commit before picking it** with `git branch -r --contains <hash>` to:
- Identify the source line (confirms you have the right hash and a valid base)
- Confirm the fix is **not already in the target deltas** (avoids redundant or empty cherry-picks)
- Sanity-check the release grid — e.g., a fix already shipped in some versions' deltas should only target the remaining versions

```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git cherry-pick <commit-hash>
```

**If a conflict occurs during cherry-pick:**
- **Single, simple conflict:** stop and have the owner resolve it, then `git cherry-pick --continue`.
- **Building many branches in one pass:** abort the conflicted one (`git cherry-pick --abort`), keep going with the rest, and report a summary (pushed vs needs-attention) at the end instead of stopping at the first conflict.
- **A fix that conflicts on some versions but not others:** don't force a single resolution across the whole span — see "Multi-version backports that conflict" below.
- **Never guess at feature/logic resolutions headed to production** — hand them to the commit author / item owner with a written handoff (base branch, commit hash, conflicting files, target versions).

#### Step 3: Push the branch

**Branch push rule (always):** A dfb branch must be pushed to origin under its **own dfb name** — never under the branch it was created from (a `release/*` or `delta/*` branch). Because the dfb is checked out from another branch, its tracking ref points at that source branch, so a bare `git push` (or `git push origin HEAD`) can target the wrong remote branch and overwrite it. Always push with an **explicit `local:remote` refspec** naming the dfb branch on both sides, and use `-u` to repoint tracking at the dfb branch:

```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git push -u origin dfb/CAR-XXXXX:dfb/CAR-XXXXX
```

Never run a bare `git push` for a dfb branch.

After pushing, **verify the remote tip** shows the fix commit on top:
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git log -1 origin/dfb/CAR-XXXXX --pretty=format:"%h %s"
```

#### Repeat for each issue in the release plan.

#### Special case: fix already in a previous delta for some versions

Sometimes a fix needs to go into a new delta, but some versions already have prior deltas that contain related changes. In this case, branching from the release branch would **miss** those prior delta commits. Instead:

1. **For versions with prior deltas** — branch the dfb off the **latest existing delta branch** for that version (not the release branch), then cherry-pick the fix commits. Use a version-specific branch name to distinguish it:
   ```bash
   cd D:/repos/CargasEnergy.worktrees/deltas && git checkout -b dfb/CAR-XXXXX-2025.01 origin/delta/2025.01-C
   cd D:/repos/CargasEnergy.worktrees/deltas && git cherry-pick <commit1> <commit2>
   cd D:/repos/CargasEnergy.worktrees/deltas && git push -u origin dfb/CAR-XXXXX-2025.01:dfb/CAR-XXXXX-2025.01
   ```

2. **For versions without prior deltas** — use the standard dfb off the release branch:
   ```bash
   cd D:/repos/CargasEnergy.worktrees/deltas && git checkout -b dfb/CAR-XXXXX origin/release/2025.03
   cd D:/repos/CargasEnergy.worktrees/deltas && git cherry-pick <commit1> <commit2>
   cd D:/repos/CargasEnergy.worktrees/deltas && git push -u origin dfb/CAR-XXXXX:dfb/CAR-XXXXX
   ```

3. **When merging** — run separate `cerelease create-delta` commands, one per dfb branch, each targeting only its own version(s):
   ```bash
   # Version-specific dfb branches (each version gets its own command)
   cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.01" --createNextDeltaBranches --fixBranch "dfb/CAR-XXXXX-2025.01" --skipDeltaPackageBuild
   cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.02" --createNextDeltaBranches --fixBranch "dfb/CAR-XXXXX-2025.02" --skipDeltaPackageBuild

   # Standard dfb branch (covers remaining versions together)
   cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.03,2025.04" --createNextDeltaBranches --fixBranch "dfb/CAR-XXXXX" --skipDeltaPackageBuild
   ```

#### Multi-version backports that conflict

When a fix authored on a recent line must go back several versions, the cherry-pick often applies cleanly on newer versions but conflicts on older ones (the code diverged). Don't force one resolution across the whole span — map it first, then split:

1. **Build a clean/conflict matrix.** Test-pick the commit onto each target version's branch and record clean vs conflict:
   ```bash
   for B in origin/2025.09 origin/release/2025.11 origin/release/2026.01; do
     git checkout --detach "$B" >/dev/null 2>&1
     git cherry-pick <hash> >/dev/null 2>&1 && echo "$B CLEAN" || echo "$B CONFLICT"
     git cherry-pick --abort >/dev/null 2>&1
   done
   ```
2. **Group the conflict versions.** Versions whose conflicting files are byte-identical share one resolution. Compare per file with `git rev-parse <branch>:<path>` — same blob hash → same group, so one fix serves them all.
3. **Build clean ranges now** as `dfb/CAR-XXXXX-<earliest-clean-version>` off that version's branch (it feeds every newer clean version via cerelease).
4. **Handle conflict ranges** as `dfb/CAR-XXXXX-<earliest-conflict-version>` off the earliest conflict version — resolve once per group, then verify the resolution merges cleanly into each version's delta. For feature/logic conflicts, escalate with a written handoff rather than guessing.
5. **Merge each range with its own cerelease command**, scoped to its versions (see Phase 3).
6. **Hold a version's package build** until all its fixes — including any escalated ones — have landed, so you don't ship a delta missing fixes the grid calls for.

### Phase 3: Merge Fix Branches into Delta Branches

This phase merges each fix branch into the **next** delta branch for its versions — minting those next delta branches in the process. It's orchestrated by a helper that encodes the safety steps (clean tree, local-branch sync, conflict pre-check, failure detection, verification); you supply the plan and resolve anything it flags.

**Helper:** [`scripts/merge-fix-branches.sh`](scripts/merge-fix-branches.sh) — modes: `check` (preflight + sync + conflict pre-check; nothing pushed), `run` (check, then merge, then verify), `verify` (re-check origin against the plan). Run it from the vault root; it `cd`s into the delta repo itself.

#### Step 1 — Write the merge plan

One line per fix branch — `<fixbranch> <versions-csv> [create]` — derived from the release grid (Phase 1) and the dfb branches from Phase 2.

**`create` logic** (mint each next delta branch exactly once): normally the single **widest-coverage** fix branch — one spanning every version in the release — is listed **first** with `create`, and every other branch merges into the branches it minted (no `create`). If no single branch covers every version, tag enough early lines `create` so each version's next delta gets minted once.

#### Step 2 — `check` (preflight + conflict pre-check)

```bash
bash .claude/skills/delta-builder/scripts/merge-fix-branches.sh check - <<'PLAN'
dfb/CAR-32274          2025.09,2025.10,2025.11,2025.12,2026.01,2026.02,2026.03,2026.04,2026.05 create
dfb/CAR-33693-2025.09  2025.09,2025.10,2025.11,2025.12,2026.01,2026.02,2026.03
dfb/CAR-33693-2026.04  2026.04
dfb/CAR-34336          2026.01,2026.02,2026.03,2026.04
PLAN
```

It fetches, cleans the tree, refreshes each fix branch as a **local** branch, then simulates the accumulation merges per version and reports clean/conflict. Nothing is pushed. Resolve everything it flags before running.

#### Step 3 — Resolve conflicts the pre-check found

- **`module.json` (CargasPay manifest):** the newer version's manifest is usually a superset that already contains the fix's entry → resolve with `--ours`. cerelease can't (its conflict path is interactive), so merge that one version manually, then **drop that version from the branch's plan line**:
  ```bash
  cd D:/repos/CargasEnergy.worktrees/deltas
  git checkout delta/<V>-<letter> && git merge --no-ff dfb/CAR-XXXXX
  git checkout --ours -- module.json && git add module.json
  git commit --no-verify --no-edit
  git push origin delta/<V>-<letter>:delta/<V>-<letter>
  ```
- **Code conflicts:** don't guess — that version needs its own version-specific dfb (see "Multi-version backports that conflict") or author escalation. Remove the affected version(s) from the plan and handle separately.

#### Step 4 — `run` (execute + verify)

When `check` is clean, re-run with `run` and the same plan. It re-checks, runs the cerelease merges in order, and verifies each delta contains its planned fixes. If cerelease stops on a branch, resolve it and re-run with a narrowed plan.

#### cerelease behavior notes (why the helper exists)

- It merges the fix branch by its **local** name — a branch that exists only as `origin/<fb>` (e.g. a teammate's) makes it crash with `TypeError …(reading 'failed')`. The helper syncs locals first.
- It **exits 0 even when its merge step fails** — never trust the exit code; the helper greps the output for failure markers.
- On a real conflict it opens an **interactive prompt** that hangs in a headless run — so we pre-check and resolve conflicts ourselves instead of letting cerelease hit them.

### Phase 4: Build Delta Packages

Once all fix branches are merged, build each version's package with the helper — it cleans the tree before each build (stale obj/bin cause MSBuild failures), builds **one version at a time** (avoids cross-version artifact contamination), and stops on the first failed build (cerelease exits 0 even when a build fails, so it scans the output):

```bash
bash .claude/skills/delta-builder/scripts/build-packages.sh 2025.09 2025.10 2025.11 2025.12 2026.01 2026.02 2026.03 2026.04 2026.05
```

Pass only the versions you're ready to build (hold any whose fixes are still pending). Any `--flag` is passed through to cerelease — e.g. `... 2026.05 --allApps` to also build APKs.

**Manual fallback** (one version), if you need to run it by hand:
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git clean -fxd -e "CargasEnergyWeb/node_modules" && cerelease create-delta "2026.05"
```

### Phase 5: Summary Output

After completion, output a summary including:
- **Fix branches created** — issue number and branch name for each
- **Delta branches created or updated** — version and branch name for each
- **Delta packages built** — version and package name for each
- **QA coverage flags** — any issue that needed **more than one dfb branch** (its code diverged across versions). Each dfb is a separate, independent resolution, so QA must test that issue in **at least one version from each dfb's range** — a bug in one range's resolution won't surface when testing another. List the ranges per such issue.

## cerelease CLI Reference

```
USAGE
  $ cerelease create-delta START [END] [-f <value>] [-b] [-s] [-c] [-d] [--mdApk] [--msApk] [--posApk]
    [--cylExApk] [--allApk] [--allApps] [--updateContentDates <value>]

ARGUMENTS
  START  starting version, or list of versions
  END    ending version

FLAGS
  -b, --betaOnly                 only create beta delta branches
  -c, --createNextDeltaBranches  Create the next delta version branches, as opposed to merging into the most recent
                                 delta branch
  -d, --skipDeltaPackageBuild    Use this if more changes will be merged into the delta branches before building the
                                 delta packages
  -f, --fixBranch=<value>        branch with the changes to be merged into the delta branches
  -s, --stableOnly               only create stable delta branches
  --allApk                       Build all APKs
  --allApps                      Build all apps
  --cylExApk                     Build Cylinder Exchange APK
  --mdApk                        Build Mobile Delivery APK
  --msApk                        Build Mobile Service APK
  --posApk                       Build Point of Sale APK
  --updateContentDates=<value>   Update content dates
```

## Task-Based Progress Tracking

```
TaskCreate:
  subject: "Parse release plan"
  description: "Fetch Jira issue and parse the release plan table"
  activeForm: "Parsing release plan..."

TaskCreate:
  subject: "Create fix branches"
  description: "Create dfb/ branches and cherry-pick commits for each issue"
  activeForm: "Creating fix branches..."

TaskCreate:
  subject: "Merge into delta branches"
  description: "Run cerelease create-delta to merge fix branches"
  activeForm: "Merging fix branches into delta branches..."

TaskCreate:
  subject: "Build delta packages"
  description: "Run cerelease create-delta to build final packages"
  activeForm: "Building delta packages..."

TaskCreate:
  subject: "Output summary"
  description: "Summarize branches created and packages built"
  activeForm: "Generating summary..."
```

Mark each task `in_progress` when starting, `completed` when done.

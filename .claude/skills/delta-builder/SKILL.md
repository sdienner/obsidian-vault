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

#### Step 2: Find and cherry-pick commits

Find all commits for the issue:
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git --no-pager log --all --no-merges -i --grep="CAR-XXXXX" --pretty=format:"%h %ad %an %s" --date=short
```

**Critical rules:**
- There may be **multiple commits** per issue — include all of them
- Commits may appear **more than once** if they were cherry-picked into other branches — only include unique, relevant commits (not duplicates from other branches)
- Cherry-pick in chronological order

```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git cherry-pick <commit-hash>
```

**If a conflict occurs during cherry-pick:** Abort immediately and prompt the user to resolve it manually. After they resolve, use `git cherry-pick --continue` to resume.

#### Step 3: Push the branch

**Branch push rule (always):** A dfb branch must be pushed to origin under its **own dfb name** — never under the branch it was created from (a `release/*` or `delta/*` branch). Because the dfb is checked out from another branch, its tracking ref points at that source branch, so a bare `git push` (or `git push origin HEAD`) can target the wrong remote branch and overwrite it. Always push with an **explicit `local:remote` refspec** naming the dfb branch on both sides, and use `-u` to repoint tracking at the dfb branch:

```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git push -u origin dfb/CAR-XXXXX:dfb/CAR-XXXXX
```

Never run a bare `git push` for a dfb branch.

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

### Phase 3: Merge Fix Branches into Delta Branches

Use `cerelease create-delta` to merge each fix branch into the appropriate delta branches.

**Key logic for `--createNextDeltaBranches`:**

- The **first fix branch** merged should use `--createNextDeltaBranches` for ALL versions in the release plan — this creates new delta branches (e.g., `delta/2025.01-D` if `delta/2025.01-C` was the last)
- **Subsequent fix branches** that only apply to versions that already have new delta branches do NOT use `--createNextDeltaBranches`
- If a subsequent fix branch applies to versions that do NOT yet have delta branches, split into two commands: one without the flag (for versions that already have branches) and one with the flag (for new versions)

**First issue example** (applies to 2025.01 through 2025.06):
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.01,2025.02,2025.03,2025.04,2025.05,2025.06" --createNextDeltaBranches --fixBranch "dfb/CAR-30298" --skipDeltaPackageBuild
```

**Second issue example** (applies to 2025.02 through 2025.05 — all already have delta branches):
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.02,2025.03,2025.04,2025.05" --fixBranch "dfb/CAR-28519" --skipDeltaPackageBuild
```

**Third issue example** (applies to 2025.01-2025.06 AND 2025.07-2025.09 which are new):
```bash
cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.01,2025.02,2025.03,2025.04,2025.05,2025.06" --fixBranch "dfb/CAR-31235" --skipDeltaPackageBuild
cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.07,2025.08,2025.09" --createNextDeltaBranches --fixBranch "dfb/CAR-31235" --skipDeltaPackageBuild
```

### Phase 4: Build Delta Packages

Once all fix branches are merged, build each version individually — running `git clean` before each one (no `--skipDeltaPackageBuild`):

```bash
cd D:/repos/CargasEnergy.worktrees/deltas && git clean -fxd -e "CargasEnergyWeb/node_modules"
cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.01"

cd D:/repos/CargasEnergy.worktrees/deltas && git clean -fxd -e "CargasEnergyWeb/node_modules"
cd D:/repos/CargasEnergy.worktrees/deltas && cerelease create-delta "2025.02"

# ... repeat for each version in the release plan
```

**Important:** Always run `git clean -fxd -e "CargasEnergyWeb/node_modules"` before each individual build. Stale build artifacts (obj/, bin/) from prior branches cause MSBuild failures. Building one version at a time prevents cross-version artifact contamination.

### Phase 5: Summary Output

After completion, output a summary including:
- **Fix branches created** — issue number and branch name for each
- **Delta branches created or updated** — version and branch name for each
- **Delta packages built** — version and package name for each

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

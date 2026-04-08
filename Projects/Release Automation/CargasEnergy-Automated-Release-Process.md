# CargasEnergy Automated Release Process

This document describes the proposed automated release system for CargasEnergy, designed to replace the manual process documented in [CargasEnergy-Release-Process.md](./CargasEnergy-Release-Process.md). It uses GitHub Actions, self-hosted Windows runners, the Jira REST API, and Jira Automation rules to automate branch management, packaging, APK builds, and Jira housekeeping — while preserving the monthly release cadence and QA approval gates.

For branching conventions referenced throughout, see [CargasEnergy-Branching-Strategy.md](./CargasEnergy-Branching-Strategy.md).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview--how-the-new-process-works)
2. [Infrastructure Setup](#2-infrastructure-setup)
3. [Workflow 1 — Merge Accountability](#3-workflow-1--merge-accountability)
4. [Workflow 2 — Release Preparation](#4-workflow-2--release-preparation)
5. [Workflow 3 — APK Builds (Merge-Testing Only)](#5-workflow-3--apk-builds-merge-testing-only)
6. [Workflow 4 — Build & Package](#6-workflow-4--build--package)
7. [Workflow 5 — Post-Release Waterfall Merge](#7-workflow-5--post-release-waterfall-merge)
8. [Workflow 6 — Jira Release Automation](#8-workflow-6--jira-release-automation)
9. [Notification Layer](#9-notification-layer)
10. [Logging, Observability, and Confidence](#10-logging-observability-and-confidence)
11. [Transition Plan](#11-transition-plan)
12. [Verification Plan Restructuring](#12-verification-plan-restructuring)

---

## 1. Architecture Overview — How the New Process Works

This section describes the entire automated release process from start to finish. You do not need to understand the technical details in later sections to follow along here — this is the big picture.

The new process is built around **six automated workflows** that run in GitHub Actions. Some are triggered automatically (by Jira or by other workflows), and some are triggered manually by the release coordinator at key decision points. QA testing and approval gates remain human-driven — the automation handles everything around those gates.

---

### Stage 1: Ongoing Work — Merge Accountability (between releases)

This stage runs **continuously throughout the month**, not just during release time. It ensures that completed work is merged into the `rc-stable` branch in a consistent, documented way — and that developers are accountable for resolving any merge conflicts their work introduces.

**How it works:**

1. A developer completes their work on a feature, task, or bug fix. QA tests it on the developer's branch. When QA passes, the Jira item is moved to a **"Ready to Merge"** status.

2. This status change in Jira **automatically triggers** the Merge Accountability workflow in GitHub. No one has to remember to do anything — it just happens.

3. The system attempts to merge the developer's branch into `rc-stable` to check for conflicts:

   - **If there are no conflicts:** A pull request (PR) is automatically created on GitHub and assigned to the developer. Depending on configuration, one of two things happens:
     - **Auto-merge enabled (recommended):** The PR is automatically merged into `rc-stable` with no developer action needed. A comment is added to the Jira item confirming the merge. This is the fastest path and eliminates the risk of PRs sitting idle.
     - **Manual merge:** The PR is left open for the developer to review and merge themselves. A comment is added to the Jira item with a link to the PR.
     
     The auto-merge vs. manual-merge behavior is a global configuration toggle in the workflow. It can be changed at any time without modifying the workflow logic.

   - **If there are conflicts:** The PR is still created (but marked as blocked). Additionally, a **new Jira item** is created — a "Merge Conflict Worksheet" — assigned to the developer. This worksheet lists exactly which files are conflicting and provides a structured template for the developer to document:
     - Which other Jira items the conflicting code belongs to
     - How they resolved each conflict
     - Any testing notes QA should be aware of

4. The developer resolves the conflicts by merging `rc-stable` into their branch locally, resolving each conflict, and pushing the updated branch. They fill out the worksheet on the Jira item and move it to **"Ready for Testing"**.

5. When the worksheet item moves to "Ready for Testing," the system **automatically unblocks the PR** on GitHub. The developer can now merge it.

6. During the release's merge testing phase, QA can reference the conflict worksheets to understand which areas had conflicts and what extra testing may be needed.

**Why this matters:** In the current process, developers are expected to merge their own branches into `rc-stable` when QA passes — but this rarely happens. The release coordinator ends up doing it manually at release time. With this system, merges happen automatically as items are completed, conflicts are tracked and documented in Jira, and the coordinator's release prep workload is dramatically reduced.

```
    Developer's work passes QA
                │
                ▼
    Jira item → "Ready to Merge"
                │
                ▼ (automatic)
    ┌───────────────────────────────┐
    │  Merge Accountability         │
    │  Workflow                     │
    │                               │
    │  Checks for merge conflicts   │
    │  against rc-stable            │
    └───────────┬───────────────────┘
                │
        ┌───────┴────────┐
        ▼                ▼
   No conflicts      Conflicts found
        │                │
        ▼                ▼
   PR created        PR created (blocked)
   on GitHub         + Jira Conflict Worksheet
        │            created & assigned to dev
        │                │
   ┌────┴────┐           ▼
   ▼         ▼       Dev resolves conflicts,
 Auto-    Dev        fills out worksheet,
 merged   reviews    pushes updated branch
 (config) & merges       │
   │         │           ▼
   └────┬────┘    Worksheet → "Ready for Testing"
        │                │
        │                ▼ (automatic)
        │            PR unblocked
        │                │
        │                ▼
        │           Dev reviews & merges PR
        │                │
        ▼                ▼
      Merged into rc-stable
```

---

### Stage 2: Release Preparation (coordinator kicks off the release)

When the sprint testing cutoff date is reached and it's time to start a new release, the release coordinator **manually triggers** the Release Preparation workflow from the GitHub Actions page.

**The verification plan is the source of truth.** The Jira verification plan item (e.g., CAR-33903) is a structured document that explicitly lists every Jira item and every git branch that should be included in the release (see [Section 11: Verification Plan Restructuring](#11-verification-plan-restructuring) for the recommended format). The automation reads this document directly — the coordinator does not need to re-enter item lists or branch names that are already in the verification plan.

**How it works:**

1. The coordinator enters the release version (e.g., `2026.04`), the verification plan Jira key (e.g., `CAR-33903`), and optionally any commit SHAs that need to be cherry-picked. The system reads the sprint branches and item lists directly from the verification plan's structured description — no need to retype them.

2. The system performs a **comprehensive release scope audit** before doing anything. It uses the GitHub for Jira integration and the GitHub API to cross-reference what the verification plan says should be in the release against what is actually in `rc-stable`:

   - **Expected items check:** For every Jira item listed in the verification plan, the system checks whether that item has been merged into `rc-stable` (by looking for merged PRs or commits referencing the Jira key). Items are classified as:
     - **Confirmed** — merged PR or commit found in `rc-stable`
     - **Pending** — open/draft PR exists but hasn't been merged yet
     - **Missing** — no PR or commit found at all

   - **Unexpected items check:** The system also looks at all commits and merged PRs in `rc-stable` since the last release tag. Any Jira items referenced in those commits that are **not** listed in the verification plan are flagged as **unexpected** — code that is in `rc-stable` but wasn't explicitly planned for this release. This catches accidental merges or items that were added without updating the verification plan.

   The coordinator reviews this audit report before proceeding. If there are missing or unexpected items, the coordinator can stop the workflow, address the issues, and re-run.

3. The system merges each sprint branch (read from the verification plan) into `rc-stable` in order. Feature and task branches should already be there thanks to Stage 1 (Merge Accountability). If any cherry-picks were specified, those are applied as well.

4. After all merges, the system runs the scope audit **a second time** against the now-updated `rc-stable` to confirm that everything expected is present and nothing unexpected slipped in. This final audit is included in the release summary.

5. The system creates the release branch (e.g., `release/2026.04`) from the fully updated `rc-stable` and pushes it to GitHub. This automatically triggers a TeamCity build, which spins up a QA testing site.

6. A detailed summary is posted as a comment on the verification plan Jira item (including the full audit report), and a Teams notification is sent.

7. Debug-only APK builds are **automatically triggered** for the new release branch so QA can test the Android apps during merge testing.

---

### Stage 3: Merge Testing (manual QA phase)

Merge testing is a **manual QA phase** — the automation does not change how QA tests.

- QA tests the release branch QA site (spun up by TeamCity) and the debug APKs.
- Any issues found are logged as subtask bugs under the verification plan in Jira, prefixed with "Merge."
- Developers create fix branches off the release branch, open PRs, and merge fixes back in.
- This cycle repeats until QA signs off on merge testing.

---

### Stage 4: Packaging (coordinator triggers after merge testing passes)

Once QA has signed off on merge testing, the coordinator triggers **a single workflow** — Build & Package. Before it runs, it requires an **approval click** in GitHub (this approval serves as the formal "merge testing passed" gate).

This one workflow handles everything:
1. **Builds the release APKs** — both debug and production-signed APKs (both are included in the final release package)
2. **Builds the frontend** (npm + Grunt)
3. **Compiles the .NET solution**
4. **Builds the database project** (dacpac)
5. **Includes the APKs and Cordova content** in the package
6. **Assembles everything** into a versioned zip package with file manifest and metadata
7. **Validates the package** — verifies expected directories exist, counts files, checks hashes, confirms APKs are present

When complete:
- The package is automatically copied to the QA server via the network share (no more manual file copy)
- A draft GitHub Release is created with the package attached (permanent, versioned storage)
- A detailed summary is posted to the verification plan in Jira — including file counts, hashes, and APK details
- A Teams notification is sent

**One click, one workflow.** No RDP, no GUI, no juggling multiple triggers. If any step fails, full logs are available in GitHub Actions and the coordinator can retry with one click.

---

### Stage 5: Build Testing on StableRelease (manual QA phase)

Build testing remains a **manual phase**:

- The coordinator deploys the package to the StableRelease QA site using the DeployTool (this step will be automated in a separate project).
- QA tests StableRelease.
- Any issues found are logged as subtask bugs prefixed with "Build."
- Same fix cycle as merge testing: fix branches, PRs, re-package if needed.
- Once QA signs off, the release is considered complete.

---

### Stage 6: Release Distribution

After build testing passes:
- The coordinator publishes the draft GitHub Release (making it a permanent release record).
- The coordinator uploads the package to SharePoint for customer distribution.
- Customer deployments continue to be handled by the deployment specialist using the existing process (this is being modernized separately via the Phone Home system).

---

### Stage 7: Post-Release Cleanup (coordinator triggers two workflows)

After the release is distributed, the coordinator triggers two final workflows:

**Jira Release Automation:**
The coordinator **manually triggers** this workflow with the release version and verification plan key. The system:
- Reads the verification plan from Jira and extracts every item referenced in it (individual issues, sprint items, subtasks)
- Creates a Jira version for the release if one doesn't already exist
- Bulk-updates every item's Fix Version to the release version (e.g., `2026.04`)
- Transitions every item to Released/Done status
- Creates and saves a Jira filter containing all the release items
- Marks the Jira version as released

This replaces the tedious manual process of hand-building a JQL query and running a bulk update.

**Post-Release Waterfall Merge:**
The coordinator **manually triggers** this workflow with the release version and the ordered list of open sprint branches. The system merges changes down through the branch hierarchy in order:
- `release/2026.04` → `master` → `rc-stable` → earliest sprint branch → next sprint → ...

If any merge in the chain has conflicts, the system creates a pull request for that specific merge (so the coordinator can resolve it manually) and **continues** with the rest of the chain. This is strictly better than stopping on the first conflict — it reveals the full scope of merge work needed in one pass.

A summary of which merges succeeded and which need manual resolution is posted to the verification plan and sent to Teams.

---

### Pipeline Diagram

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                     ONGOING (between releases)                  │
  │                                                                 │
  │   Jira "Ready to Merge" ──► Merge Accountability Workflow       │
  │                              │                                  │
  │                     ┌────────┴─────────┐                        │
  │                     ▼                  ▼                         │
  │               No conflicts        Conflicts                     │
  │                     │                  │                         │
  │                     ▼                  ▼                         │
  │               PR created          PR (blocked)                  │
  │                     │             + Jira Worksheet               │
  │                     │                  │                         │
  │                     │             Dev resolves,                  │
  │                     │             worksheet completed            │
  │                     │                  │                         │
  │                     │             PR unblocked                   │
  │                     │                  │                         │
  │                     └───────┬──────────┘                         │
  │                             ▼                                    │
  │                   Dev merges PR into rc-stable                   │
  └─────────────────────────────────────────────────────────────────┘

                    ═══════════════════════════
                    MONTHLY RELEASE CYCLE BEGINS
                    ═══════════════════════════

  ┌─ RELEASE PREPARATION ──────────────────────────────────────────┐
  │                                                                 │
  │  Coordinator triggers ──► Release Preparation Workflow          │
  │                            • Merges sprint branches → rc-stable │
  │                            • Cherry-picks special items         │
  │                            • Creates release/2026.04 branch     │
  │                            • Posts readiness report to Jira     │
  │                                     │                           │
  │                            Auto-triggers ▼                      │
  │                            APK Build (debug-only)               │
  └─────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─ MERGE TESTING (manual QA) ────────────────────────────────────┐
  │                                                                 │
  │  QA tests release branch site + debug APKs                     │
  │  Bugs → subtask items → dev fix branches → PRs → re-test       │
  │  QA signs off                                                   │
  └─────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─ PACKAGING ────────────────────────────────────────────────────┐
  │                                                                 │
  │  Coordinator triggers ──► Build & Package Workflow              │
  │                            (requires approval gate)             │
  │                            • Builds release APKs (debug + prod) │
  │                            • Builds frontend, backend, database │
  │                            • Includes APKs & Cordova content    │
  │                            • Creates versioned zip package      │
  │                            • Validates package integrity        │
  │                            • Auto-copies to QA server           │
  │                            • Creates draft GitHub Release       │
  └─────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─ BUILD TESTING (manual QA) ────────────────────────────────────┐
  │                                                                 │
  │  Coordinator deploys to StableRelease (manual, via DeployTool)  │
  │  QA tests StableRelease                                         │
  │  Bugs → fix → re-package if needed                              │
  │  QA signs off                                                   │
  └─────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─ RELEASE DISTRIBUTION ─────────────────────────────────────────┐
  │                                                                 │
  │  Coordinator publishes GitHub Release                           │
  │  Coordinator uploads package to SharePoint                      │
  └─────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─ POST-RELEASE CLEANUP ─────────────────────────────────────────┐
  │                                                                 │
  │  Coordinator triggers ──► Jira Release Automation               │
  │                            • Bulk-sets Fix Version on all items │
  │                            • Transitions all items to Done      │
  │                            • Creates saved Jira filter          │
  │                            • Marks Jira version as released     │
  │                                                                 │
  │  Coordinator triggers ──► Post-Release Waterfall Merge          │
  │                            • release → master → rc-stable       │
  │                              → sprint/a → sprint/b → ...        │
  │                            • Creates PRs for any conflicts      │
  └─────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
                               RELEASE COMPLETE
```

### Workflow Trigger Summary

| Workflow | Trigger | Who Initiates |
|---|---|---|
| 1. Merge Accountability | Automatic (Jira status change) | No one — fires when a dev moves an item to "Ready to Merge" |
| 2. Release Preparation | Manual (coordinator clicks "Run" in GitHub Actions) | Release coordinator |
| 3. APK Build (merge-test) | Automatic (fires after Release Preparation completes) | No one — auto-triggered |
| 4. Build & Package | Manual (coordinator clicks "Run" + approval gate). Includes release APK builds as its first step. | Release coordinator |
| 5. Waterfall Merge | Manual (coordinator clicks "Run") | Release coordinator |
| 6. Jira Release Automation | Manual (coordinator clicks "Run") | Release coordinator |

### Manual vs. Automated Phase Mapping

| Current Manual Phase | Automated Workflow | What Changes |
|---|---|---|
| Phase 1: Pre-release merges into rc-stable | Workflow 1 (ongoing) + Workflow 2 | Devs merge via auto-created PRs (Workflow 1). Sprint branches merged by Workflow 2. |
| Phase 2: Release branch creation | Workflow 2 | Branch created automatically. |
| Phase 2: Manual APK trigger in TeamCity | Workflow 3 (merge-test) + Workflow 4 (release) | Debug APKs auto-triggered for merge testing. Release APKs built as part of the packaging workflow. |
| Phase 3: Merge testing | **Still manual** | QA tests on TeamCity QA site. Bug subtasks, fix branches, PRs unchanged. |
| Phase 4: Packaging (RDP + PackageTool) | Workflow 4 | Fully automated. No RDP, no GUI. Package auto-copied to QA server. |
| Phase 5: Deploy to StableRelease | **Still manual (out of scope)** | DeployTool replacement is a separate project. |
| Phase 5: Build testing | **Still manual** | QA tests StableRelease. Same bug workflow. |
| Phase 6: Release distribution | **Partially automated** | GitHub Release created as draft during packaging. SharePoint upload remains manual. |
| Phase 7: Jira updates | Workflow 6 | Fully automated — filter creation, bulk fix version, bulk status transition. |
| Phase 8: Post-release waterfall merges | Workflow 5 | Fully automated with conflict-aware PR creation. |

---

## 2. Infrastructure Setup

### 2.1 Self-Hosted Runner Installation

Two self-hosted GitHub Actions runners are required:

**Build Server Runner:**
- Label: `build-server`
- Install as a Windows service using `--runasservice`
- Must have access to: the CargasEnergy repo, `public_packaging` directory, UNC share to QA server

**QA Server Runner:**
- Label: `qa-server`
- Install as a Windows service using `--runasservice`
- Used for future automation (currently only the UNC copy targets this server)

**Installation steps (both servers):**
1. Navigate to https://github.com/Cargas/CargasEnergy/settings/actions/runners/new
2. Select "Windows" and "x64"
3. Follow the download and configuration instructions
4. During configuration:
   ```powershell
   .\config.cmd --url https://github.com/Cargas/CargasEnergy --token <TOKEN> --labels build-server --runasservice
   ```
   (Replace `build-server` with `qa-server` for the QA server runner)
5. Pin the runner version — do not enable auto-update

**Runner prerequisites (build server):**
- .NET Framework 4.8 SDK / Targeting Pack
- Visual Studio Build Tools (MSBuild 17.x)
- Node.js (LTS) + npm
- Grunt CLI (`npm install -g grunt-cli`)
- Android SDK + Cordova CLI (`npm install -g cordova`)
- Java JDK 17+ (for Android builds)
- Git for Windows
- SqlPackage (SQL Server Data-Tier Application framework)
- NuGet CLI

### 2.2 GitHub Repository Configuration

#### Secrets

Configure the following repository-level secrets at https://github.com/Cargas/CargasEnergy/settings/secrets/actions:

| Secret | Purpose |
|--------|---------|
| `JIRA_API_TOKEN` | Jira Cloud API token for a service account |
| `JIRA_USER_EMAIL` | Email of the Jira service account |
| `JIRA_BASE_URL` | `https://cargasenergy.atlassian.net` |
| `JIRA_CLOUD_ID` | `2a483932-7e78-4a63-9520-4cae9dc3e478` |
| `APK_KEYSTORE_BASE64` | Base64-encoded Android keystore for production signing |
| `APK_KEY_ALIAS` | Keystore alias |
| `APK_KEY_PASSWORD` | Key password |
| `APK_STORE_PASSWORD` | Store password |
| `BUILD_SERVER_PACKAGE_PATH` | UNC path to package output on build server |
| `QA_SERVER_PACKAGE_PATH` | UNC path for packages on QA server |
| `TEAMS_WEBHOOK_URL` | Microsoft Teams Incoming Webhook URL |
| `GH_PAT` | GitHub Personal Access Token with `repo` and `workflow` scopes (for cross-workflow triggers) |

#### Environments

Configure the following at https://github.com/Cargas/CargasEnergy/settings/environments:

| Environment | Required Reviewers | Purpose |
|---|---|---|
| `merge-testing` | None | Auto-proceeds. Used to track APK builds. |
| `packaging` | Release coordinator | Approval gate before packaging runs. Represents "QA has signed off on merge testing." |
| `release` | Release coordinator | Approval gate before release finalization. Represents "QA has signed off on build testing." |

#### Branch Protection

For `rc-stable` and `master`:
- Require pull request reviews before merging
- Require status checks to pass before merging
- Restrict who can push directly (allow only the automation service account and coordinators)

### 2.3 User Mapping

Create `.github/user-mapping.json` in the repository root. This file maps Jira account IDs to GitHub usernames:

```json
{
  "557078:673c1261-c48d-4adf-b6e2-7e84f76qc6cd": "rpschube",
  "5a2g9bb20783ea47bf51931d": "sdienner"
}
```

To find a Jira account ID, query:
```
GET https://cargasenergy.atlassian.net/rest/api/3/user/search?query=<email>
```

The `accountId` field in the response is what goes in the mapping file. Update this file whenever team members join or leave.

### 2.4 Jira Automation Rules

Two Jira Automation rules are required. Configure them at https://cargasenergy.atlassian.net/ under **Project Settings > Automation** (or global automation).

#### Rule 1: "Ready to Merge" → Create PR

- **Trigger:** When issue transitioned to "Ready to Merge" (adjust status name to match your actual workflow)
- **Condition:** Issue has a development branch linked (visible in the Development panel via the GitHub for Jira app)
- **Action:** Send web request
  - URL: `https://api.github.com/repos/Cargas/CargasEnergy/actions/workflows/merge-accountability.yml/dispatches`
  - Method: POST
  - Headers:
    - `Authorization: Bearer <GitHub PAT>` (store in Jira Automation secrets)
    - `Accept: application/vnd.github+json`
  - Body:
    ```json
    {
      "ref": "rc-stable",
      "inputs": {
        "jira_issue_key": "{{issue.key}}",
        "source_branch": "{{issue.development.branch.name}}",
        "jira_assignee_id": "{{issue.assignee.accountId}}"
      }
    }
    ```

#### Rule 2: Conflict Resolution → Unblock PR

- **Trigger:** When issue transitioned to "Ready for Testing" AND issue summary starts with "Merge Conflict:"
- **Action:** Send web request
  - URL: `https://api.github.com/repos/Cargas/CargasEnergy/actions/workflows/merge-accountability.yml/dispatches`
  - Body:
    ```json
    {
      "ref": "rc-stable",
      "inputs": {
        "mode": "unblock",
        "jira_issue_key": "{{issue.key}}"
      }
    }
    ```

### 2.5 GitHub for Jira App

The official **GitHub for Jira** integration is already installed and active for the `Cargas` organization and `cargasenergy` Atlassian site. No setup is required.

This integration provides capabilities that the automated workflows depend on:
- Automatic linking of commits, branches, and PRs to Jira issues when they contain issue keys (e.g., `CAR-12345`)
- Development panel in Jira showing branch/PR/build status — used by Jira Automation rules to resolve branch names when triggering the Merge Accountability workflow
- No custom code required

---

## 3. Workflow 1 — Merge Accountability

**File:** `.github/workflows/merge-accountability.yml`

**Purpose:** Enforce a consistent, documented process for merging completed work into `rc-stable`. When a Jira item passes QA and moves to "Ready to Merge," this workflow automatically creates a PR, detects merge conflicts, and — if conflicts exist — creates a Jira conflict worksheet that the dev must complete before the merge can proceed.

**Trigger:** `workflow_dispatch` — called automatically by Jira Automation Rule 1 (Section 2.4) when an issue transitions to "Ready to Merge."

**Inputs:**

| Input | Example | Description |
|-------|---------|-------------|
| `jira_issue_key` | `CAR-32983` | The Jira issue that is ready to merge |
| `source_branch` | `feature/CAR-32983` | The git branch to merge into rc-stable |
| `jira_assignee_id` | `557058:673c...` | Jira account ID of the assigned developer |
| `mode` | `create` or `unblock` | Default: `create`. Set to `unblock` by Rule 2 for conflict resolution. |

### Create Mode (default)

**Step 1 — Resolve GitHub username:**
Read `.github/user-mapping.json` and look up the `jira_assignee_id` to get the GitHub username for PR assignment.

**Step 2 — Check for merge conflicts:**
```bash
git fetch origin
git checkout origin/rc-stable
git merge --no-commit --no-ff origin/$SOURCE_BRANCH
```
If this succeeds without conflicts, the merge is clean. Abort the test merge (`git merge --abort`).

**Step 3a — No conflicts (clean merge):**
- Create a PR from `$SOURCE_BRANCH` → `rc-stable` using the GitHub API:
  - Title: `Merge ${JIRA_ISSUE_KEY} into rc-stable`
  - Body:
    ```markdown
    ## Jira Issue
    [${JIRA_ISSUE_KEY}](https://cargasenergy.atlassian.net/browse/${JIRA_ISSUE_KEY})

    ## Merge Status
    No merge conflicts detected. This PR is ready for review and merge.

    ---
    *Auto-created by the Merge Accountability workflow.*
    ```
  - Assignees: the resolved GitHub username
- **If auto-merge is enabled** (configurable toggle): Merge the PR immediately via the GitHub API (`PUT /repos/{owner}/{repo}/pulls/{number}/merge`). Comment on the Jira issue: "Automatically merged into rc-stable. PR: {link}."
- **If auto-merge is disabled**: Leave the PR open for the developer to review and merge. Comment on the Jira issue: "PR created: {link}. No merge conflicts detected. Please review and merge."

**Step 3b — Conflicts detected:**
- Parse the conflicting file list from git output
- Create the PR (it will show as unmergeable):
  - Same title and assignee
  - Body notes that conflicts exist and a worksheet has been created
  - Apply `merge-blocked` label to the PR
- **Create a new Jira issue** via `POST /rest/api/3/issue`:
  ```json
  {
    "fields": {
      "project": { "key": "CAR" },
      "issuetype": { "name": "Task" },
      "summary": "Merge Conflict: CAR-32983 into rc-stable",
      "assignee": { "accountId": "<jira_assignee_id>" },
      "description": "<ADF document with conflict worksheet - see below>"
    }
  }
  ```
- Link the new issue to the original issue via `POST /rest/api/3/issueLink`
- The conflict worksheet description includes:

  ```
  Merge Conflict Worksheet

  Source Branch: feature/CAR-32983
  Target Branch: rc-stable

  Conflicting Files:
  - src/CargasEnergyWeb/Pages/Invoice.aspx.cs
  - src/CargasEnergyDB/StoredProcedures/Invoice_Get.sql

  Resolution Instructions:
  1. Merge rc-stable into your branch:
     git checkout feature/CAR-32983
     git merge origin/rc-stable
  2. Resolve all conflicts listed above.
  3. For each conflict, fill in the resolution log below:
     - Which Jira items the conflicting changes belong to
     - How you resolved the conflict (which side you kept, or how you combined)
     - Any testing notes QA should be aware of
  4. Push your updated branch.
  5. Move this item to "Ready for Testing" when complete.

  Conflict Resolution Log:
  | File | Conflicting Jira Item(s) | Resolution | Testing Notes |
  |------|--------------------------|------------|---------------|
  |      |                          |            |               |
  ```

- Comment on the original Jira issue:
  > "Merge conflicts detected when attempting to merge into rc-stable. A conflict worksheet has been created: {link to new issue}. Please resolve the conflicts before this item can be merged."

### Unblock Mode

Triggered by Jira Automation Rule 2 when the "Merge Conflict: ..." issue transitions to "Ready for Testing."

**Steps:**
1. Find the open PR from `source_branch` → `rc-stable` that has the `merge-blocked` label
2. Check if the PR is now mergeable (the dev should have resolved conflicts and pushed)
3. If mergeable:
   - Remove the `merge-blocked` label
   - Comment on the PR: "Conflicts have been resolved. PR is ready for review and merge."
4. If still not mergeable:
   - Comment on the PR: "PR still has conflicts. Please verify that you pushed your conflict resolution."

### Key Benefits
- **Accountability:** Every merge conflict is tracked as a Jira issue with a documented resolution
- **Visibility:** QA has testing notes for conflicted areas, available during merge testing
- **Consistency:** Every dev follows the same process — no more ad-hoc merges
- **Traceability:** Conflict resolution log captures which Jira items were involved in each conflict

---

## 4. Workflow 2 — Release Preparation

**File:** `.github/workflows/release-prepare.yml`

**Purpose:** Merge remaining sprint branches into `rc-stable`, cherry-pick special items, and create the release branch. This replaces the manual Phase 1 and Phase 2 of the current process.

**Trigger:** `workflow_dispatch` — manually triggered by the release coordinator when the sprint testing cutoff date is reached.

**Inputs:**

| Input | Example | Description |
|-------|---------|-------------|
| `release_version` | `2026.04` | Version identifier for this release |
| `verification_plan_key` | `CAR-33903` | Jira key of the verification plan |
| `cherry_pick_commits` | `abc1234,def5678` | Optional. Comma-separated commit SHAs for items that must be cherry-picked rather than branch-merged |

**Design note:** Sprint branches and item lists are read directly from the verification plan's structured description (see [Section 12](#12-verification-plan-restructuring)) — the coordinator does not need to re-enter them. Feature and task branches should already be in `rc-stable` via Workflow 1 (Merge Accountability). Sprint branches are the primary items that always need explicit merging at release prep time.

### Steps

**Step 1 — Release Scope Audit (pre-merge):**
Query the Jira REST API for the verification plan:
```
GET /rest/api/3/issue/{verification_plan_key}?fields=description,subtasks
```
Parse the structured description to extract:
- Sprint branch names (from the "Sprint Branches" section)
- All `CAR-#####` issue key references
- All subtask keys
- Cherry-pick items and commit SHAs

Then perform a **two-way scope audit** using the GitHub API and the GitHub for Jira integration:

**Expected items check:** For every Jira item listed in the verification plan, check whether it has been merged into `rc-stable`:
- Look for merged PRs targeting `rc-stable` that reference the Jira key
- Look for commits on `rc-stable` (since the last release tag) that reference the Jira key
- Classify each item as: **Confirmed** (in rc-stable), **Pending** (open PR), or **Missing** (no PR/commit found)

**Unexpected items check:** Examine all commits on `rc-stable` since the last release tag (`git log v{previous_version}..rc-stable`). Extract Jira keys from commit messages, branch names, and PR titles. Flag any keys that appear in the commit history but are **not** listed in the verification plan as **Unexpected** — code that landed in `rc-stable` without being part of the release plan.

Generate a detailed audit report and output it to the workflow log and step summary. The coordinator reviews this report before the workflow proceeds to merging. If critical items are missing or unexpected items are present, the coordinator can cancel the workflow, address the issues, and re-run.

**Log output example:**
```
=== RELEASE SCOPE AUDIT (pre-merge) ===
Verification plan: CAR-33903 (2026.04)

EXPECTED ITEMS: 47 total
  Confirmed (in rc-stable):  39
  Pending (open PR):          5
    - CAR-33449: PR #892 (draft) — feature/CAR-33449
    - CAR-33768: PR #901 (open) — task/CAR-33768
    - ...
  Missing (no PR/commit):     3
    - CAR-32825: No PR or commit referencing this key found
    - ...

UNEXPECTED ITEMS (in rc-stable but not in verification plan): 2
    - CAR-34102: Merged via PR #887 on 2026-03-28
    - CAR-34150: Commit abc1234 on 2026-04-01

Sprint branches to merge: sprint/2026.e, sprint/2026.f
Cherry-picks requested: (none)
```

**Step 2 — Merge Sprint Branches:**
For each sprint branch extracted from the verification plan description:
```bash
git fetch origin
git checkout rc-stable
git pull origin rc-stable
git merge origin/sprint/2026.e --no-ff -m "Merge sprint/2026.e into rc-stable for release 2026.04"
```
- On success: log the merge commit SHA and continue to the next branch
- On conflict: stop the workflow immediately. Create a GitHub issue assigned to the coordinator with the conflict details and file list. Send a Teams notification. The coordinator must resolve the conflict manually and re-run the workflow.

**Step 3 — Cherry-Pick Special Items:**
For each SHA in `cherry_pick_commits` (from workflow input or from the verification plan's "Cherry-Pick Items" section):
```bash
git cherry-pick <SHA>
```
Same conflict handling as Step 2.

**Step 4 — Push rc-stable:**
```bash
git push origin rc-stable
```

**Step 5 — Release Scope Audit (post-merge):**
Re-run the same scope audit from Step 1 against the now-updated `rc-stable`. This confirms that all expected items are now present after the sprint merges and cherry-picks. The post-merge audit should show:
- Fewer "Missing" items than the pre-merge audit (the sprint merges should have resolved many)
- The same or fewer "Unexpected" items

Both the pre-merge and post-merge audits are included in the final summary, allowing the coordinator to see exactly what changed.

**Step 6 — Create Release Branch:**
```bash
git checkout -b release/2026.04
git push -u origin release/2026.04
```
Pushing this branch to GitHub:
- Triggers the existing TeamCity build (during the hybrid transition phase), which spins up the QA site for merge testing
- Triggers Workflow 3 (APK Build) in debug-only mode automatically

**Step 7 — Post Summary to Jira:**
Comment on the verification plan via Jira REST API:
> **Release Preparation Complete**
> - Release branch: `release/2026.04` ([view on GitHub]({link}))
> - Sprint branches merged: sprint/2026.e, sprint/2026.f
> - Commits cherry-picked: abc1234, def5678
>
> **Scope Audit (post-merge):**
> - Expected items: {N} total — {X} confirmed, {Y} pending, {Z} missing
> - Unexpected items: {N}
> - [Full audit details in workflow log]({link})
>
> Merge testing can begin.

**Step 8 — Teams Notification:**
> Release branch `release/2026.04` created. Merge testing can begin.
> [View workflow run]({link})

---

## 5. Workflow 3 — APK Builds (Merge-Testing Only)

**File:** `.github/workflows/apk-build.yml`

**Purpose:** Build debug-only Android APKs for QA to test during the merge testing phase. This workflow is triggered automatically when the release branch is created — no manual intervention needed.

Release APK builds (debug + production) are handled as part of Workflow 4 (Build & Package), not as a separate workflow.

**Trigger:** `workflow_run` — automatically triggered when Workflow 2 (Release Preparation) completes successfully.

**Runs on:** Self-hosted `build-server` runner (has Android SDK, Cordova, Java installed)

### Steps

**Step 1 — Checkout:**
```bash
git checkout release/2026.04
git pull
```

**Step 2 — Install Dependencies:**
```bash
cd <cordova project directory>
npm install
cordova platform add android  # if not already present
```

**Step 3 — Build Debug APKs:**
```bash
cordova build android --debug
```

**Step 4 — Upload Artifacts:**
Upload debug APK files as GitHub Actions artifacts attached to the workflow run.
Retention: 90 days.

**Step 5 — Report:**
Comment on verification plan Jira item:
> Merge-testing APK build complete.
> - Debug APKs: [Download from GitHub Actions]({link})

---

## 6. Workflow 4 — Build & Package

**File:** `.github/workflows/release-package.yml`

**Purpose:** The single end-to-end packaging workflow. Builds release APKs, compiles the web application, builds the database project, assembles all components, validates the output, and produces the final versioned zip. This replaces both the manual TeamCity APK trigger and the PackageTool Windows Forms application (`Ancillary-Projects/Deploy/Package/Package.cs`).

**Trigger:** `workflow_dispatch` — manually triggered by the coordinator after QA signs off on merge testing.

**Environment:** `packaging` — requires manual approval before execution (the approval step serves as the formal "merge testing passed" gate).

**Inputs:**

| Input | Example | Description |
|-------|---------|-------------|
| `release_version` | `2026.04` | Version identifier |
| `release_branch` | `release/2026.04` | Branch to build from |
| `verification_plan_key` | `CAR-33903` | For status reporting |

**Runs on:** Self-hosted `build-server` runner

### Steps

Each step below mirrors a corresponding method in `Package.cs` from the existing PackageTool, with the addition of APK builds and validation steps.

**Step 1 — Git Setup** *(mirrors `ValidateGitStatus`)*
```powershell
git checkout release/2026.04
git reset --hard origin/release/2026.04
git clean -fdx
git pull
```

**Step 2 — Build Release APKs**
Build both debug and production APKs as part of this workflow (no separate manual trigger needed):
```bash
cd <cordova project directory>
npm install
cordova platform add android

# Debug APKs
cordova build android --debug

# Production APKs (signed)
cordova build android --release \
  --keystore=release.keystore \
  --alias=$APK_KEY_ALIAS \
  --storePassword=$APK_STORE_PASSWORD \
  --password=$APK_KEY_PASSWORD
```
Copy APKs to `public_packaging/{version}/` for inclusion in the package.
Log: APK file names, sizes, and signing status.

**Step 3 — Frontend Build** *(mirrors `NPMTask` + `GruntTask`)*
```powershell
cd $repoPath
npm install
npx grunt deploytasks
```

**Step 4 — Copy Cordova/APK Content** *(mirrors `CopyCordovaAndAPKsTask`)*
```powershell
Copy-Item -Path "$env:BUILD_SERVER_PACKAGE_PATH\public_packaging\2026.04\*" `
  -Destination "$repoPath\<cordova output dir>\" -Recurse -Force
```

**Step 5 — Set Deploy Scripts** *(mirrors `SetDeployScripts`)*
Inject the release version into `predeployment.sql` and `postdeployment.sql`:
- The pre-deployment script inserts a `cDeployment` record and sets database trustworthiness
- The post-deployment script calls `Util_UpdateSolutionAfterServicePack`
- Version replacement uses regex to update the version token in the SQL files

**Step 6 — Build Solution** *(mirrors `Build`)*
```powershell
# Restore NuGet packages
dotnet restore Release.sln

# Build web project
msbuild CargasEnergyWeb\CargasEnergyWeb.csproj `
  /t:Build /p:Configuration=Release /m

# Build database project
msbuild CargasEnergyDB\CargasEnergyDB.sqlproj `
  /t:Build /p:Configuration=Release
```

**Step 7 — Assemble Package** *(mirrors `CreatePackage`)*
```powershell
$pkgDir = "$destinationPath\2026.04"
New-Item -ItemType Directory -Path "$pkgDir\database" -Force
New-Item -ItemType Directory -Path "$pkgDir\web" -Force

# Copy dacpac + SQL scripts
Copy-Item "CargasEnergyDB\bin\Release\CargasEnergyDB.dacpac" "$pkgDir\database\"
Copy-Item "predeployment.sql" "$pkgDir\database\"
Copy-Item "postdeployment.sql" "$pkgDir\database\"

# Copy web files with exclusion filtering (excludeFromHF.txt)
# Only copy files whose MD5 hash differs from the previous manifest
# Generate DeployedFiles.manifest with hash of each included file
# Generate PackageInfo.json with package metadata
```

The web file copy logic:
1. Load exclusion patterns from `excludeFromHF.txt` (excludes node_modules, build artifacts, configs, etc.)
2. If a previous `DeployedFiles.manifest` exists, load it for hash comparison
3. Walk the compiled web directory, calculate MD5 hash for each file
4. Skip files matching exclusion patterns
5. Only copy files that are new or changed (hash differs from previous manifest)
6. Write the new `DeployedFiles.manifest` — a text file with `filepath:md5hash` pairs
7. Write `PackageInfo.json`:
   ```json
   {
     "PackageType": 1,
     "Version": "2026.04",
     "Modules": []
   }
   ```

**Step 8 — Build Module Packages** *(mirrors `BuildAllModules`)*
If `module.json` exists in the repo root:
- Parse the module definitions
- For each module: build a separate dacpac from the specified SQL files, copy matching web files, create a module-specific `PackageInfo.json`, and zip into `{moduleName} {version}.zip`

**Step 9 — Compress**
```powershell
Compress-Archive -Path "$pkgDir\*" -DestinationPath "$destinationPath\2026.04.zip" -CompressionLevel Optimal

# Calculate MD5 hash
$hash = (Get-FileHash "$destinationPath\2026.04.zip" -Algorithm MD5).Hash
Write-Output "Package hash: $hash"
```

**Step 10 — Validate Package Integrity**
Before distributing the package, perform automated validation checks to ensure the package is correct and complete:

```powershell
# Extract the zip to a temp directory for inspection
Expand-Archive -Path "$destinationPath\2026.04.zip" -DestinationPath "$tempDir\verify"

# Validate expected directory structure
Assert-Path "$tempDir\verify\database\CargasEnergyDB.dacpac"
Assert-Path "$tempDir\verify\database\predeployment.sql"
Assert-Path "$tempDir\verify\database\postdeployment.sql"
Assert-Path "$tempDir\verify\web\"
Assert-Path "$tempDir\verify\PackageInfo.json"
Assert-Path "$tempDir\verify\web\DeployedFiles.manifest"

# Validate APKs are present in the web directory
$apkCount = (Get-ChildItem "$tempDir\verify" -Filter *.apk -Recurse).Count
Assert ($apkCount -ge 2) "Expected at least 2 APKs (debug + release), found $apkCount"

# Validate PackageInfo.json contents
$pkgInfo = Get-Content "$tempDir\verify\PackageInfo.json" | ConvertFrom-Json
Assert ($pkgInfo.Version -eq "2026.04") "Version mismatch in PackageInfo.json"
Assert ($pkgInfo.PackageType -eq 1) "PackageType should be 1 (Release)"

# Log detailed package summary
$webFileCount = (Get-ChildItem "$tempDir\verify\web" -Recurse -File).Count
$totalSize = (Get-Item "$destinationPath\2026.04.zip").Length / 1MB
Write-Output "=== PACKAGE VALIDATION PASSED ==="
Write-Output "  Version:    2026.04"
Write-Output "  Zip size:   $([math]::Round($totalSize, 2)) MB"
Write-Output "  MD5 hash:   $hash"
Write-Output "  Web files:  $webFileCount"
Write-Output "  APKs:       $apkCount"
Write-Output "  Dacpac:     present"
Write-Output "  Manifest:   present"
```

If any validation check fails, the workflow fails immediately with a clear error message describing what's wrong. The package is not distributed until all checks pass.

**Step 11 — Upload & Distribute:**

1. **GitHub Actions artifact:** Upload `2026.04.zip` with 365-day retention
2. **GitHub Release:** Create a draft release tagged `v2026.04` with the zip attached:
   ```bash
   gh release create v2026.04 \
     --title "Release 2026.04" \
     --notes "Release package for 2026.04. See verification plan: CAR-33903." \
     --draft \
     2026.04.zip
   ```
3. **Copy to QA server:** Copy the zip to the QA server via UNC path:
   ```powershell
   Copy-Item "$destinationPath\2026.04.zip" "$env:QA_SERVER_PACKAGE_PATH\" -Force
   ```
4. **Verify QA server copy:** Confirm the file exists on the QA server and the hash matches:
   ```powershell
   $qaHash = (Get-FileHash "$env:QA_SERVER_PACKAGE_PATH\2026.04.zip" -Algorithm MD5).Hash
   Assert ($qaHash -eq $hash) "QA server copy hash mismatch! Expected $hash, got $qaHash"
   ```

**Step 12 — Report:**
Comment on verification plan Jira item:
> **Release Package Built**
> - Package: `2026.04.zip`
> - Size: {size} MB | MD5: {hash} | Web files: {count} | APKs: {count}
> - Validation: **PASSED** (all integrity checks passed)
> - [GitHub Release (draft)]({link})
> - [GitHub Actions artifacts]({link})
> - Package copied to QA server at `{QA_SERVER_PACKAGE_PATH}` (hash verified)
>
> Ready for StableRelease deployment and build testing.

Teams notification with the same summary.

### Key Improvements Over PackageTool
- **Reproducible:** Same inputs produce the same output, every time
- **Observable:** Full build logs in GitHub Actions — no more squinting at a WinForms textbox or wondering what went wrong
- **Validated:** Automated integrity checks confirm the package is correct before it's distributed
- **Retriable:** If the build fails, click "Re-run" in the GitHub Actions UI
- **Artifact management:** Package automatically uploaded to GitHub Releases for permanent, versioned storage
- **No RDP required:** No need to remote into the build server
- **Auto-distribution:** Package automatically copied to QA server via UNC share (hash-verified)

---

## 7. Workflow 5 — Post-Release Waterfall Merge

**File:** `.github/workflows/release-merge-cascade.yml`

**Purpose:** Perform the post-release waterfall merge sequence: `release/{version}` → `master` → `rc-stable` → earliest sprint → next sprint → ... This replaces the manual Phase 8 of the current process.

**Trigger:** `workflow_dispatch` — manually triggered by the coordinator after the release is complete.

**Inputs:**

| Input | Example | Description |
|-------|---------|-------------|
| `release_version` | `2026.04` | Release version |
| `sprint_branches` | `sprint/2026.g`<br>`sprint/2026.h` | Ordered list of open sprint branches (earliest first) |
| `verification_plan_key` | `CAR-33903` | For status reporting |

### Steps

The workflow constructs the full merge chain:
```
release/2026.04 → master → rc-stable → sprint/2026.g → sprint/2026.h
```

For each merge pair in the chain:

**Attempt the merge:**
```bash
git checkout <target>
git pull origin <target>
git merge origin/<source> --no-ff -m "Post-release merge: <source> → <target>"
```

**If the merge is clean:**
```bash
git push origin <target>
```
Log success, move to the next pair.

**If conflicts exist:**
```bash
git merge --abort
```
- Create a PR from `<source>` → `<target>` with conflict details in the body:
  ```markdown
  ## Post-Release Waterfall Merge Conflict

  **Source:** `<source>`
  **Target:** `<target>`
  **Release:** 2026.04

  ### Conflicting Files
  - path/to/file1.cs
  - path/to/file2.sql

  This merge conflict occurred during the post-release waterfall cascade.
  Please resolve the conflicts and merge this PR to continue the cascade.
  ```
- Assign to the release coordinator
- **Continue** to the next merge pair — do not block the rest of the cascade. For the next merge, use the conflicting target branch as-is (the subsequent merge may or may not also conflict).

**Summary report:**
After all merge pairs have been attempted, comment on the verification plan:
> **Post-Release Waterfall Merges Complete**
> - `release/2026.04` → `master`: Clean
> - `master` → `rc-stable`: Clean
> - `rc-stable` → `sprint/2026.g`: **Conflict** — [PR #123]({link})
> - `sprint/2026.g` → `sprint/2026.h`: Clean
>
> {1} conflict(s) require manual resolution.

Teams notification with the same summary.

### Conflict Strategy

The workflow does not stop on conflicts. It creates a PR for the conflicting merge and moves on. This means:
- Downstream merges may also conflict (because the upstream conflict wasn't resolved yet)
- The coordinator resolves conflict PRs **in order** (top of chain first)
- Once a conflict PR is merged, any downstream PRs that were also conflicting may auto-resolve

This approach is strictly better than stopping on the first conflict, because it reveals the full scope of merge work needed rather than drip-feeding one conflict at a time.

---

## 8. Workflow 6 — Jira Release Automation

**File:** `.github/workflows/jira-release-update.yml`

**Purpose:** Automatically construct the JQL filter, bulk-update all release items with the correct Fix Version, transition them to Released/Done, and mark the Jira version as released. This replaces the tedious manual Phase 7 of the current process.

**Trigger:** `workflow_dispatch` — manually triggered by the coordinator post-release.

**Inputs:**

| Input | Example | Description |
|-------|---------|-------------|
| `release_version` | `2026.04` | Version identifier to create/use as Fix Version |
| `verification_plan_key` | `CAR-33903` | Jira verification plan to extract items from |
| `additional_issue_keys` | `CAR-33779,CAR-34001` | Optional. Extra keys not captured by automatic extraction. |

### Steps

**Step 1 — Fetch Verification Plan:**
```
GET /rest/api/3/issue/CAR-33903?fields=description,subtasks
```
Parse the description text for all `CAR-#####` patterns using regex. Collect all subtask keys from the `subtasks` field.

**Step 2 — Resolve Sprint Items:**
Extract sprint names from the verification plan description (e.g., references to "2026.e", "2026.f"). For each sprint name:
```
POST /rest/api/3/search/jql
{
  "jql": "sprint = '2026.e' AND project = CAR",
  "fields": ["key"],
  "maxResults": 200
}
```
Paginate through results collecting all issue keys.

**Step 3 — Combine & Deduplicate:**
Merge all collected keys into a single deduplicated list:
- Keys parsed from the verification plan description
- Subtask keys
- Sprint query results
- `additional_issue_keys` from the input

**Step 4 — Create Jira Version (if needed):**
```
GET /rest/api/3/project/CAR/versions
```
Check if version `2026.04` already exists. If not:
```
POST /rest/api/3/version
{
  "name": "2026.04",
  "project": "CAR",
  "projectId": 10000,
  "description": "April 2026 Release",
  "released": false
}
```

**Step 5 — Bulk Set Fix Version:**
Use the bulk edit endpoint for efficiency:
```
POST /rest/api/3/bulk/issues/fields
{
  "editedFieldsInput": {
    "fixVersions": {
      "add": { "name": "2026.04" }
    }
  },
  "selectedIssueIdsOrKeys": ["CAR-101", "CAR-102", ...],
  "sendBulkNotification": false
}
```
This is an async operation. Poll the returned task ID until complete:
```
GET /rest/api/3/task/{taskId}
```

**Step 6 — Transition Issues to Released/Done:**
There is no bulk transition endpoint in the Jira REST API. Each issue must be transitioned individually:

```bash
for ISSUE in $ALL_ISSUE_KEYS; do
  # Get available transitions
  TRANSITIONS=$(curl -s -X GET \
    -H "Authorization: Basic $AUTH" \
    "https://cargasenergy.atlassian.net/rest/api/3/issue/$ISSUE/transitions")

  # Find the "Done" or "Released" transition ID
  TRANS_ID=$(echo $TRANSITIONS | jq -r '.transitions[] | select(.name=="Done" or .name=="Released") | .id' | head -1)

  if [ -n "$TRANS_ID" ]; then
    # Execute transition
    curl -s -X POST \
      -H "Authorization: Basic $AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"transition\":{\"id\":\"$TRANS_ID\"}}" \
      "https://cargasenergy.atlassian.net/rest/api/3/issue/$ISSUE/transitions"
  fi

  # Rate limit: ~100 requests per 10 seconds
  sleep 0.1
done
```

Log successes and failures. Some issues may not have the expected transition available (e.g., already Done, or in a status that doesn't allow direct transition to Done). These are logged as warnings, not failures.

**Step 7 — Create Saved Filter:**
Construct the JQL from all collected keys and create a named filter:
```
POST /rest/api/3/filter
{
  "name": "Release 2026.04 Items",
  "jql": "key in (CAR-101, CAR-102, CAR-103, ...) ORDER BY key ASC",
  "description": "All items included in the 2026.04 release. Auto-generated.",
  "favourite": true
}
```
Set filter permissions to share with the project:
```
POST /rest/api/3/filter/{id}/permission
{
  "type": "project",
  "projectId": "10000"
}
```

**Step 8 — Mark Version as Released:**
```
PUT /rest/api/3/version/{versionId}
{
  "released": true,
  "releaseDate": "2026-04-17"
}
```

**Step 9 — Report:**
Comment on verification plan:
> **Jira Release Automation Complete**
> - Issues processed: {N}
> - Fix Version set: {N} successes, {M} failures
> - Status transitioned: {N} successes, {M} failures
> - Saved filter: [Release 2026.04 Items]({link})
> - Jira version `2026.04` marked as released
>
> Failed items (if any):
> - CAR-XXXXX: {reason}

Teams notification with the same summary.

---

## 9. Notification Layer

### GitHub (Primary)

All workflows use two GitHub notification mechanisms:

1. **Jira Comments:** Every workflow posts a structured status comment on the verification plan Jira item via REST API. This creates a chronological log of all release activity directly on the Jira ticket.

2. **GitHub Step Summary:** Each workflow writes a summary to `$GITHUB_STEP_SUMMARY`, visible on the workflow run page. This provides quick at-a-glance status without digging into logs.

3. **Issues & PRs:** Conflict PRs and GitHub Issues created by workflows generate standard GitHub notifications for assigned users.

### Microsoft Teams (Secondary)

Each workflow sends a Teams notification card on completion (success or failure).

**Implementation:** Create a reusable composite action at `.github/actions/notify-teams/action.yml`:

```yaml
name: 'Notify Teams'
description: 'Send a notification card to Microsoft Teams'
inputs:
  webhook_url:
    required: true
  workflow_name:
    required: true
  status:
    required: true
  release_version:
    required: true
  summary:
    required: true
  run_url:
    required: true
runs:
  using: 'composite'
  steps:
    - name: Send Teams notification
      shell: bash
      run: |
        COLOR=$([[ "${{ inputs.status }}" == "success" ]] && echo "00ff00" || echo "ff0000")
        curl -s -X POST "${{ inputs.webhook_url }}" \
          -H "Content-Type: application/json" \
          -d '{
            "@type": "MessageCard",
            "themeColor": "'"$COLOR"'",
            "summary": "${{ inputs.workflow_name }} - ${{ inputs.status }}",
            "sections": [{
              "activityTitle": "${{ inputs.workflow_name }}",
              "activitySubtitle": "Release ${{ inputs.release_version }}",
              "facts": [
                { "name": "Status", "value": "${{ inputs.status }}" },
                { "name": "Summary", "value": "${{ inputs.summary }}" }
              ],
              "potentialAction": [{
                "@type": "OpenUri",
                "name": "View Workflow Run",
                "targets": [{ "os": "default", "uri": "${{ inputs.run_url }}" }]
              }]
            }]
          }'
```

Each workflow calls this at the end:
```yaml
- uses: ./.github/actions/notify-teams
  if: always()
  with:
    webhook_url: ${{ secrets.TEAMS_WEBHOOK_URL }}
    workflow_name: "Release Preparation"
    status: ${{ job.status }}
    release_version: ${{ inputs.release_version }}
    summary: "Release branch release/2026.04 created. Merge testing can begin."
    run_url: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

---

## 10. Logging, Observability, and Confidence

The most important property of these workflows is that the team can **trust** them. A release built by automation must be at least as reliable as one built by hand — and ideally more so, because the automation is consistent, transparent, and verifiable in ways a manual process never can be. Every design decision below serves this goal.

### Verbose, Structured Logging

Every workflow step must produce clear, human-readable log output. The guiding principle is: **if a workflow fails, anyone on the team should be able to read the logs and understand exactly what happened without asking the person who wrote the workflow.**

Specific requirements:
- **Every step starts with a log line** stating what it is about to do: `"Step 3: Building frontend (npm install + grunt deploytasks)..."`
- **Every step ends with a log line** confirming success or reporting failure: `"Step 3: Frontend build complete. 0 warnings, 0 errors."`
- **All external command output** (npm, msbuild, grunt, cordova, git) is streamed to the workflow log in real time — not suppressed or captured silently
- **All file operations** log what they're doing: `"Copying 1,247 web files to package directory..."`, `"Skipping 892 unchanged files (hash match)..."`, `"APK copied: app-debug.apk (14.3 MB)"`
- **Error messages are actionable:** Not just "Step failed" but "MSBuild failed with exit code 1. See the build output above for the specific error. Common causes: missing NuGet packages, syntax errors, project reference issues."

### GitHub Actions Step Summaries

Every workflow writes a structured summary to `$GITHUB_STEP_SUMMARY` at the end of each run. This summary appears on the workflow run page and provides a quick at-a-glance report without digging into logs.

Example summary for the Build & Package workflow:
```markdown
## Build & Package — 2026.04

| Step | Status | Duration | Details |
|------|--------|----------|---------|
| Git setup | Passed | 12s | Branch: release/2026.04, commit: abc1234 |
| APK build (debug) | Passed | 3m 22s | 1 APK, 14.3 MB |
| APK build (release) | Passed | 4m 11s | 1 APK, 13.8 MB, signed |
| Frontend build | Passed | 2m 45s | npm: 0 warnings, grunt: 0 warnings |
| Solution build | Passed | 5m 18s | msbuild: 0 errors, 0 warnings |
| Database build | Passed | 1m 02s | dacpac generated |
| Package assembly | Passed | 48s | 1,247 web files, 2 APKs |
| Validation | Passed | 5s | All integrity checks passed |
| Distribution | Passed | 22s | GitHub Release + QA server copy verified |

**Package:** 2026.04.zip (187.4 MB, MD5: a1b2c3d4...)
**Total duration:** 18m 15s
```

### Validation Gates

Every workflow includes validation checks that **fail the workflow** if something is wrong. These are not optional or informational — they are hard gates:

- **Build & Package:** Package integrity validation (Step 10) confirms all expected files, directories, APKs, and metadata are present and correct. QA server copy hash is verified against the source.
- **Release Preparation:** Scope audit confirms expected items are present and flags unexpected items. The audit runs both before and after merges.
- **Merge Accountability:** Conflict detection uses actual git merge attempts (not heuristics) to produce accurate conflict reports.
- **Jira Release Automation:** Each API call's response is checked. Failed transitions are logged with the specific reason (e.g., "CAR-12345: transition 'Done' not available from current status 'In Progress'").
- **Waterfall Merge:** Each merge is verified by checking that the target branch tip includes the source branch tip after push.

### Reproducibility

The same inputs to any workflow must produce the same outputs. This means:
- All dependency versions are locked (npm `package-lock.json`, NuGet `packages.config`)
- Git state is explicit — every workflow resets to the exact branch/commit before starting
- Build configuration is explicit — `Configuration=Release` is always specified, never inferred
- Timestamps or build numbers in the package are deterministic from the inputs (version, branch, commit SHA)

### Debugging Failed Workflows

When a workflow fails:
1. **The log output is complete** — every command's stdout/stderr is captured
2. **The step summary shows which step failed** and how far the workflow got
3. **Artifacts are preserved even on failure** — partial build outputs, log files, and diagnostic information are uploaded as artifacts so they can be inspected
4. **The Jira comment includes the failure** — "Build & Package FAILED at Step 6 (Solution build). [View logs]({link})"
5. **Re-running is safe** — every workflow is designed to be re-run from scratch. No leftover state from a failed run can cause a subsequent run to produce incorrect results.

---

## 11. Transition Plan

The transition from the current manual process to the automated system is incremental. Both systems coexist during migration. Each phase runs the new automation alongside the existing manual process for at least one release cycle to validate. **No manual process is decommissioned until the automated replacement has been validated for at least one full release cycle.**

### Phase A — Foundation (1-2 weeks)

**Goal:** Set up infrastructure. No process changes yet.

| Task | Details |
|------|---------|
| Install self-hosted runner on build server | Label: `build-server`, run as Windows service |
| Install self-hosted runner on QA server | Label: `qa-server`, run as Windows service |
| Configure GitHub repository secrets | All secrets listed in Section 2.2 |
| Configure GitHub environments | `merge-testing`, `packaging`, `release` with appropriate reviewers |
| Create `.github/user-mapping.json` | Map all current devs' Jira account IDs to GitHub usernames |
| Install GitHub for Jira app | Follow steps in Section 2.5 |
| Configure Jira Automation rules | Rules 1 and 2 from Section 2.4 |

### Phase B — Low-Risk Automation (1 release cycle)

**Goal:** Automate the lowest-risk, highest-value workflows first.

| Workflow | Why First | Validation |
|----------|-----------|------------|
| **Workflow 6: Jira Release Automation** | Lowest risk (read-only until the update step), eliminates the most tedious manual work (JQL construction + bulk update). Easy to verify — compare the filter output against a manually constructed filter. | Run both manual and automated Jira updates for one release. Compare results. |
| **Workflow 5: Waterfall Merges** | High value (saves significant coordinator time), low risk (creates PRs on conflict rather than force-pushing). Easy to verify — check that all branches received the merges. | Run the workflow, then verify each branch has the expected merge commit. |
| **Workflow 1: Merge Accountability** | Starts building the conflict tracking habit early. Doesn't disrupt existing sprint workflow — adds PRs and worksheets on top of it. | Monitor for one cycle. Verify PRs are created correctly and conflict worksheets contain accurate file lists. |

### Phase C — Build Automation (1 release cycle)

**Goal:** Automate APK builds and release preparation.

| Workflow | Validation |
|----------|------------|
| **Workflow 3: APK Builds** | Run APK builds via both GitHub Actions and TeamCity in parallel. Compare the APK outputs. QA tests the GitHub Actions APKs. |
| **Workflow 2: Release Preparation** | Use for sprint branch merges and release branch creation. Verify the release branch contains all expected items by comparing against the manual process. |

### Phase D — Packaging Automation (1 release cycle)

**Goal:** Replace PackageTool with the automated packaging workflow.

| Workflow | Validation |
|----------|------------|
| **Workflow 4: Build & Package** | Run both PackageTool and the GitHub Actions workflow in parallel. Compare output packages (file list, hashes, zip contents). QA tests the GitHub Actions package. |

This is the highest-risk phase because the packaging workflow replicates the most complex logic from Package.cs. Running both in parallel for a full cycle is essential.

### Phase E — Steady State

**Goal:** Decommission legacy tools.

| Action | Details |
|--------|---------|
| Retire TeamCity APK build configs | GitHub Actions handles all APK builds |
| Retire PackageTool | GitHub Actions handles all packaging |
| TeamCity continues for dev/QA site builds | Branch-triggered builds for `release/*`, `sprint/*`, `feature/*`, `task/*` remain in TeamCity until a future migration |
| SharePoint upload remains manual | Could be automated in a future phase by adding a SharePoint upload step to Workflow 4 |

---

## 12. Verification Plan Restructuring

The verification plan Jira item is the source of truth for release scope. To support the automated workflows (especially Workflow 2 and Workflow 6), the verification plan description should follow a consistent, machine-parseable format. This does not require changing the Jira issue type — just standardizing the description structure.

### Recommended Format

```
h2. Release {version}

h3. Sprint Branches
* sprint/2026.e (10 new items)
* sprint/2026.f (11 new items)

h3. Feature Branches
* feature/CAR-32983 - [Feature name] (Developer)
* feature/CAR-23882 - [Feature name] (Developer)

h3. Grouped Item Branches
* CAR-33589-DocExtraction-Throttle (Developer)
  ** CAR-33589
  ** CAR-33784
  ** CAR-33614
* DeadlockFixes (Developer)
  ** CAR-33650
  ** CAR-33657
  ** CAR-33662
  ** CAR-33676

h3. Miscellaneous Tasks
* CAR-33510 (Developer)
* CAR-33485 (Developer)

h3. Miscellaneous Bugs
* CAR-31190 (Developer)
* CAR-32955 (Developer)

h3. Cherry-Pick Items
* CAR-33779 (commit: abc1234)

h3. Developer Roles
* Primary Contact: Ryan
* Merge/Build Coordinator: Ryan

h3. Release Timeline
| Phase | Target | Actual |
| QA Testing Cutoff | 4/2/26 | |
| Release Branch Created | 4/10/26 | |
| Merge Testing Complete | 4/15/26 | |
| Package Built | 4/16/26 | |
| Build Testing Complete | 4/16/26 | |
| Release Date | 4/17/26 | |
```

### What Makes This Machine-Parseable

- **Sprint branches** are listed under a `Sprint Branches` heading with exact branch names
- **Feature branches** include exact branch names
- **Grouped items** list individual Jira keys as sub-items under their branch name
- **Cherry-pick items** include the commit SHA
- All Jira keys follow the `CAR-#####` pattern and can be extracted via regex

The automated workflows parse this format using straightforward regex patterns to extract branch names, issue keys, and commit SHAs. If an item doesn't match the expected format, it's flagged in the readiness report (Workflow 2, Step 1) for manual review.

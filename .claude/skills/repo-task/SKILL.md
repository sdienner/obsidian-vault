---
name: repo-task
description: Delegate an implementation task to a Cargas repo using Claude Code headless mode, then report results back to the vault. Use when Scott says "go implement X in repo Y" or "go do X in EnergyLicenses".
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
user-invocable: true
---

# Repo Task Skill

Delegate implementation work to a specific Cargas repo by running Claude Code headlessly inside that repo's directory. Report results back to the vault via the daily note and relevant project CLAUDE.md.

## Usage

```
/repo-task                          # Prompts for repo and task interactively
/repo-task EnergyLicenses           # Prompts for task description
/repo-task EnergyLicenses "implement the Octopus Deploy API versions endpoint"
```

Or invoked naturally:
- "Go implement X in EnergyLicenses"
- "Go add Y to MyFuelPortal"
- "Have Claude work on Z in MFPQueryManager"

## Repo Directory Map

All repos live at `D:/repos/`. Common repos:

| Short name | Path |
|------------|------|
| EnergyLicenses / CustomerHub | `D:/repos/EnergyLicenses` |
| MyFuelPortal / MFP | `D:/repos/MyFuelPortal` |
| MFPQueryManager | `D:/repos/MFPQueryManager` |
| CargasEnergy / CE | `D:/repos/CargasEnergy` |
| EnergyScripts | `D:/repos/EnergyScripts` |

If unsure of the path, run `ls D:/repos/` and match by name (case-insensitive).

## How to Execute

### Step 1: Confirm task and repo

If the repo or task is ambiguous, ask before running. Confirm:
- **Repo:** Which repo path to use
- **Task:** Clear description of what to implement
- **Scope:** Any constraints (e.g., "read-only exploration first", "commit when done", "don't push")

### Step 2: Run Claude Code headlessly in the target repo

Use the Bash tool with `run_in_background: true`:

```bash
cd D:/repos/<RepoName> && claude -p "<task description>" \
  --allowedTools "Read,Edit,Write,Bash,Glob,Grep" \
  --permission-mode acceptEdits \
  --output-format json \
  2>&1
```

**Important flags:**
- `--permission-mode acceptEdits` — auto-approves file reads and edits without interactive prompts
- `--output-format json` — returns structured output with `result`, `session_id`, `cost_usd`
- Do NOT use `--bare` — the target repo's CLAUDE.md should be loaded for context

Tell the user the task is running in the background and they'll see a summary when it finishes.

### Step 3: Parse the output

When the background task completes, extract:
- `result` — Claude's summary of what was done
- Any git status output if commits were made
- Any errors or blockers

If the output is too large, read from the saved result file.

### Step 4: Report back to the vault

#### 4a. Update today's daily note

Append to the `## Notes & Capture` section of `Daily/YYYY-MM-DD.md`:

```markdown
**Repo task completed — <RepoName>:** <one-line summary of what was done>
- Files changed: <list key files>
- Committed: yes/no
- Follow-up needed: <any blockers or next steps>
```

#### 4b. Update the relevant project CLAUDE.md (if one exists)

Find the matching project in `Projects/*/CLAUDE.md` and update:
- `## Current Focus` — reflect what was just implemented
- `## Next Actions` — check off completed items, add any new follow-ups
- `## Key Decisions` — log any significant decisions made during implementation

If no matching project CLAUDE.md exists, note it in the daily note only.

#### 4c. Tell the user

Give a clear spoken summary:
- What was implemented
- Files changed or created
- Whether it was committed
- Anything that needs their attention (conflicts, decisions, TODOs left behind)

## Example Full Flow

**User:** "Go implement the Octopus versions endpoint in EnergyLicenses"

1. Confirm: repo = `D:/repos/EnergyLicenses`, task = implement Octopus versions API route
2. Run in background:
   ```bash
   cd D:/repos/EnergyLicenses && claude -p "Implement a Remix API route at app/routes/api.octopus.versions.ts that calls getOctopusVersionsForAllMfpDatabaseLinks() from app/utils/octopus.server.ts and returns the data as JSON. Follow the existing loader pattern used in jiraIssues.server.ts." --allowedTools "Read,Edit,Write,Bash,Glob,Grep" --permission-mode acceptEdits --output-format json 2>&1
   ```
3. Tell user: "Running in EnergyLicenses — I'll report back when it's done."
4. On completion, parse result and update:
   - `Daily/2026-04-17.md` → Notes & Capture
   - `Projects/MyFuelPortal/CLAUDE.md` → Current Focus + Next Actions
5. Report to user with summary

## Task Progress Tracking

```
TaskCreate:
  subject: "Run repo task"
  description: "Execute Claude Code headlessly in target repo"
  activeForm: "Running Claude Code in <repo>..."

TaskCreate:
  subject: "Parse results"
  description: "Extract what was done from output"
  activeForm: "Parsing results..."

TaskCreate:
  subject: "Report to vault"
  description: "Update daily note and project CLAUDE.md"
  activeForm: "Updating vault notes..."
```

## Constraints and Safety

- **Never force-push** to main or master branches
- **Confirm before pushing** — by default, commit but do not push unless told to
- If the task involves a migration or schema change, pause and report back before committing
- If Claude Code in the target repo hits an error or conflict, report it back verbatim — do not try to silently recover

# Release Automation

Automated release process for CargasEnergy, replacing the manual release workflow with GitHub Actions.

## Owner
Ryan (proposed), Scott (sponsor)

## Key Files
- `CargasEnergy-Automated-Release-Process.md` — Full proposal with 6 workflows, infrastructure setup, and transition plan

## Context
- Replaces manual process: branch merging, APK builds, packaging (PackageTool), Jira updates, waterfall merges
- Uses GitHub Actions with self-hosted Windows runners, Jira REST API, and Jira Automation rules
- Monthly release cadence preserved; QA approval gates remain human-driven
- 5-phase incremental transition plan (Foundation -> Low-Risk -> Build -> Packaging -> Steady State)

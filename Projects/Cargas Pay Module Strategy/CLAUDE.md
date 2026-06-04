---
date: 2026-06-04
tags: [project, cargas-pay, modules, deltas, release-engineering]
status: active
---

# Project: Cargas Pay Module Strategy

## Overview
Define a release/deployment strategy for the Cargas Pay module so that module changes and base (release/delta) changes can coexist on the same customer site without breaking each other. The trigger: the 2025.10 delta failed when the 2026.03 Cargas Pay module was applied, because the module had dropped a column the delta's SQL still referenced.

## Status
- **Phase:** Planning (design complete, implementation not started)
- **Progress:** 10%
- **Started:** 2026-06-04
- **Target:** TBD — must land before module rollout passes a handful of sites

Full technical design: [[Projects/Cargas Pay Module Strategy/Design]]

## Goal Link
**Supports:** [[2. Yearly Goals#Engineering Delivery]]
**Related:** [[Projects/MFP CE Module/CLAUDE]] (inherits this pattern), [[Projects/Deltas/CLAUDE]], [[Projects/Release Automation/CLAUDE]]

## The Core Decision
The answers gathered during design force the architecture — the "clean partition" is off the table:

- Only ~30% of customers will run the module; the other ~70% get payments through base release/delta forever.
- All payment objects stay together in the module (a complete, self-contained payment subsystem that can run on an old base).
- Therefore payment objects live in **both** channels permanently. Drift is the steady state, not a defect.

**Model: source-level overlay, deploy-time partition.** Objects exist in both channels in git, but on any given site exactly one channel owns them at deploy time:

| Site type | Who owns payments at deploy time |
|-----------|----------------------------------|
| Non-module (~70%) | Base release/delta (unchanged) |
| Module (~30%) | The module, completely — base deploys must leave payment objects alone |

## Approach — defense in depth
Three layers; all three are needed, none replaces the others:

1. **Prevent (PR-time):** a module-boundary GitHub Action in CargasEnergy that flags PRs touching both module and base objects — reusing the EnergyLicenses classifier. Advisory, not a correctness guarantee.
2. **Separate (build-time):** the delta build partitions changed files against `module.json`; module-owned SQL goes to a separate `update.module.sql`; the module fix re-ships as a module package built from the delta branch.
3. **Enforce (deploy-time):** the deploy agent skips the base delta's payment portion on module sites (one `cModule` lookup) and blocks module downgrades. This is the actual safety net.

## Key Decisions
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-04 | Overlay forever, not clean partition | 70% of customers need payments via base; module is a self-contained superset for the other 30% |
| 2026-06-04 | Payments fix dual-ships: base delta (payments inline, skipped on module sites) + module delta | One base-delta artifact serves both populations via deploy-time skip |
| 2026-06-04 | Payment fix for module sites ships as `DeploymentType: 3` (Module), not a type-2 delta | Type-2 delta gate keys off base version and would reject a module-versioned delta; partial-dacpac semantics are what we want anyway |
| 2026-06-04 | Module revisions use letter suffix (`2026.03-A`), not three-dot (`2026.03.1`) | `string.Compare` mis-orders multi-digit numeric segments (.2 vs .10); letters sort correctly under the existing comparator |
| 2026-06-04 | Module-boundary PR check starts advisory, tightens to blocking later | Mixing isn't always wrong; hard-block day one breeds override-fatigue. Make accidental mixing impossible, not all mixing |
| 2026-06-04 | Drop the cumulative compatibility matrix; packages self-describe and are gated at deploy | A dense matrix (~24 lines/yr × 12+ letters, cumulative) doesn't scale; per-package metadata is sparse and O(1) to evaluate against live site state |
| 2026-06-04 | Module is per-release-line; cross-channel dep keys off Jira fix identity, not a module version | Base and module versions are decoupled many-to-many, so a base delta serving heterogeneous module lines can't name one required version — a fix-set is line-agnostic |

## Next Actions

### Phase 0 — Prevent (cheap, do first)
- [ ] Build module-boundary PR check as a GitHub Action in CargasEnergy (reuse `modulePatterns.server.ts` classifier from EnergyLicenses)
- [ ] Decide where the classifier lives: call EnergyLicenses API (short-term) → shared package (long-term). Do **not** vendor a copy (can't see DB-backed overrides)
- [ ] One-time audit: does `module.json`'s object set cover **every** payment object base ships? (self-containedness invariant)

### Build-time (separate)
- [ ] In `cerelease patch`: partition the diff against `module.json` after the file list is computed; route module-owned SQL → `update.module.sql`, module-owned web/DLLs → separate staging
- [ ] Add a module-delta build path: point the existing C# module packager at the delta branch, version it `<base>-<letter>` (e.g. `Cargas Pay 2026.03-A`)
- [ ] Content-hash the module object set into the module `PackageInfo.json`; skip publishing if unchanged from the last module package

### Deploy-time (enforce)
- [ ] Deploy agent: on a module site (cModule present), skip `update.module.sql` and payment web files from a base delta
- [ ] Add module-downgrade guard: **read** `cModule.versionNumber` and block an older incoming module (it is write-only today)
- [ ] Replace ad-hoc `string.Compare` version checks with a real version comparator (helps base channel too)

### Tracking (no global matrix — packages self-describe by fix identity)
- [ ] Module packages advertise the payment fix-set they contain (`ContainsModuleFixes` — Jira keys from cherry-picks); record it on the site (`cModule`)
- [ ] Base deltas declare `RequiresModuleFixes` (Jira keys) only for the rare hard cross-dep; deploy gate checks containment against the site's module fix-set (line-agnostic, O(1))
- [ ] Fan out payment fixes across every adopted module line via the per-batch release grid (module dimension = target module versions), same shape as base-delta fan-out
- [ ] Add a per-issue "touches module?" flag to the per-batch plan grid (from the PR check); keep it batch-scoped, never cumulative

## Open Questions / Blockers
- **Cross-channel dependency enforcement:** automatically detect when a base delta's non-payment code depends on a newer module object (call-graph analysis, hard), or record by convention in the package's `RequiresModuleFixes` (Jira keys) and gate on it? Headline open question.
- **Web binary compatibility:** `CargasPay.dll` built at one version running against another version's core assemblies is "tested fairly well, not fully" — finish that testing before rollout.
- **A-vs-B build approach:** lighter Contents-driven split (recommended) vs. fully symmetric partial-dacpac in the delta flow (cleaner, requires DacFx model-building in the TS CLI).

## Resources
- **Module manifest:** `D:/repos/CargasEnergy/module.json`
- **Module + release packager (C#):** `D:/repos/ancillary-projects/Deploy/Package/Package.cs`
- **Deploy agent:** `D:/repos/ancillary-projects/Deploy/Deploy/Deploy.cs`
- **Delta CLI:** `D:/repos/CEReleaseCLI/src/commands/{patch,create-delta}/index.ts`
- **Existing module classifier (reactive):** `D:/repos/EnergyLicenses/app/utils/modulePatterns.server.ts`, `app/services/moduleAnalysis.server.ts`
- **Delta build skill:** `.claude/skills/delta-builder/skill.md`

## Notes for Claude
This project is the foundation MFP CE Module inherits — whatever pattern lands here sets the precedent. No customer sites run modules yet, so this is greenfield design, not incident cleanup; the 2025.10 failure was caught internally. The non-negotiable: the deploy agent must become module-aware regardless of how clean release planning gets — process discipline alone can't fix a DacFx full-compare or a flat `update.sql`. See [[Projects/Cargas Pay Module Strategy/Design]] for the code-level mechanics and file/line anchors.

---
date: 2026-06-04
updated: 2026-06-10
tags: [project, cargas-pay, modules, deltas, release-engineering]
status: active
---

# Project: Cargas Pay Module Strategy

## Overview
Define the release/deployment strategy for the Cargas Pay module so module changes and base (release/delta) changes can coexist on customer sites. Trigger: the 2025.10 delta failed when the 2026.03 Cargas Pay module was applied (module had dropped a column the delta's SQL referenced). Caught internally — no customer affected; no module sites exist yet.

**The module is intended for all customers** (corrected 2026-06-09 — earlier design assumed ~30% subset). Payments is the one domain with externally-forced change (gateways, PCI, tokenization vendors), so the module is mandatory payments-delivery infrastructure: evergreen payments on a slow-moving base.

## Status
- **Phase:** Planning (design complete and evaluated; implementation not started)
- **Progress:** 15%
- **Started:** 2026-06-04
- **Target:** TBD — safety preconditions must land before first production module install

Full technical design: [[Projects/Cargas Pay Module Strategy/Design]]
Broad-audience explainer + FAQ: [[Projects/Cargas Pay Module Strategy/Delta and Module Release Process]]

## Goal Link
**Supports:** [[2. Yearly Goals#Engineering Delivery]]
**Related:** [[Projects/MFP CE Module/CLAUDE]] (inherits this pattern), [[Projects/Deltas/CLAUDE]], [[Projects/Release Automation/CLAUDE]]

## The Architecture: clean partition, segmented by floor

Payments have a **single owning channel** per site — no overlay, no per-site conditional deploy behavior:

| Base line | Payments channel | Why safe |
|-----------|------------------|----------|
| **≥ 2025.08** (module-eligible) | **Module only** — deltas carry no payment objects | Collision structurally impossible: the delta never contains payments |
| **< 2025.08** (module-ineligible) | Deltas, as today (legacy until upgraded) | No module can exist there — nothing to collide with |

Partition is mechanical (`diff ∩ module.json`). Compatibility **bands** bound how far a module can run ahead of base (band 1: base 2025.08–2026.03 ↔ modules ≤2026.03; band 2: modules ≥2026.04 need base ≥2026.04); maintain **one module head per band**. What remains in the deploy agent is **gates only** — fail-safe checks, not conditional behaviors.

**2026-06-10 evaluation verdict:** merit high, tooling feasibility high, **rollout is the real project.** Top risks are payment-data migration under desired-state apply, residual cross-boundary SQL references, and campaign logistics — see risk register in [[Projects/Cargas Pay Module Strategy/Design]].

## Key Decisions
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-04 | ~~Overlay forever, not clean partition~~ **Superseded 2026-06-09** | Was based on 30%-subset assumption |
| 2026-06-04 | ~~Dual-ship payment fixes; base delta skips payments on module sites~~ **Superseded 2026-06-10** | Replaced by segment-by-floor; skip machinery never gets built |
| 2026-06-04 | Payment fix for module sites ships as `DeploymentType: 3` (Module), not a type-2 delta | Type-2 gate keys off base version and rejects module-versioned packages; partial-dacpac semantics are what we want |
| 2026-06-04 | Module revisions use letter suffix (`2026.03-A`), not three-dot | Lexical `string.Compare` mis-orders numeric segments (.2 > .10); letters sort correctly and match delta convention |
| 2026-06-04 | PR boundary check starts advisory, tightens later | Make accidental mixing impossible first; under partition it grows into routing enforcement |
| 2026-06-04 | No global compatibility matrix; packages self-describe, gated at deploy | Matrix doesn't scale (~24 lines/yr × 12+ letters, cumulative); per-package metadata is O(1) vs live site state |
| 2026-06-05 | Bands enforced via `MinBaseVersion` as package data | Boundaries change; floor-as-data survives that. Current `module ≥ base` gate permits the forbidden case |
| 2026-06-05 | Maintain only the head module per band | Bounds payment-fix fan-out to # bands |
| 2026-06-09 | **Module goes to all customers** | Evergreen-payments rationale applies to every payments customer |
| 2026-06-10 | **Segment-by-floor:** lines ≥2025.08 ship payments module-only (deltas exclude them); lines <2025.08 keep payments in deltas (provably safe) | Trades hard correctness risk (breaking deploy) for soft coverage gap (unmigrated site waits for module); deletes the skip machinery |
| 2026-06-10 | Fix-identity tracking (`RequiresModuleFixes`) demoted to escape hatch for residual cross-boundary references | Its main driver (dual-ship coordination) died with the overlay |
| 2026-06-10 | Migration data-safety + campaign plan are **preconditions** to first production install | `BlockOnPossibleDataLoss=false` on financial data across multi-version jumps is the plan's scariest operation |

## Next Actions

### Phase 0 — Decisions & data (this/next week, no code)
- [ ] Pull customer population by base version from PhoneHome: size the sub-2025.08 tail, band 1, band 2. Sizes the campaign and the legacy-path lifetime
- [ ] Ratify with team leads: payments module-only for lines ≥2025.08; band governance (new boundary = deliberate costed decision); urgent-fix policy (ad-hoc package as official escape hatch)
- [ ] Identify how deploy agents get updated in the field; name an owner for agent-update sequencing

### Phase 1 — Safety preconditions (gate the first production module install)
- [ ] **Payment data migration design**: cumulative idempotent migration scripts in the module package valid from any eligible starting version; decide `BlockOnPossibleDataLoss` for type-3 deploys; require generated deploy reports on first N installs
- [ ] Deploy gates in `Deploy.cs`: module-downgrade guard (read `cModule.versionNumber` — write-only today), `MinBaseVersion` band gate (current `module ≥ base` check permits the forbidden case), real version comparator
- [ ] Module completeness audit: `module.json` covers every payment object base ships
- [ ] DLL compatibility matrix: `CargasPay.dll` at module head vs older base assemblies, per band

### Phase 2 — Build tooling
- [ ] PR boundary check in CargasEnergy (advisory): path classification (reuse EL classifier — call EL API short-term, shared package later, never vendor) + content heuristic for base SQL referencing module object names + flags for module table changes and manifest drift
- [ ] `cerelease patch`: exclude `module.json`-matched files from delta builds on lines ≥ floor (floor as config); detect module-content change per delta letter
- [ ] Module-delta build path: thin CLI wrapper around `BuildModulePackage` (checkout delta branch → build web artifacts → package); stamp letter version + `MinBaseVersion` + `ModuleContentHash`; skip publish when hash unchanged

### Phase 3 — Pilot
- [ ] Stand up automated module regression suite (one stable artifact shape — desired-state)
- [ ] Pilot: updated agent + module install + subsequent base delta + subsequent module delta on internal/friendly sites; review deploy reports
- [ ] Verify band gate and downgrade guard fire correctly (negative tests)

### Phase 4 — Campaign
- [ ] Migration campaign plan: scheduling, customer comms, adoption dashboard (EL already snapshots adoption nightly)
- [ ] Flip PR check from advisory to required once the boundary is clean
- [ ] Sunset plan for sub-2025.08 legacy payment-delta path

## Open Questions / Blockers
- **Payment data migration mechanics** — the headline precondition; needs a design of its own (Phase 1)
- **Population shape** — sub-2025.08 tail size and band distribution (Phase 0 data pull) determines campaign length and legacy-path lifetime
- **Band boundaries** — confirmed "good for now" (2025.08 floor; 2026.03/2026.04 split); design stays boundary-agnostic via `MinBaseVersion`
- **Residual cross-boundary references** — base SQL referencing payment schema still rides deltas; detection (PR content heuristic) chosen over prevention; fix-identity gate held in reserve

## Resources
- **Module manifest:** `D:/repos/CargasEnergy/module.json`
- **Module + release packager (C#):** `D:/repos/ancillary-projects/Deploy/Package/Package.cs`
- **Deploy agent:** `D:/repos/ancillary-projects/Deploy/Deploy/Deploy.cs`
- **Delta CLI:** `D:/repos/CEReleaseCLI/src/commands/{patch,create-delta}/index.ts`
- **Existing module classifier (reactive):** `D:/repos/EnergyLicenses/app/utils/modulePatterns.server.ts`, `app/services/moduleAnalysis.server.ts`
- **Adoption tracking:** EnergyLicenses nightly jobs (`.github/workflows/nightly_release_jobs.yml`)
- **Delta build skill:** `.claude/skills/delta-builder/skill.md`

## Notes for Claude
This project sets the pattern MFP CE Module inherits. No customer sites run modules yet — greenfield design, not incident cleanup. The architecture is settled (segment-by-floor clean partition; see Design.md revision note for the superseded overlay model). The work now divides into: tooling (weeks, low risk) and rollout (quarters, where the real risk lives — data migration, agent sequencing, campaign). Non-negotiables: deploy gates before any module install; data-migration story before the first production install; payments never ride deltas on module-eligible lines.

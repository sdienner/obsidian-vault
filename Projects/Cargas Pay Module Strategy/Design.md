---
date: 2026-06-04
updated: 2026-06-10
tags: [design, cargas-pay, modules, deltas, release-engineering]
status: active
---

# Cargas Pay Module — Technical Design

Code-grounded design for how the Cargas Pay module and base release/delta changes coexist on customer sites. Project hub: [[Projects/Cargas Pay Module Strategy/CLAUDE]]. Broad-audience version: [[Projects/Cargas Pay Module Strategy/Delta and Module Release Process]].

> **Revision note (2026-06-10):** the original draft assumed the module would reach only ~30% of customers, which forced an "overlay forever" architecture with deploy-time payment-skipping. Corrected intent: **the module goes to all customers.** That enables the simpler clean-partition model ("segment-by-floor") this document now describes. The superseded overlay design is summarized in [Design history](#design-history) for context.

## Problem

Deltas are cherry-picked fixes packaged against a release branch. The Cargas Pay module is a separately-built package containing everything listed in `module.json`. Applying a delta can fail once a module is installed: the **2025.10 delta failed** because the **2026.03 Cargas Pay module** had dropped a column that the 2025.10 delta's SQL still referenced.

The change that failed was a *payments fix* — both a routing problem (wrong channel for a module site) and a boundary problem. No customer was affected; the failure was caught internally before module rollout began.

## Strategic rationale: evergreen payments

Look at what `module.json` actually contains: NMI, AuthorizeNet, BasisTheory, Finix — payment gateways and tokenization vendors. Payments is the one domain where change is **externally forced** (gateway API deprecations, PCI requirements, vendor migrations) on timelines customers don't control. The module exists to deliver **current payments on a slow-moving base** — and that rationale applies to *every* payments customer, which is why the module is intended for **all customers**, not a subset. It is mandatory payments-delivery infrastructure, not an optional add-on.

## How the two pipelines work today (verified)

| | Base delta | Module |
|---|---|---|
| Built from | Cherry-picks on `delta/X-n` branch | `module.json` file set on a release branch |
| Build tool | `cerelease` (TS) | `Package.cs` (C#), `BuildAllModules` |
| DB payload | **Static `update.sql`** — changed procs/views/functions concatenated as `create or alter`; tables only via hand-written `DeltaDeploymentScript.sql` | **Partial dacpac** of just the `module.json` objects |
| Deploy semantics | Run the script as-is (`DeploymentType: 2`) | DacFx partial sync (`DeploymentType: 3`); won't drop objects missing from the dacpac, but syncs objects it *does* contain to release shape — **including column drops, with `BlockOnPossibleDataLoss = false`** |
| Version gate | Must match site base version (`StartsWith`) | Only blocked if *older* than base |

`DeploymentType` enum: `Release = 1, AdHoc = 2, Module = 3, DataCleanup = 4` (`Package.cs:19`).

### Delta build mechanics (`cerelease patch`)
- Three-dot git diff `base...delta --name-only` → changed file list (`patch/index.ts:611`).
- `.cs` changed → msbuild → DLLs copied into `web/bin`. `.jsx` changed → yarn + webpack.
- SQL with `create proc/view/function` → concatenated into `database/update.sql` as `create or alter` (`patch/index.ts:1366`); tables/other DDL skipped unless in `DeltaDeploymentScript.sql` (`patch/index.ts:1346`).
- `PackageInfo.json` written as `{ DeploymentType: 2, Contents: [...] }` — `Contents` already enumerates the object list (`patch/index.ts:1216`).
- Deltas are **cumulative**: each new delta branch is cut from the previous one (`create-delta/index.ts:440`), and the diff is from the release branch, so `2025.10-C` contains A+B+C.

### Module build mechanics (`Package.cs`)
- `BuildPackage` calls `BuildAllModules` at the end (`Package.cs:123`) — every full release emits base + module(s), built from the same source at the same version (so a module site taking a full release gets idempotent, identical payment definitions from both).
- `BuildModulePackage` (`Package.cs:148`) builds a partial dacpac (`Package.cs:186`) from the `module.json` object set and stamps `ModuleVersion = version` (`Package.cs:238`).
- A standalone manual path exists (`PackageTool/Form1.cs:393`), version from a free-text box — does **not** checkout a branch.
- `cerelease` has **zero** module awareness (confirmed by search).

## Why 2025.10 failed (decoded)

Site was base 2025.10 with module 2026.03 applied (the module's core use case: current payments on an old base). The module's partial dacpac synced a payments table to 2026.03 shape — dropping a column, silently (`BlockOnPossibleDataLoss = false`, `Deploy.cs:1691`). The 2025.10 delta's static `update.sql` then ran a `create or alter` on an object referencing that column, generated against pristine 2025.10 schema. SQL Server failed the bind. The script *must* fail — it assumes zero drift; the module exists to *create* drift.

The base channel is completely module-blind: `cModule` appears in the deploy agent exactly once (`Deploy.cs:1549`), to bump the version after a module deploy. Release and delta deploys never consult it.

## Architecture: clean partition via segment-by-floor

Since all customers get the module, payments can have a **single owning channel** on every site — no overlay, no per-site conditional deploy behavior. The partition is segmented by the module-eligibility floor (modules began at **2025.08**):

| Base line | Payments channel | Why it's safe |
|---|---|---|
| **≥ 2025.08** (module-eligible) | **Module only.** Deltas for these lines carry **no payment objects**. Payment fixes ship as module deltas; sites receive them by being on the module. | A module site can never collide with a payment-delta, because the delta never contains payments. Structural, not policed. |
| **< 2025.08** (module-ineligible) | **Deltas, as today** (legacy path until upgraded/sunset). | These sites *cannot* have the module, so there is nothing to collide with. |

The partition at build time is mechanical: `diff ∩ module.json`. For eligible lines, matching files are **excluded from the delta** and routed to the module build instead.

### Why this beats the deploy-time skip
The earlier overlay design kept payments in every delta and taught the deploy agent to skip them on module sites. That trades a **hard correctness risk** (a conditional deploy behavior that can break) for what segment-by-floor turns into a **soft coverage gap** (an eligible-but-unmigrated site lacks the newest payment fixes until migrated — omission never breaks a deploy). What remains in the deploy agent is **gates only** (read state, compare, block) — easy to build, easy to test, fail-safe.

Machinery deleted by this model (never to be built): the `update.module.sql` split, the per-site deploy-time payment skip, routine dual-shipping of payment fixes into every base-delta line, and most of the fix-identity dependency tracking (demoted to escape hatch — see [Residual risk](#residual-risk-cross-boundary-references)).

## The two channels (eligible lines)

Example site: base 2025.10 + module 2026.03.

| | Base delta (`2025.10-C`, type 2) | Module delta (`Cargas Pay 2026.03-A`, type 3) |
|---|---|---|
| Version line | base (2025.10-A,B,C…) | module (2026.03, -A, -B…) — independent within its compatibility band |
| Payload | cumulative SQL diff + DLLs, **no payment objects** | desired-state partial dacpac of the payment subsystem |
| Applies | base/non-payment fixes | payment fixes; bumps `cModule` |

The payments package is `DeploymentType: 3` (Module), **not** a type-2 delta: the type-2 gate requires `newVersion.StartsWith(baseVersion)` (`Deploy.cs:822`), so a `2026.03`-named package on a 2025.10 base would be rejected as a delta. Type-3 uses the module gate and gives the drift-tolerant partial-dacpac semantics we want — but that gate is insufficient and partly backwards; see [Compatibility bands](#compatibility-bands-base--module) and [Versioning findings](#versioning-findings-does-the-code-support-revisions-today).

## Cumulative deltas vs. the desired-state module property

Base deltas are cumulative diffs. Module packages are **desired-state**: the partial dacpac holds the full current definition of every module object, and DacFx syncs the DB to match. Consequences:

- There's only ever **one current module package** per module line; the latest supersedes all prior. A site can jump straight to the latest revision — no need to apply each letter in sequence.
- "Payments unchanged this delta letter" means the module package simply **isn't re-minted**. The module line advances only when payment content actually changes. Detection is mechanical: `diff(prev-delta … new-delta) ∩ module.json` — empty means don't mint.

## Compatibility bands (base ↔ module)

The base↔module relationship is **piecewise**, bounded by dependency boundaries. Modules began at release **2025.08**. Current bands (**boundaries confirmed "good for now," subject to change**):

- **Band 1:** base **2025.08–2026.03** can run modules up through **2026.03**. The module floats ahead of base *within* the band (base 2025.10 + module 2026.03 — the core use case).
- **Band 2:** modules **2026.04+** require base **2026.04+** — a dependency boundary introduced at 2026.04.

"Module ahead of base" holds *within* a band; the boundary caps how far, and crossing it requires base and module to move together.

### Enforced as data, not code: `MinBaseVersion`
Each module package declares a **`MinBaseVersion`** (its band floor) in `PackageInfo.json`; the deploy gate enforces **site base ≥ module `MinBaseVersion`**. Boundaries change, so the floor is data carried by the package — a new boundary just means new module builds stamp a higher floor. No code change.

### The current gate is backwards for this
The existing type-3 gate only checks **module ≥ base** (`Deploy.cs:838`). That *permits exactly the forbidden case*: module 2026.04 on base 2025.10 passes (`2026.04 ≥ 2025.10`) but must be blocked. `MinBaseVersion` is a **correctness fix** to a gate that today allows incompatible installs.

### "Latest module only" → maintain one head per band
Ship module deltas only for the **head module of each active band** (band 2 advances with current releases; band 1 stays at the 2026.03 head for sites that can't cross). This bounds payment-fix fan-out to the number of bands — a couple — not every adopted release line.

### Band crossing is automatic via full release
Crossing the 2026.04 boundary means taking a full release, which ships the matching module alongside (`Package.cs:123`) — base and module upgrade together. The boundary is only dangerous on a **standalone module install**, exactly what the `MinBaseVersion` gate catches.

### Band governance
Each new boundary **permanently adds a maintained module head**. If boundaries accrue casually, fan-out converges back to per-line module maintenance — the unbounded case this design eliminates. Introducing a dependency that forces a new band must be a deliberate, costed decision, not an engineering side effect.

## Residual risk: cross-boundary references

Segment-by-floor removes payment **objects** from deltas. It does **not** remove **base objects that reference payment schema** — a base proc or view mentioning a payment table's column, or calling a payment proc, is not in `module.json` and still rides the delta. On a site whose module has moved that schema, the delta's `create or alter` can still fail the bind (views bind at creation; procs validate column references when the table exists). This is the 2025.10 failure shape surviving in a thinner slice. **No split-channel model can eliminate it — only detect it.**

Mitigations, in order of preference:
1. **PR content heuristic:** extend the boundary check beyond path classification — flag base SQL files whose text mentions module-owned object names. Cheap, catches most cases at author time.
2. **Routing rule:** a flagged base object's fix ships through the module channel too, or is band-restricted.
3. **Fix-identity escape hatch (design reserve — build only when first needed):** the base delta declares required payment Jira key(s) (`RequiresModuleFixes`), module packages advertise the fix-set they contain (Jira keys from cherry-picks; EL's `extractJiraIds` already parses these), and the deploy gate checks containment against the site's recorded module fix-set. Line-agnostic by construction. This was the centerpiece of the overlay model's tracking; under segment-by-floor it is needed only for this residual case.

## Tracking model

No global compatibility matrix — it doesn't scale (~24 lines/yr × 12+ letters, cumulative) and is unnecessary when packages self-describe and the deploy agent evaluates locally (it already parses `PackageInfo`, `Deploy.cs:780`):

1. **`ModuleContentHash`** in the module `PackageInfo.json` — skip publishing when unchanged from the last published package. The module line's own history *is* the dedup record; "unchanged" is never stored.
2. **`MinBaseVersion`** in the module `PackageInfo.json` — the band floor, gated at deploy.
3. **`RequiresModuleFixes` / fix-set advertising** — escape-hatch only (above).
4. **Per-batch release grid** (existing, in Jira) gains a per-issue "touches module?" flag from the PR check and, for payment fixes, the band heads to fan out to. Batch-scoped, never cumulative.

## Versioning findings (does the code support revisions today?)

**No, not really** — the version field is a free string so it won't throw, but:

1. **No build path produces a revision.** `ModuleVersion = version` is always the release version on the only automated path (`Package.cs:238` via `BuildAllModules`). The manual button (`Form1.cs:393`) takes free text but is unguarded and doesn't checkout a branch.
2. **The only module check is incoming-vs-base, and it's lexical.** `string.Compare(newModuleVersion, previousVersion) < 0` (`Deploy.cs:838`). `string.Compare("2026.03.2", "2026.03.10")` is positive — it thinks `.2` is newer than `.10`, so **three-dot numeric breaks at 10+**. A **letter suffix** (`2026.03-A`…) sorts correctly under the existing comparator and matches the delta-letter convention — use letters. (26 revisions per line; module lines should advance far slower than delta lines, so overflow is theoretical.)
3. **No module-vs-module comparison exists.** `cModule.versionNumber` is only ever written (`Deploy.cs:1549`), never read. Nothing stops `2026.03-A` over installed `2026.03-B` (a downgrade) — it proceeds and stamps the version backward.

Work to enable revisions: (a) a build path that mints module revisions from a delta branch; (b) a real comparator or bounded letter scheme; (c) a downgrade guard that reads `cModule`.

## Migration & rollout (preconditions to first production install)

The tooling above is weeks of work; **the rollout is the project.** Items in this section gate the first production module install, ahead of tooling polish.

### 1. Payment data migration under desired-state apply — the scariest operation in the plan
The module is a desired-state dacpac applied with `BlockOnPossibleDataLoss = false`. Schema sync handles structure; it does nothing for **data** — backfills, transforms across a multi-version jump (a 2025.09 site jumping to 2026.03-era payment schema crosses many releases of payment evolution in one apply, on financial data: `bCCTransaction`, payment profiles, settlements). The full-release path accumulates pre/post-deploy migration scripts release by release; the module path has a single `PostDeploymentScript` format-string. Required before rollout:
- cumulative, **idempotent** payment-data migration scripts in the module package, valid from *any* eligible starting version;
- a decision on flipping `BlockOnPossibleDataLoss` **on** for module deploys;
- generated deploy **reports** (the agent already supports `GenerateReport`) reviewed on the first N installs.

### 2. Deploy-agent sequencing
The new gates (downgrade, `MinBaseVersion`) exist only on sites running the **updated deploy agent**. Agent updates must precede module rollout — a bootstrap step that needs an owner. Since no module sites exist yet, the rule is enforceable: no module install to a site without the updated agent.

### 3. Urgent-fix policy during the campaign
Eligible-but-unmigrated sites no longer get payment fixes through deltas. Routine fixes wait for migration (which *is* the fix delivery, and a forcing function for adoption). For an externally-forced urgent change (gateway deadline) hitting many unmigrated sites: the existing **ad-hoc package** (`DeploymentType: 2 AdHoc`) is the official escape hatch — named, not improvised.

### 4. Adoption tracking
EnergyLicenses already captures adoption snapshots nightly (`nightly_release_jobs.yml`) and syncs Cargas Pay config — the natural home for module-adoption dashboards driving the campaign.

### 5. DLL compatibility matrix
`CargasPay.dll` built at the module head runs against older base assemblies — previously "tested fairly well, not fully." Under all-customers this is every site, routinely. Needs a deliberate per-band compatibility test matrix.

### 6. QA economics
A one-line payment fix now ships as the entire module re-asserted at head — the per-fix QA unit is "module regression on each band head it ships to." Mitigation: the desired-state property means there is **one stable artifact shape** to test, which argues for an automated module regression suite rather than per-fix manual passes.

## Proactive module-boundary PR check

EnergyLicenses already has the classifier — running **reactively**. `moduleAnalysis.server.ts:28` compares a release to its predecessor, groups commits by Jira ID, and classifies each item as touching module files, base files, or **both** (tested: `modulePatterns.server.test.ts`). Proposal: run the same classification at **PR time** in CargasEnergy (`github.com/cargas/cargasenergy`) via a `pull_request` Action:

- compute changed files, load `module.json` at the base ref, classify via `classifyFilePath` (MODULE/BASE/IGNORE);
- mixed PR → comment listing which files fall on which side + `module-boundary` label;
- classify by **raw changed files**, independent of Jira parsing (EL keys off `jira-id:` trailers; at PR time the trailer may be absent);
- **content heuristic** for the residual risk: flag base SQL whose text references module-owned object names;
- flag module-owned **table/column** changes (these always need the module channel) and **new payment objects missing from `module.json`** (manifest drift).

Under segment-by-floor the check's role strengthens from advisory hygiene to **routing enforcement**: a payment-file change *must* ship via the module, a base change via the delta — a mixed PR can't ship as one unit through one channel. Start advisory; tighten to a required check once the boundary is clean. Classifier reuse: call EL's API short-term, extract a shared package long-term; do **not** vendor a copy (it can't see EL's DB-backed pattern overrides and will silently diverge).

## Defense in depth

```
PR routing check (prevent) → build partition by floor (separate) → deploy gates (enforce) → migration safety (data)
```

The PR check reduces how often lower layers matter; the build partition makes collision structurally absent on eligible lines; the deploy gates catch band violations and downgrades; migration safety protects the data when the module lands. No single layer is sufficient.

## Risk register (from 2026-06-10 evaluation)

| Risk | Severity | Mitigation |
|---|---|---|
| Payment **data** migration under desired-state apply (`BlockOnPossibleDataLoss=false` on financial data, multi-version jumps) | **High — top precondition** | Cumulative idempotent migrations in module; reconsider data-loss flag for type-3; deploy reports on first N installs |
| Base SQL referencing module-moved schema still rides deltas (residual 2025.10 shape) | Medium | PR content heuristic; routing rule; fix-identity escape hatch |
| Migration campaign duration; eligible-but-unmigrated sites payment-fix-starved | Medium | Campaign plan + adoption tracking; ad-hoc package as urgent escape hatch |
| Deploy gates absent on stale agents | Medium | Agent update precedes module install; sequencing owner |
| DLL version-skew at scale | Medium | Per-band compatibility matrix |
| Band proliferation re-creates unbounded fan-out | Medium (governance) | Boundary = deliberate costed decision; `MinBaseVersion` as data |
| Module letter overflow (>26 revisions/line) | Low | Module lines advance only on payment change |

## Design history

Superseded (2026-06-09/10): the original architecture assumed ~30% module adoption, concluding payments must live in **both** channels forever ("overlay"), with the base delta carrying payments in a separate `update.module.sql` that the deploy agent would skip per-site on module sites, and a fix-identity dependency system (`RequiresModuleFixes`/`ContainsModuleFixes`) coordinating the dual-ship. The all-customers correction made the clean partition achievable; segment-by-floor then made the skip machinery unnecessary (a delta for an eligible line simply never contains payments). The fix-identity system survives only as the escape hatch for residual cross-boundary references. A global base×module compatibility matrix was also considered and rejected for scale reasons before the overlay died.

## Code anchors

- `D:/repos/CargasEnergy/module.json` — the manifest (web + db file lists; comment notes to also register in `Util_TableValues` as `cModules`)
- `Package.cs:123` `BuildAllModules` from `BuildPackage`; `:148` `BuildModulePackage`; `:186` partial dacpac; `:238` `ModuleVersion = version`
- `Form1.cs:393` standalone manual module build (free-text version)
- `Deploy.cs:818` type-2 delta gate (`StartsWith`); `:836` type-3 module gate (lexical, backwards for bands); `:845` `Contents` vs `CustomObject` (`blockDeployOnConflict`); `:1549` `cModule` write-only; `:1691` `BlockOnPossibleDataLoss=false`; `:1703` `DropObjectsNotInSource=true` (full); `:1709` `SchemaBasedFilter` plan contributor; `:1752` type-3 sets `Drop*NotInSource=false`
- `patch/index.ts:611` three-dot diff; `:1216` `PackageInfo` (type 2 + `Contents`); `:1346` `DeltaDeploymentScript`; `:1358` `update.sql` stream; `:1366` `create or alter`
- `create-delta/index.ts:440` cumulative delta branch; `:527` invokes `patch`
- EnergyLicenses `app/utils/modulePatterns.server.ts` (`classifyFilePath`, `isFileInModule`, `loadModuleJson`, `extractJiraIds`); `app/services/moduleAnalysis.server.ts:28` (reactive release analysis); `app/tests/modulePatterns.server.test.ts`; `.github/workflows/nightly_release_jobs.yml` (adoption snapshots, Cargas Pay sync)

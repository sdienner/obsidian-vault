---
date: 2026-06-04
tags: [design, cargas-pay, modules, deltas, release-engineering]
status: active
---

# Cargas Pay Module — Technical Design

Code-grounded design for letting the Cargas Pay module and base release/delta changes coexist on the same site. Project hub: [[Projects/Cargas Pay Module Strategy/CLAUDE]].

## Problem

Deltas are cherry-picked fixes packaged against a release branch. The Cargas Pay module is a separately-built package containing everything listed in `module.json`. Applying a delta can fail once a module is installed: the **2025.10 delta failed** because the **2026.03 Cargas Pay module** had dropped a column that the 2025.10 delta's SQL still referenced.

The change that failed was a *payments fix* — so it was both a routing problem (wrong channel for module sites) and a boundary problem.

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
- `.cs` changed → msbuild → DLLs copied into `web/bin`.
- `.jsx` changed → yarn + webpack → output copied.
- SQL with `create proc/view/function` → concatenated into `database/update.sql` as `create or alter` (`patch/index.ts:1366`); tables/other DDL skipped unless in `DeltaDeploymentScript.sql` (`patch/index.ts:1346`).
- `PackageInfo.json` written as `{ DeploymentType: 2, Contents: [...] }` — `Contents` already enumerates the object list (`patch/index.ts:1216`).
- Deltas are **cumulative**: each new delta branch is cut from the previous one (`create-delta/index.ts:440`), and the diff is from the release branch, so `2025.10-C` contains A+B+C.

### Module build mechanics (`Package.cs`)
- `BuildPackage` calls `BuildAllModules` at the end (`Package.cs:123`) — every full release emits base + module(s).
- `BuildModulePackage` (`Package.cs:148`) builds a partial dacpac (`Package.cs:186`) from the `module.json` object set and stamps `ModuleVersion = version` (`Package.cs:238`).
- A standalone manual path exists too (`PackageTool/Form1.cs:393`), version from a free-text box — does **not** checkout a branch.
- `cerelease` has **zero** module awareness (confirmed).

## Why 2025.10 failed (decoded)

Site was base 2025.10 with module 2026.03 applied (the module's core use case: current payments on an old base). The module's partial dacpac synced a payments table to 2026.03 shape — dropping a column, silently (`BlockOnPossibleDataLoss = false`, `Deploy.cs:1691`). The 2025.10 delta's static `update.sql` then ran a `create or alter` on a proc/view referencing that column, generated against pristine 2025.10 schema. SQL Server failed the bind. The script *must* fail — it assumes zero drift; the module exists to *create* drift.

The base channel is completely module-blind: `cModule` appears in the deploy agent exactly once (`Deploy.cs:1549`), to bump the version after a module deploy. Release and delta deploys never consult it.

## Architecture decision: overlay forever, deploy-time partition

A clean partition (module exclusively owns payments; base never ships them) is impossible because ~70% of customers get payments via base. So:

- **Source-level overlay:** payment objects live in both channels in git, permanently.
- **Deploy-time partition:** on a given site, exactly one channel owns them. Non-module site → base. Module site → the module; base deploys must leave payment objects alone.

Full releases are already safe under this model (Scott's clarification): base-Y and module-Y are built from the same source at the same version, so a module site taking full release Y gets idempotent, identical payment-object definitions from both. The module is re-minted every release, not left stale. Residual risk only in the backward case (installing a base whose bundled module is *older* than installed) — handled by a downgrade guard.

The breakage is specific to **deltas**, and specifically to **module-ahead-of-base** sites (module's main use case).

## The two-channel deployment flow (mixed-version site)

Example: base 2025.10 + module 2026.03. Two independent version lines, two channels:

| | Base delta (`2025.10-C`, type 2) | Module delta (`Cargas Pay 2026.03-A`, type 3) |
|---|---|---|
| Version line | base (2025.10-A,B,C…) | module (2026.03, -A, -B…) — **independent within its compatibility band** |
| Payload | cumulative SQL diff + DLLs | desired-state partial dacpac |
| On this module site | applies everything **except** the split-out payment portion (`update.module.sql` skipped because `cModule` shows Cargas Pay installed) | applies payment objects, bumps `cModule` |
| On a non-module 2025.10 site | applies **everything including** payments | never offered |

Key points:
- It's **one** base-delta artifact, not a separately-built "base-only" delta. Same zip applies payments on non-module sites and skips them on module sites — the build splits payment objects into `update.module.sql`; deploy decides per-site off `cModule`.
- The payments package is `DeploymentType: 3` (Module), **not** a type-2 delta: the type-2 gate requires `newVersion.StartsWith(baseVersion)` (`Deploy.cs:822`), so a `2026.03`-named delta on a 2025.10 base is rejected. Type-3 uses the module gate (`module >= base`, `Deploy.cs:838`) and gives the drift-tolerant partial-dacpac semantics we want — but that gate is **insufficient and backwards** for compatibility bands; it must be augmented by a `MinBaseVersion` check (see [Compatibility bands](#compatibility-bands-base--module)).

## Cumulative deltas vs. the desired-state module property

Base deltas are cumulative diffs. Module packages are **desired-state**: the partial dacpac holds the full current definition of every module object, and DacFx syncs the DB to match. Consequences:

- There's only ever **one current module package** per module-version line; the latest supersedes all prior. A fresh module site can jump straight to the latest revision — no need to apply each letter in sequence.
- "Payments unchanged between `-B` and `-C`" means the module package simply **isn't re-minted**. The module line advances only when payment content actually changes.

## Compatibility bands (base ↔ module)

The base↔module relationship is **not** fully decoupled — it is piecewise, bounded by dependency boundaries. Modules began at release **2025.08**. Current bands (**provisional — boundaries subject to change**):

- **Band 1:** base **2025.08–2026.03** can run modules up through **2026.03**. The module still floats ahead of base *within* the band (e.g. base 2025.10 + module 2026.03 — the core "current payments on old base" case).
- **Band 2:** modules **2026.04+** require base **2026.04+** — a dependency boundary introduced at 2026.04.

So "module ahead of base" still holds *within* a band; the boundary caps how far, and crossing it requires base and module to move together.

### Enforced as data, not code: `MinBaseVersion`
Each module package declares a **`MinBaseVersion`** (its band floor) in `PackageInfo.json`; the deploy gate enforces **site base ≥ module `MinBaseVersion`**. Because boundaries change, this is data carried by the package — a new boundary just means new module builds stamp a higher floor; no code change.

### The current gate is backwards for this
The existing type-3 gate only checks **module ≥ base** (`Deploy.cs:838`). That *permits exactly the forbidden case*: module 2026.04 on base 2025.10 passes (`2026.04 ≥ 2025.10`) but must be blocked. So `MinBaseVersion` is a **correctness fix** to a gate that today allows incompatible installs — not just policy. (Same shape as the write-only `cModule`: the needed guard is absent, the present one points the wrong way.)

### "Latest module only" → maintain one head per band
Policy: ship module deltas only for the **latest module**, with a couple of exceptions. In band terms: maintain the **head module of each active band** (band 2 advances with current releases; band 1 stays at the 2026.03 head for sites that can't cross). This **bounds the payment-fix fan-out to the number of bands (a couple)** — not every adopted release line — simplifying the fan-out in the tracking model. Desired-state packages make "move to your band's head" latest-wins.

### Band crossing is automatic via full release
You can't jump base lines through deltas — crossing the 2026.04 boundary means taking a **full release**, which ships the matching module alongside (`Package.cs:123`). So taking base 2026.04 carries module 2026.04 and upgrades the band together. The boundary is only dangerous on a **standalone module install** — exactly what the `MinBaseVersion` gate catches.

Detection is mechanical: when building base `2025.10-C`, compute `diff(delta/2025.10-B … delta/2025.10-C) ∩ module.json`. Empty → no module change this letter. Non-empty → mint the next module revision.

## Tracking model

A global base-delta × module-version matrix does **not** scale — ~12 monthly lines/year (×2 with betas), each accumulating 12+ delta letters, cumulative forever, is a dense structure for sparse data (mostly recording "nothing changed"). Replace it with **self-describing packages evaluated at deploy time** — no cumulative table.

1. **`ModuleContentHash` in the module `PackageInfo.json`.** Hash the module object set at build; if a rebuild matches the last published hash, skip publishing. Idempotent builds; the module line advances only on real change, so its own version history *is* the dedup record — "unchanged" is never stored, its absence is the information. (Per-package; scales.)
2. **Cross-channel dependency: a fix *identity*, not a version.** Base and module versions are decoupled *within compatibility bands* (many-to-many) — `ModuleVersion` is stamped from the release branch the module is built on (`Package.cs:238`), so there is **one module line per release version with adopters** (Cargas Pay 2026.03, 2026.04, …), and a single base line (2025.10) hosts sites on *different* module lines. So a base delta cannot name one required module *version* — sites that receive it span 2026.03 / 2026.04 / none. Two sub-points:
   - **Fan-out is a planning concern, already-shaped.** A payment fix produces module deltas across every adopted module line (2026.03-B, 2026.04-A, …) exactly as a base fix fans out across base lines. The per-batch release grid handles it (the module dimension is just another set of target versions for that fix) — bounded per batch, never cumulative.
   - **The deploy gate keys off the fix, not the version.** *Common case (independent payment fix): no marker at all* — the base delta skips payments, the module site gets the fix on its own line whenever, fully decoupled. *Rare case (base non-payment code depends on a newer module object):* the base delta declares the required payment **Jira key(s)** — `RequiresModuleFixes: ["CAR-12345"]`. Each module package advertises the payment fix-set it contains (derivable from its cherry-picks; EL's `extractJiraIds` already pulls these from commits). The deploy gate checks containment against the site's recorded module fix-set — **line-agnostic by construction** (it only matters whether the installed module contains CAR-12345, not which line it's on). The deploy agent already parses `PackageInfo` (`Deploy.cs:780`), so this is one more field. (A global monotonic "payment content sequence" is the scalar alternative, but Jira keys reuse existing identifiers.)
3. **Module-downgrade guard** in the deploy gate — compare incoming module vs. installed `cModule.versionNumber`, block if older. (Per-deploy; scales.)

### Why self-describing beats a matrix
At deploy time the agent already knows the site's base version (`cDeployment`), module version + fix-set (`cModule`), and the incoming package's declared needs (`PackageInfo`). If every package declares its own constraints by **fix identity** (not version), no global cross-reference is ever needed — the evaluation is local, O(1), and independent of how many base lines, module lines, or delta letters exist. Because base and module versions are decoupled (a base delta serves sites on heterogeneous module lines), a version-scalar can't express the dependency; a Jira-key fix-set can, line-agnostically. The only human-facing artifact left is the existing **per-release-batch** plan grid (issues × versions), which gains a per-issue "touches module?" flag from the PR check and, for payment fixes, the set of module lines to fan out to — bounded to the batch, never cumulative.

## Versioning findings (does the code support revisions today?)

**No, not really** — the version field is a free string so it won't throw, but:

1. **No build path produces a revision.** `ModuleVersion = version` is always the release version on the only automated path (`Package.cs:238` via `BuildAllModules`). The manual button (`Form1.cs:393`) takes free text but is unguarded and doesn't checkout a branch. Revisions would be pure operator convention.
2. **The only module check is incoming-vs-base, and it's lexical.** `string.Compare(newModuleVersion, previousVersion) < 0` (`Deploy.cs:838`). Not semantic — `string.Compare("2026.03.2", "2026.03.10")` returns positive, i.e. it thinks `.2` is newer than `.10`. **So three-dot numeric breaks at 10+.** A **letter suffix** (`2026.03-A`…`-Z`) sorts correctly under the existing comparator and matches the delta-letter convention — use letters.
3. **No module-vs-module comparison exists.** `cModule.versionNumber` is only ever written (`Deploy.cs:1549`), never read. Nothing stops `2026.03-A` being applied over installed `2026.03-B` (a downgrade); it proceeds and stamps the version backward. The downgrade guard is net-new.

Work to enable revisions, in order: (a) build path that mints module revisions from a delta branch; (b) real comparator or bounded letter scheme; (c) downgrade guard that reads `cModule`.

## Proactive module-boundary PR check

EnergyLicenses already has the classifier — it just runs **reactively**. `moduleAnalysis.server.ts:28` (`runModuleAnalysis(releaseId)`) compares a release to its predecessor, groups commits by Jira ID, and classifies each item as touching module files, base files, or **both** — persisted to a DB for release-time triage. The "inside and outside a module" detection exists and is tested (`modulePatterns.server.test.ts`).

**Proposal: move the same classifier to PR time in CargasEnergy** (it's on GitHub — `github.com/cargas/cargasenergy`). A `pull_request` Action:
- computes changed files, loads `module.json` at the base ref, classifies each via `classifyFilePath` (MODULE/BASE/IGNORE);
- if **both** MODULE and BASE present → comment listing which files fall on which side + a `module-boundary` label;
- classify by **raw changed files**, independent of Jira parsing (EL keys off `jira-id:` trailers and skips orphan commits — at PR time the trailer may be absent);
- bonus flags: module-owned **table/column** changes (can't be cleanly skipped in a base delta) and **new payment objects not yet in `module.json`** (manifest drift).

A mixed PR is exactly where a cross-channel dependency is born — so the check is the natural **upstream feeder for the compatibility matrix**: detect it with the author present, not at deploy time on a customer site.

### Decisions
- **Warn vs block:** start advisory (comment + label), tighten to a required check once the boundary is clean. Mixing isn't always wrong; hard-block day one breeds override-fatigue. Make *accidental* mixing impossible, not all mixing.
- **Where the classifier lives:** call EnergyLicenses' API short-term (reuses the live engine + DB-backed overrides), extract a shared package long-term. Do **not** vendor a copy — it can't see the overrides and silently diverges.

## Defense in depth

```
PR check (prevent)  →  build partition (separate)  →  deploy gate (enforce)
```

The PR check reduces how often the lower layers must save you, but it's advisory and bypassable — **not** a correctness guarantee. The deploy-side downgrade gate and the per-site payment skip are the actual safety net. A green PR check must not breed false confidence that the deploy-side guards are unneeded.

## Open implementation forks

- **Build approach A vs B:** (A) lighter Contents-driven split — route module SQL to `update.module.sql`, deploy skips it on module sites, module fix re-ships via the existing C# packager on the delta branch (recommended; reuses proven plumbing). (B) fully symmetric partial-dacpac emitted by `cerelease` itself (cleaner, but needs DacFx model-building ported into the TS CLI).
- **`DeltaDeploymentScript.sql` table changes** can't be skipped per-object at deploy time → route payment table/column changes through the **module channel** (partial dacpac handles them with drift tolerance), not the base delta's hand-authored script.
- **Cross-channel dependency enforcement:** auto-detect (call-graph, hard) vs. record-by-convention in the matrix and gate (pragmatic).

## Code anchors

- `D:/repos/CargasEnergy/module.json` — the manifest (web + db file lists; comment notes to also register in `Util_TableValues` as `cModules`)
- `Package.cs:123` `BuildAllModules` from `BuildPackage`; `:148` `BuildModulePackage`; `:186` partial dacpac; `:238` `ModuleVersion = version`
- `Form1.cs:393` standalone manual module build (free-text version)
- `Deploy.cs:818` type-2 delta gate (`StartsWith`); `:836` type-3 module gate; `:845` `Contents` vs `CustomObject` (`blockDeployOnConflict`); `:1549` `cModule` write-only; `:1691` `BlockOnPossibleDataLoss=false`; `:1703` `DropObjectsNotInSource=true` (full); `:1709` `SchemaBasedFilter` plan contributor; `:1752` type-3 sets `Drop*NotInSource=false`
- `patch/index.ts:611` three-dot diff; `:1216` `PackageInfo` (type 2 + `Contents`); `:1346` `DeltaDeploymentScript`; `:1358` `update.sql` stream; `:1366` `create or alter`
- `create-delta/index.ts:440` cumulative delta branch; `:527` invokes `patch`
- EnergyLicenses `app/utils/modulePatterns.server.ts` (`classifyFilePath`, `isFileInModule`, `loadModuleJson`); `app/services/moduleAnalysis.server.ts:28` (reactive release analysis); `app/tests/modulePatterns.server.test.ts`

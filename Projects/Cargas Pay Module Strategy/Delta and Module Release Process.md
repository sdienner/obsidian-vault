---
date: 2026-06-05
updated: 2026-06-10
tags: [explainer, cargas-pay, deltas, modules, release-engineering, faq]
status: active
audience: broad
---

# Cargas Energy Releases: Deltas & the Cargas Pay Module

> **Who this is for:** anyone at Cargas who touches the release process — developers, QA, support, PMs — who wants to understand how we ship Cargas Energy, what the Cargas Pay module is, why it conflicted with deltas, and what we're changing. No deep technical background assumed. A [[Projects/Cargas Pay Module Strategy/Design|technical design doc]] covers the engineering specifics.

## The short version

We ship Cargas Energy three ways: **full releases**, **deltas** (small patches between releases), and the **Cargas Pay module** (the payments subsystem, packaged so it can update independently). The plan is for **every customer** to eventually run the module. Deltas and the module were built independently and don't know about each other, so applying a delta to a site that has the module can break things. No customer has hit this — we caught it internally before rollout. The fix: **payment changes will ship only through the module** (for versions that can run it), deltas will carry everything else, and the installer gets safety checks it's currently missing. This document explains the pieces, answers common questions, and lists the changes underway.

## The three ways we ship Cargas Energy

| | What it is | When it's used |
|---|---|---|
| **Full release** | The complete product at a monthly version (e.g. `2026.05`). | Monthly. Every customer eventually lands on a full version. |
| **Delta** | A small package containing only what changed since a full release — quicker to download and apply. Named with a letter: `2026.05-A`, `-B`. | Between full releases, to push high-priority fixes fast. |
| **Module** | A self-contained package of one feature area that can update independently of the base version. Today: **Cargas Pay** (payments). | Headed to **all customers**, rolled out progressively. |

### What a delta is, in plain terms
When we cut a full release, that's the customer's **base version**. A delta is "everything that changed since your base version, bundled up." A customer on `2026.05` applies `2026.05-A` to get fixes without re-installing the product. Deltas are **cumulative** — `-C` contains everything in `-A` and `-B` plus the new changes.

### What the Cargas Pay module is, in plain terms
Payments is the one part of our product where change is forced on us from outside — payment gateways retire APIs, card-industry rules change, tokenization vendors migrate — on timelines our customers don't control. The module packages the **entire payments subsystem** as one unit that can be kept current **without upgrading the customer's whole system**. That's why it's going to every customer: everyone's payments need to stay current, even when their base version doesn't.

## The problem we caught

Deltas and the module both change payment-related parts of the product, but **neither knows the other exists**. A site that has a newer module installed has newer payment structures than its base version — and an older delta carrying payment changes can trip over them.

**The real example (internal testing, no customer affected):** the `2025.10` delta failed on a setup with the `2026.03` Cargas Pay module applied. The newer module had removed a database column; the older delta's instructions still referred to it, and the update errored out.

The fix isn't a patch — it's a rule: **on any version that can run the module, payment changes never travel in deltas.** They travel only in the module. Then there is nothing to collide, by construction.

## The rules that keep base versions and modules compatible ("bands")

A site's base version and module version don't have to match, but they can't drift arbitrarily far apart:

- Modules started at version **2025.08** — older versions can't run one at all (they keep getting payment fixes the old way, via deltas, which is safe precisely because no module can be present).
- Bases **2025.08 through 2026.03** can run module versions **up to 2026.03**.
- Modules **2026.04 and later** require base **2026.04 or later** (newer modules picked up dependencies that need the newer base).

A module can run ahead of its base, but only within a band. Crossing a band boundary means upgrading the base — which happens naturally with a full release (full releases ship the matching module along with them).

## FAQ

**Q: What's actually *wrong* with modules right now?**
Nothing is wrong with the module concept — it does its job. What's missing is the surrounding process: (1) the delta build doesn't separate module content from base content, (2) the installer doesn't check what module a site has before applying things, and there are a couple of missing safety checks (it would currently let an older module overwrite a newer one, or let a too-new module land on a too-old base), and (3) there's no tooling yet to ship a payments fix to module customers between full releases. The gaps are in the plumbing around the module, not the module itself.

**Q: Which customers get the module?**
All of them, eventually — that's the plan. It rolls out progressively. Customers below version 2025.08 need a base upgrade before they can receive it.

**Q: Why is payments a module instead of just part of the main release?**
Because payments must update on the outside world's schedule (gateways, card rules, vendors), and customers upgrade their systems on their own schedule. The module decouples the two: current payments on whatever base version the customer runs (within a band).

**Q: A site has the module. What happens when a delta is applied?**
After this change: nothing payment-related, by design. Deltas for module-era versions (2025.08+) won't contain payment changes at all — those ship through the module. The delta applies its base fixes; the module owns payments. No overlap, no collision.

**Q: I'm fixing a payments bug. Where does my fix go?**
Into the module — it ships as an updated module package (e.g. `2026.03-A`), not in a regular delta. The only exception is a fix targeting versions older than 2025.08, which still travels by delta because those sites can't run a module. The release tooling and an automated PR check will steer you.

**Q: What if my pull request changes both payments files and non-payments files?**
Those now ship through *different channels*, so a mixed change can't ride as one unit. An automated check on the PR will flag it so you can split it (or handle it deliberately). It starts as a warning, not a blocker.

**Q: What about a customer who can run the module but hasn't gotten it yet?**
During rollout, that site doesn't receive new payment fixes through deltas anymore — getting the module *is* how it gets current payments. That's intentional: it keeps the rollout moving. For a genuinely urgent payment fix on a site that hasn't migrated, there's a designated emergency path (an "ad-hoc" package), used deliberately rather than improvised.

**Q: Is applying the module to an existing customer risky?**
It's the step we're treating most carefully. Applying the module updates payment database structures across potentially many versions of change at once, on financially sensitive data. Before rollout we're building dedicated data-migration scripts into the module, tightening the installer's data-loss protections for module installs, and reviewing the installer's generated change reports on the first sites. This is an explicit precondition to rollout, not an afterthought.

**Q: Did this break a real customer?**
No. No customer is running the module yet. The failure was caught in internal testing — which is why we're fixing the process now, before rollout.

**Q: Why do we ship deltas at all instead of just full releases?**
Speed and size. A delta is small and fast to apply, so a high-priority fix reaches customers without the cost and risk of a full upgrade.

**Q: What do I need to do differently?**
- **Developers:** keep payment and non-payment changes in separate PRs; watch for the boundary-check flag. A payments fix ships as a module update — expect that, not a delta.
- **QA:** payments fixes are tested as a module package (the same artifact shape every time, which we'll automate around), across the active bands; base deltas no longer need payments regression on module-era versions.
- **Support / deployment:** a site has *two* version numbers (base and module). If an update is blocked, it's likely a compatibility guard doing its job — check both versions and the band rules.
- **Release managers:** payment fixes fan out to the maintained module heads (one per band — currently a couple) instead of every delta line; the release plan gains a "touches module?" flag.

**Q: When does this change?**
The design is settled and evaluated. The build/installer tooling is the fast part; the gating items are the data-migration work and the installer safety checks, which must land **before** the first production module install. The rollout campaign to all customers is the long pole.

## What we're changing to support this

Four layers, plus the rollout itself. They work together — no single one is sufficient.

### 1. Prevent — catch boundary problems at PR time
- An automated **boundary check on pull requests** that flags when a change mixes module and base files (and when base database code references payment structures — a subtler version of the same problem). Reuses classification logic we already run after-the-fact in EnergyLicenses; moves it to where the author can still act. Advisory first, required later.

### 2. Separate — the build keeps the channels apart
- The delta build **excludes payment files** on module-era versions (2025.08+); they route to the module instead.
- A new **module update build**, so payments fixes ship to module customers between full releases — with versioning (`2026.03-A`), a "did payments actually change?" check so identical updates are never re-shipped, and a declared minimum base version.

### 3. Enforce — make the installer module-aware
- Add the **missing safety checks**: block an older module from overwriting a newer one; block a module from installing on a base that's too old for it (the band rule — today's check would actually allow this).
- These checks only exist on updated installers, so **installer updates roll out before modules do**.

### 4. Protect the data — the rollout precondition
- **Data-migration scripts** built into the module so it can be applied safely to a customer at *any* eligible starting version.
- Tighten **data-loss protections** for module installs and review the installer's change reports on the first sites.

### The rollout itself
- A **migration campaign** to bring all customers onto the module, tracked on an adoption dashboard (we already collect the data nightly), with the ad-hoc package as the urgent-fix escape hatch for not-yet-migrated sites.
- A plan for the **pre-2025.08 tail**, which keeps the old payments-in-deltas path (safely) until those customers upgrade.

## Glossary

- **Base version:** the full release a customer is on (e.g. `2026.05`).
- **Delta:** a small, cumulative patch of what changed since a base version (e.g. `2026.05-B`).
- **Module:** a self-contained package of one feature area that updates independently; today, Cargas Pay (payments).
- **Band:** a compatibility range pairing base versions with the module versions they can run.
- **Module-eligible:** base version 2025.08 or newer — able to run the module.
- **Module-blind / module-aware:** whether a process checks for an installed module before acting.

## Learn more
- Technical design & engineering specifics: [[Projects/Cargas Pay Module Strategy/Design]]
- Project status, decisions, and work items: [[Projects/Cargas Pay Module Strategy/CLAUDE]]
- Related: [[Projects/Deltas/CLAUDE]], [[Projects/MFP CE Module/CLAUDE]]

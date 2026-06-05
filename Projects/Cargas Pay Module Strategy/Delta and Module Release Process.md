---
date: 2026-06-05
tags: [explainer, cargas-pay, deltas, modules, release-engineering, faq]
status: active
audience: broad
---

# Cargas Energy Releases: Deltas & the Cargas Pay Module

> **Who this is for:** anyone at Cargas who touches the release process — developers, QA, support, PMs — who wants to understand how we ship Cargas Energy, what the Cargas Pay module is, why it currently conflicts with deltas, and what we're changing. No deep technical background assumed. A [[Projects/Cargas Pay Module Strategy/Design|technical design doc]] covers the engineering specifics.

## The short version

We ship Cargas Energy three ways: **full releases**, **deltas** (small patches between releases), and **modules** (optional add-ons — today, just Cargas Pay). Deltas and the module were built independently and don't yet know about each other, so applying a delta to a customer who has the module can break things. No customer has hit this yet because module rollout hasn't started — we caught it internally. This document explains the pieces and lays out the changes we need before we roll the module out widely.

## The three ways we ship Cargas Energy

| | What it is | When it's used |
|---|---|---|
| **Full release** | The complete product at a monthly version (e.g. `2026.05`). | Monthly. Every customer eventually lands on a full version. |
| **Delta** | A small package containing only what changed since a full release — quicker to download and apply. Named with a letter, e.g. `2026.05-A`, `-B`. | Between full releases, to push high-priority fixes fast. |
| **Module** | An optional, self-contained add-on for one feature area. Today the only one is **Cargas Pay** (our payments subsystem). | For the subset of customers who use that feature. |

### What a delta is, in plain terms
When we cut a full release, that's the customer's **base version**. A delta is "everything that changed since your base version, bundled up." A customer on `2026.05` can apply `2026.05-A` to get a handful of fixes without re-installing the whole product. Deltas are **cumulative** — `-C` contains everything in `-A` and `-B` plus the new changes.

### What the Cargas Pay module is, in plain terms
Cargas Pay is our payments offering. The module packages up the **entire payments part of the product** as a standalone unit that can be installed on top of a customer's existing version. Its purpose: let a customer who is on an **older base version** still run the **current** Cargas Pay, without forcing them to upgrade their whole system first. Only customers who use Cargas Pay get it — roughly a third of customers, eventually.

## The problem: deltas and modules can collide

Deltas and the module both change payment-related parts of the product, but **neither one knows the other exists**. That's fine until a customer has both a base version *and* a newer module installed — then a delta can trip over the module's changes.

**A real example (caught internally, no customer affected):** the `2025.10` delta failed on a setup that had the `2026.03` Cargas Pay module applied. The newer module had removed a database column; the older delta's instructions still referred to that column, so the update errored out.

Two root realities cause this:

1. **The delta process is "module-blind."** When we build a delta, it just packages whatever changed — including payment changes — with no awareness that some of those changes belong to the module.
2. **The installer is "module-blind."** When it applies a delta or a full release, it doesn't check what module the customer has, so it can overwrite or conflict with the module's version of those payment objects.

Because the module is the whole payments subsystem and a chunk of payments code is shared with customers who *don't* have the module, the same code legitimately travels through **both** channels. So this overlap isn't a one-off bug — it's structural, and it needs a real solution before rollout.

## The rules that keep base versions and modules compatible ("bands")

A customer's base version and their module version don't have to match exactly, but they can't be arbitrarily far apart. There are **compatibility bands** (these specific cutoffs may change over time):

- Modules started at version **2025.08**. A customer on 2025.08 or newer can adopt the module.
- Customers from **2025.08 through 2026.03** can run module versions **up to 2026.03**.
- To run a module from **2026.04 or later**, the customer must be on base **2026.04 or later** — newer modules took on dependencies that require the newer base.

In short: a module can run somewhat ahead of the base version, but only within a band. Crossing a band boundary means upgrading the base version too (which happens naturally during a full release).

## FAQ

**Q: What's actually *wrong* with modules right now?**
Nothing is wrong with the module *concept* — it does its job (current payments on an older base). What's missing is the surrounding process: (1) our delta/release tooling doesn't separate module content from base content, (2) the installer doesn't check the customer's module before applying updates, and (3) we have no clean way to ship a payments fix *to module customers* between full releases. Add a couple of missing safety checks (see below) and the picture is fine. The gaps are in the plumbing around the module, not the module itself.

**Q: Why do we ship deltas instead of just full releases?**
Speed and size. A delta is small and fast to apply, so a high-priority fix can reach customers without the cost and risk of a full re-install.

**Q: Why is Cargas Pay a separate module instead of just part of the main release?**
So customers who haven't upgraded their whole system can still get the latest payments functionality. Bundling it into the full release would force everyone to upgrade everything in lockstep, which many customers can't do on our schedule.

**Q: Which customers get the module?**
Only those who use Cargas Pay — a subset, targeted at roughly 30% of customers over time. The other ~70% continue to get payments through the normal full-release and delta path.

**Q: Can any customer get any module version?**
No — see [bands](#the-rules-that-keep-base-versions-and-modules-compatible-bands). A customer can run a module somewhat newer than their base, but only within a compatibility band; newer modules require a newer base.

**Q: A customer has the module. What happens when they get a delta?**
Today: the delta may try to change payment objects the module owns, and conflict. After the changes below: the delta will apply its **non-payment** parts normally and **skip** the payment parts (because the module owns those on that customer), so there's no collision.

**Q: I'm fixing a payments bug. Where does my fix go?**
It will need to reach two audiences: non-module customers (through the normal delta) and module customers (through an updated module). The tooling will handle producing both — but you should expect a payments fix to "ship twice," and you'll be prompted if your change crosses the line.

**Q: What if my pull request changes both payments files and non-payments files?**
That "mixed" change is the root of most of this pain. We're adding an automated check that flags it on the PR so you can decide to split it or handle it deliberately. It won't block you at first — it's there to make accidental mixing visible.

**Q: Why not just ban payment changes from deltas entirely?**
Because non-module customers (the majority) still need payment fixes between releases, and the delta is how they get them. So payments can't simply leave the delta channel — instead the installer learns to skip them only on customers who have the module.

**Q: Did this break a real customer?**
No. No customer is running the module yet. The failure was caught in internal testing — which is exactly why we're designing the fix now, before rollout.

**Q: Why not make *every* customer use the module, or *no* customer?**
"Everyone" isn't viable — many customers can't upgrade to the base versions newer modules require. "No one" defeats the purpose of letting older-base customers get current payments. So we live with a mix, which is why the two channels must coexist cleanly.

**Q: What do I need to do differently?**
- **Developers:** keep payment changes and non-payment changes in separate PRs when you can; watch for the boundary-check flag.
- **QA:** a payments fix now needs testing in both worlds — a non-module customer and a module customer — and across the relevant compatibility bands.
- **Support / deployment:** be aware a customer has *two* version numbers (base and module); when an update is blocked, it's likely a compatibility guard doing its job.
- **Release managers:** payment fixes fan out to the module as well as the base deltas; the release plan will gain a column to track this.

**Q: When does this change?**
The design is done; implementation is sequenced (below) and is intended to land **before** module rollout passes a handful of sites.

## What we're changing to support this

The fixes fall into four layers. They work together — no single one is sufficient.

### 1. Prevent — catch mixed changes early
- An automated **boundary check on pull requests** that flags when a change touches both module and base code, so it can be split or handled on purpose. It reuses logic we already have in EnergyLicenses (which does this *after the fact* today) and moves it earlier, to PR time. Advisory at first, stricter later.

### 2. Separate — keep the two channels apart when we build
- The delta build will **separate payment content** so it can be applied to non-module customers and skipped for module customers.
- A new **"module update" build** so payments fixes can ship to module customers between full releases.
- **Skip rebuilding** a module update when payments haven't actually changed (avoids shipping identical "new" updates).

### 3. Enforce — make the installer module-aware
- On a customer with the module, a delta or release **leaves the module's payment objects alone** instead of overwriting them.
- Add the **missing safety checks** the installer doesn't have today:
  - don't let an **older** module overwrite a newer one already installed;
  - don't let a module install onto a base version that's **too old for it** (the band rule). *(Today's check is actually backwards on this point and would allow it.)*

### 4. Track — know what's compatible with what
- Each package **describes its own requirements** (e.g. "needs payments fix CAR-12345"), and the installer checks that against the customer — so there's no giant compatibility spreadsheet to maintain as releases pile up.
- The existing per-release plan gains a **"touches the module?" flag** and the set of module versions a fix needs to reach.

### Supporting work
- **Finish testing** that module files built at one version run correctly against a different base version (partially done).
- **Audit** that the module truly contains the *complete* payments subsystem, so an older-base customer isn't missing anything.

## Glossary

- **Base version:** the full release a customer is on (e.g. `2026.05`).
- **Delta:** a small, cumulative patch of what changed since a base version (e.g. `2026.05-B`).
- **Module:** an optional add-on for one feature area; today, Cargas Pay (the payments subsystem).
- **Band:** a compatibility range pairing base versions with the module versions they can run.
- **Module-blind / module-aware:** whether a process checks for an installed module before acting.

## Learn more
- Technical design & engineering specifics: [[Projects/Cargas Pay Module Strategy/Design]]
- Project status, decisions, and work items: [[Projects/Cargas Pay Module Strategy/CLAUDE]]
- Related: [[Projects/Deltas/CLAUDE]], [[Projects/MFP CE Module/CLAUDE]]

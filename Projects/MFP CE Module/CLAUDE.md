# Project: MFP CE Module

## Overview
A new CargasEnergy module (modeled after CargasPay) that ships the APIs and stored procedures MyFuelPortal depends on. The problem it solves: MFP calls CE APIs/sprocs that may not exist in older customer CE versions. Deploying this module ensures those data calls succeed regardless of what base version of CE the customer is running.

## Status
- **Phase:** Planning
- **Progress:** 5%
- **Started:** 2026-04-17
- **Target:** TBD

## Goal Link
Supports: [[2. Yearly Goals#Engineering Delivery]] (MFP management and handoff)
Related: [[Projects/MyFuelPortal/CLAUDE]] — the module exists to unblock MFP deployments

## How CE Modules Work

Modules are defined in `module.json` at the root of `D:/repos/CargasEnergy`. Each entry includes:
- `name` — display name
- `guid` — unique module identifier (must also be registered in `Util_TableValues` as `cModules`)
- `web` — list of web files (DLLs, webpack output, ASPX pages, scripts, styles) relative to `CargasEnergyWeb`
- `db` — list of DB schema files (tables, stored procs, functions, schemas) relative to `CargasEnergyDB`
- `PostDeploymentScript` — optional SQL to run after module deployment (e.g., `exec dbo.Util_UpdateSolutionForCargasPayModule '{0}'`)

**Reference implementation:** `D:/repos/CargasEnergy/CargasPay/` — C# project with a `.csproj`, startup registration, ASMX web service, and its DB objects tracked in `module.json`.

**Packaging:** `D:/repos/Ancillary-Projects/BuildDeployPackage` and `BuildManifest` handle module packaging. Need to explore these to understand the build/deploy pipeline for modules.

## What the MFP Module Needs to Contain

The module should ship whatever stored procedures and APIs MFP calls that are not guaranteed to exist in a customer's CE version. Specifically:

- [ ] Audit: identify all CE API stored procs called by MFP (start with MFP codebase — look for CE API calls)
- [ ] Determine which of those procs are version-sensitive (added in newer CE releases)
- [ ] Decide: DB-only module, or does it also need a web/DLL component?

Likely **DB-only or mostly DB** — MFP primarily talks to CE via stored procs through the API schema. The CargasPay module is a useful reference but is much larger (payment UI, DLL, webpack) — the MFP module will probably be simpler.

## Key Decisions
| Date | Decision | Context |
|------|----------|---------|
| 2026-04-17 | Module approach chosen | MFP calls CE sprocs that may not exist in older CE versions; module deployment solves this cleanly without requiring customers to be on latest CE |

## Next Actions
- [ ] Explore `D:/repos/Ancillary-Projects/BuildDeployPackage` and `BuildManifest` to understand module packaging pipeline
- [ ] Audit MFP codebase for all CE API stored proc calls — build the list of what needs to ship in the module
- [ ] Determine if a web/DLL component is needed or if DB-only is sufficient
- [ ] Create new C# project in CargasEnergy (if web component needed) following CargasPay pattern
- [ ] Generate a new GUID for the module
- [ ] Add module entry to `module.json` with `name`, `guid`, `web`, `db` lists
- [ ] Register module GUID in `Util_TableValues` (`cModules`)
- [ ] Write/move stored procs into the module's DB file list
- [ ] Add `PostDeploymentScript` if needed
- [ ] Test module deploy against an older CE version to validate it solves the version gap

## Blockers
- Need to audit MFP→CE API calls before scope is defined
- Need to understand Ancillary-Projects packaging pipeline before build/deploy path is clear

## Resources
- **Reference module:** `D:/repos/CargasEnergy/CargasPay/`
- **Module manifest:** `D:/repos/CargasEnergy/module.json`
- **Packaging tools:** `D:/repos/Ancillary-Projects/BuildDeployPackage`, `BuildManifest`
- **Related repo:** `D:/repos/MyFuelPortal`
- **Supports:** [[2. Yearly Goals#Engineering Delivery]]
- **Related:** [[Projects/MyFuelPortal/CLAUDE]]

## Notes
The CargasPay module is large (payment UI, gateways, DLL, webpack). The MFP module is likely much narrower — primarily DB schema objects (stored procs, maybe a schema). Start with the audit before assuming scope.

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

## What the MFP Module Contains

This module is **entirely new** — it does not backport or re-ship existing CE functionality. Everything in it is written specifically for MFP.

### MFP API Schema
A new DB schema scoped exclusively to MFP. Stored procs and objects in this schema are written for MFP's needs and live only in this module — they are not part of base CE.

### MFP API Key System
A new API key designation specifically for MFP. Key design decisions:
- MFP API keys are created alongside regular CE API keys but flagged as MFP-designated
- **Existing API keys cannot be re-designated as MFP API keys** — MFP keys must be created as such from the start
- The module ships the tables, stored procs, and logic to create and manage MFP API keys

### MFP-Designated CE Endpoints
CE exposes new API endpoints (in the MFP schema) that MFP calls. These endpoints require an MFP API key — regular CE API keys are not accepted. MFP calls CE, as always; the MFP API key is simply how those calls are authenticated against the new MFP-specific endpoints.

Likely **DB-only or mostly DB** — the new endpoints are stored procs under the MFP schema, called through CE's existing API layer. May not need a new C# project unless there's logic that can't live in SQL.

## Key Decisions
| Date | Decision | Context |
|------|----------|---------|
| 2026-04-17 | Module approach chosen | MFP calls CE sprocs that may not exist in older CE versions; module deployment solves this cleanly without requiring customers to be on latest CE |

## Next Actions
- [ ] Explore `D:/repos/Ancillary-Projects/BuildDeployPackage` and `BuildManifest` to understand module packaging pipeline
- [ ] Design the MFP API key schema — tables, procs for create/read/validate, designation flag, constraints preventing re-designation of existing keys
- [ ] Design the CE→MFP endpoint — what does CE need to call on the MFP side, and how does the MFP API key authorize it?
- [ ] Spec out the MFP schema objects (stored procs, tables) that ship in the module
- [ ] Determine if a C# project is needed or if DB-only (stored procs under MFP schema) is sufficient
- [ ] Generate a new GUID for the module
- [ ] Add module entry to `module.json` with `name`, `guid`, `web`, `db` lists
- [ ] Register module GUID in `Util_TableValues` (`cModules`)
- [ ] Add `PostDeploymentScript` if needed (e.g., seed MFP key type records)
- [ ] Test module deploy against an older CE version

## Blockers
- Need to define what CE needs to call back into MFP before the endpoint can be designed
- Need to understand Ancillary-Projects packaging pipeline before build/deploy path is clear

## Resources
- **Reference module:** `D:/repos/CargasEnergy/CargasPay/`
- **Module manifest:** `D:/repos/CargasEnergy/module.json`
- **Packaging tools:** `D:/repos/Ancillary-Projects/BuildDeployPackage`, `BuildManifest`
- **Related repo:** `D:/repos/MyFuelPortal`
- **Supports:** [[2. Yearly Goals#Engineering Delivery]]
- **Related:** [[Projects/MyFuelPortal/CLAUDE]]

## Notes
The CargasPay module is large (payment UI, gateways, DLL, webpack). The MFP module will be narrower but does need a web component for the CE→MFP callback endpoint. The key design constraint: MFP API keys are a new, distinct designation — not a flag you can set on an existing key. This needs to be enforced at the data layer (probably a separate table or a non-nullable type column set only at creation time).

The interesting architectural question here is the direction of calls: typically MFP calls CE, but this module also enables CE to call MFP — which is a new pattern worth thinking through carefully (auth, error handling, what triggers the call).

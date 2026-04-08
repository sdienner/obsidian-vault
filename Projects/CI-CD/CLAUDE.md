# Project: CI/CD

## Overview
CI/CD pipeline support across two products — Cargas Energy and MyFuelPortal (MFP) — with a focus on reducing delta release friction and eventually handing off the process.

## Status
- **Phase:** Active
- **Progress:** 20%
- **Started:** 2026-04-01
- **Target:** Handoff by Q3 2026

## Goals
- Reduce delta release friction (currently tedious/manual)
- Document process well enough to hand off to a team lead
- Resolve API versioning question for MFP (how APIs not on CE instances are handled)
- MFA implementation for MyFuelPortal

## Current Focus
- Delta building (started 2026-04-01)
- Upload last delta release
- API versioning: talk to Casey about MFP approach

## Key Decisions
| Date | Decision | Context |
|------|----------|---------|
| 2026-04-01 | Delta building started | New release process initiated |
| 2026-04-01 | MFA spec passed along | Spec received for MFP MFA |

## Next Actions
- [ ] Upload last delta release
- [ ] Talk to Casey about API versioning (MFP APIs not present on CE instances)
- [ ] Document delta release process for handoff
- [ ] Follow up on Silverline SQL role permissions

## Blockers
- API versioning decision pending Casey conversation

## Resources
- Jira: CAR-34157 (waiting on 2026b.03 deployment — Eric Taylor)
- **Supports:** [[2. Yearly Goals#Career & Leadership]] (handoff goal)

## Notes for Claude
Delta releases are the key operational burden Scott wants to hand off. 2026b.03 deployment: Ryan is packaging, targeting ~4pm (2026-04-07). Eric Taylor is waiting on it for CAR-34157. MFP = MyFuelPortal.

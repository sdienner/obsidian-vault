---
date: 2026-05-29
tags: [review, activity-summary]
period: 2026-04-26 to 2026-05-10
status: completed
---
# Activity Summary: April 26 - May 10, 2026

Reconstructed from M365 activity (emails, meetings, Teams chats, documents).

---

## Week 1: April 27 - May 1

### Monday, April 27
- **Dev SUM** (9:30-10:00) — full team stand-up
- **May Monthly Delta Kickoff** (1:00-1:20) — release planning for the May delta cycle with Ed Stewart, Tony, Andrea, Nate, and cross-functional group
- Emailed Fred re: **Atlassian API token expiration** — validated whether PhoneHome Connector token is still in use before acting
- Teams: confirmed deployment assignments for Ryan (originally 6 PM, shifted to 3 PM)

### Tuesday, April 28
- **Weekly Fleet Delta quick chat** (10:30-10:45) with Eric Taylor
- **1:1 with Anne Nguyen** (11:00-12:00)
- **Open Collaboration** (1:00-2:00) — full dev team
- **Product Leadership** (2:00-3:00) — product status, technical initiatives, team updates (transcribed)
- **MFP Deployments/Server Moves** quick chat (4:30-4:50) with Bob Graybill
- Teams: CAR ticket clarification, short technical exchanges

### Wednesday, April 29
- **MFP Tech Ticket Time** (9:00-10:00) with Casey + optional group
- **Cargas Running Club** (12:00-1:00)
- **Recent Release Performance Retro** (1:30-2:30) with Fred, Ryan, Tom
- **Wine Wednesday** (4:00-5:00)
- Teams: deployed **2026b.04-A to BetaRelease on cargas-qa**
- Teams (Fleet Fueling channel): clarified delta inclusion — fix not in base release but will be in deltas going forward
- Email: **customization billing thread** with Justin — flagged that a billing change swings the sprint bottom line

### Thursday, April 30
- **Dev SUM** (9:30-10:00)
- **A&B Propane (AZ) MFP Deployment / Portal Build** (2:00-3:30) with Casey + cross-functional group
- Teams: caught and fixed a **mistaken double-commit push** — rebuilt and redeployed same day
- Teams: asked about deployment effort for latest version to customer environments
- Teams: directed **DB + tenant removal steps** in Octopus for decommissioning; asked Casey about current decommission process

### Friday, May 1
- **1:1 with Ryan Schubert** (10:00-11:00)
- **FESG: The Meeting** (11:00-12:00) with Fred and Ed Stewart
- **MFP Tech Ticket Time** (2:00-3:00)
- **1:1 with Fred Bowers** (3:00-4:00)
- Teams: branch management — confirmed keeping sprint branch open

---

## Week 2: May 4 - May 8

### Sunday, May 4
- Reported a **phishing email** via Phish Alert system

### Monday, May 5
- **MFP Squad Catch-up** (4:00-5:00) with Casey and Andrea
- **Product Leadership** (2:00-3:00) with Fred, Andrea, Ed Stewart
- Teams: nudged Nate on a pending PR ("I bugged Nate")
- Teams: asked team to **validate/test a suggested solution** ASAP
- Teams: casual team engagement ("I'll be here!" for helping unload)

### Tuesday, May 6
- **SPP - Override Tank Percentage** (10:00-10:30) with Justin — technical review
- **Superior Plus - One-time Payment Customization Review** (10:30-11:00) with Casey and Matt
- **FESG: The Meeting** (1:00-2:00) with Fred and Ed Stewart
- **LT: Talent Roadmap Update** (3:00-4:00) with Ed, Gale, Adam, Shawn
- **Exchanging Solutions** (4:00-5:00) with Fred, Jonathan, Anthony Christian
- Teams: made a **hold call on Taylor deployment** — moved to next day ("No Taylor deployment tonight")
- Teams: checked NOCO deployment readiness with Matt ("Anything for NOCO? Matt is standing by")
- Screenshots captured (2) — likely debugging or documentation support

### Wednesday, May 7
- **MFP Release Notes / Change Log** (9:00-9:30) with Bill Decker
- **Dev SUM** (9:30-10:00) — full team
- **Feature Management - Site Cleanup** (10:00-10:30) with Ryan
- **Product Team Monthly Meeting** [in-person] (11:45-1:30) with Fred, Aaron, Pam, Justin, Tony, Ryan
- **Sprint Planning** (2:30-3:00) with Andrea, Ian, Shane
- Teams: guided team on branch strategy — "Put it in a separate feature branch"
- Teams: shared **Product Team MAY 2026 Meeting.pptx** in channel, gave recognition ("Great job on this")
- Teams: provided system-level remediation steps (DB + IIS removal)

### Thursday, May 8
- **Dev Sprint Retro** (9:00-11:00) — full dev team
- **MFP Tech Ticket Time** (2:00-3:00)
- **MFP Weekly Operational Call** (3:00-4:00) with Fred, Aaron, Andrea, Pam, Shawn — mobile analytics, MFA design/rollout, SMTP compliance, PCI/SOC audit scope
- Edited **release-audit-release-2026.04.md** — commit analysis, Jira mappings, release validation
- Teams: announced **new release workflow** — "I'll put it in a PR"
- Teams: scoped a **new tank monitor integration** epic — "This is going to have to be a new tank monitor integration"
- Screenshot captured — likely tied to release audit work

---

## Top Workstreams

### 1. Release Engineering (2026b.04 Delta)
Hands-on throughout: built/deployed deltas to beta, fixed deployment mistakes, made go/no-go calls for customer deployments (NOCO, Taylor), coordinated with QA (Gale) on blocking bugs, and authored the release audit document. Introduced a new release workflow by the end of the period.

### 2. MyFuelPortal Product Work
Participated in MFP squad catch-ups, tech ticket sessions, deployment planning (A&B Propane portal build), server moves, release notes/change log, and the weekly operational call covering MFA, mobile analytics, and compliance.

### 3. Sprint & Delivery Management
Ran stand-ups, sprint planning, sprint retro. Managed the customization billing impact on sprint financials. Coordinated branch strategy and PR flow with the team.

### 4. People & Leadership
1:1s with Anne, Ryan, and Fred. Talent Roadmap Update session. Product Leadership recurring meetings. Recognized team contributions publicly in channels.

### 5. Technical Decision-Making
CP module discussion with Fred and Tom. SPP tank percentage override review with Justin. Superior Plus payment customization review. Feature management site cleanup with Ryan. Scoped new tank monitor integration epic.

### 6. Process & Infrastructure
Validated Atlassian API token usage. Directed decommissioning steps (DB + Octopus tenant removal). Phishing report. Branch protection and `dev/` naming convention work (from May 4 daily note).

---

## Key Collaborators

| Person | Interaction Type |
|--------|-----------------|
| **Fred Bowers** | 1:1, product leadership, FESG, CP module, MFP ops |
| **Casey Holland** | MFP squad, tech tickets, payment review, decommissioning |
| **Ryan Schubert** | 1:1, retro, release performance, feature mgmt, deployments |
| **Andrea Bierly** | MFP squad, product leadership, sprint planning |
| **Justin Madilia** | Billing thread, SPP review, stand-ups |
| **Tom Groff** | Release retro, CP module, ticket prioritization |
| **Eric Taylor** | Fleet delta, release coordination, bug tracking |
| **Gale Shirk** | QA escalation, talent roadmap |
| **Ed Stewart** | FESG, talent roadmap |
| **Matt Hahn** | Payment review, NOCO deployment readiness |
| **Nate Kindrew** | PR follow-ups, delta kickoff |
| **Anne Nguyen** | 1:1 |

---

## Carried Work (from daily notes)

Progress confirmed during this window:
- [x] Deploy MFPQueryManager to Silverline
- [x] Write up code review decisions and share with the team
- [x] Branch protection enabled, `dev/` naming convention established
- [ ] Open PR in energy-dev-docs with coding guidelines — [PR #16](https://github.com/Cargas/energy-dev-docs/pull/16) (opened, pending)
- [ ] Implement Jira -> Cargas Pay module review process
- [ ] Get Casey's new MFP release strategy off the ground
- [ ] Implement Octopus API in CustomerHub

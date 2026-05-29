---
date: 2026-05-29
tags: [review, activity-summary]
period: 2026-04-26 to 2026-05-24
status: completed
---
# Activity Summary: April 26 - May 24, 2026

Reconstructed from M365 activity (emails, meetings, Teams chats, documents). Four weeks of work covering two full sprint cycles.

---

## Week 1: April 27 - May 1

### Monday, April 27
- **Dev SUM** — full team stand-up
- **May Monthly Delta Kickoff** — release planning for the May delta cycle with Ed Stewart, Tony, Andrea, Nate, and cross-functional group
- Emailed Fred re: **Atlassian API token expiration** — validated whether PhoneHome Connector token is still in use before acting
- Teams: confirmed deployment assignments for Ryan (originally 6 PM, shifted to 3 PM)

### Tuesday, April 28
- **Weekly Fleet Delta quick chat** with Eric Taylor
- **1:1 with Anne Nguyen**
- **Open Collaboration** — full dev team
- **Product Leadership** — product status, technical initiatives, team updates (transcribed)
- **MFP Deployments/Server Moves** quick chat with Bob Graybill
- Teams: CAR ticket clarification, short technical exchanges

### Wednesday, April 29
- **MFP Tech Ticket Time** with Casey + optional group
- **Recent Release Performance Retro** with Fred, Ryan, Tom
- Teams: deployed **2026b.04-A to BetaRelease on cargas-qa**
- Teams (Fleet Fueling channel): clarified delta inclusion — fix not in base release but will be in deltas going forward
- Email: **customization billing thread** with Justin — flagged that a billing change swings the sprint bottom line

### Thursday, April 30
- **Dev SUM**
- **A&B Propane (AZ) MFP Deployment / Portal Build** with Casey + cross-functional group
- Teams: caught and fixed a **mistaken double-commit push** — rebuilt and redeployed same day
- Teams: directed **DB + tenant removal steps** in Octopus for decommissioning; asked Casey about current decommission process

### Friday, May 1
- **1:1 with Ryan Schubert**
- **FESG: The Meeting** with Fred and Ed Stewart
- **MFP Tech Ticket Time**
- **1:1 with Fred Bowers**
- Teams: branch management — confirmed keeping sprint branch open

---

## Week 2: May 4 - May 8

### Monday, May 5
- **Product Leadership** with Fred, Andrea, Ed Stewart
- **MFP Squad Catch-up** with Casey and Andrea
- Teams: nudged Nate on a pending PR
- Teams: asked team to validate/test a suggested solution ASAP
- Reported a **phishing email** via Phish Alert system (May 4)

### Tuesday, May 6
- **SPP - Override Tank Percentage** with Justin — technical review
- **Superior Plus - One-time Payment Customization Review** with Casey and Matt
- **FESG: The Meeting** with Fred and Ed Stewart
- **LT: Talent Roadmap Update** with Ed, Gale, Adam, Shawn
- **Exchanging Solutions** with Fred, Jonathan, Anthony Christian
- Teams: made a **hold call on Taylor deployment** — moved to next day
- Teams: checked NOCO deployment readiness with Matt

### Wednesday, May 7
- **MFP Release Notes / Change Log** with Bill Decker
- **Dev SUM** — full team
- **Feature Management - Site Cleanup** with Ryan
- **Product Team Monthly Meeting** [in-person] with Fred, Aaron, Pam, Justin, Tony, Ryan
- **Sprint Planning** with Andrea, Ian, Shane
- Teams: guided team on branch strategy — separate feature branches
- Teams: shared **Product Team MAY 2026 Meeting.pptx**, gave team recognition

### Thursday, May 8
- **Dev Sprint Retro** — full dev team
- **MFP Tech Ticket Time**
- **MFP Weekly Operational Call** with Fred, Aaron, Andrea, Pam, Shawn — mobile analytics, MFA design/rollout, SMTP compliance, PCI/SOC audit scope
- Edited **release-audit-release-2026.04.md** — commit analysis, Jira mappings, release validation
- Teams: announced **new release workflow** — putting it in a PR
- Teams: scoped a **new tank monitor integration** epic

---

## Week 3: May 11 - May 15

### Monday, May 11
- Granted **Kyle Marten** read-only GitHub access + added to tech services team
- Confirmed **Customer Hub deltas** uploaded and ready for scheduling (Ian Dennis)
- Clarified **FICO score data access** with Andrea and Casey — DB-level + role-based access; added sprint/branch updates in Jira (`sprint/2026.105`)
- Quick coordination with Gale on meeting timing

### Tuesday, May 12
- Helped **Rob Mallon** debug a **Zendesk API** field update issue — suggested adding the `organization_fields` layer

### Wednesday, May 13
- Flagged need to **rebuild APK and merge bug fix** (CAR-34808) into 2026.05 stable release (Product Team / 2026 Stable Releases channel)

### Thursday, May 14 — High activity day
- **Copilot budget cap** discussion with Fred — proposed removing company cap or increasing to ~$200
- Coordinated **deployment windows** with Jeremy Yoder — recommended 9:30 PM or 9:30 AM based on team availability
- Finalized **next-day 9:30 AM deployment** plan with Ryan and Tony (~1 minute estimated duration)
- **Built and deployed 2026b.04-C** — confirmed build success with Eric Taylor, clarified delta file locations
- Reviewed **eCheck failure root cause** with Casey — ProfileType vs CardType issue
- Looped in Tom for deeper **payment profile logic review** — confirmed Tom's analysis, adopted more robust implementation
- Required **new APKs** despite no version bump; granted Ryan repo/branch permissions
- Discussed **release notes architecture** with Ryan — scoped notes, modular delivery, suggested Excel export + HTML path
- Recommended **ASAP Customer Hub rollout** to Ian Dennis, flagged caution on Friday timing
- **Claude team plan** — noted join requests to Michael Poland, suggested it may be worthwhile vs free tier
- Explained **SMTP relay/IP allowlisting** to Ginger Seui and Casey — emails originate from web servers, not configurable via app settings

### Friday, May 15
- Clarified **deployment log locations** for Tony and Ryan (deployments tab vs logs)
- Asked Dev SUM for **SPP release status** — Tom reported successful release with minor bug fix
- Validated **eCheck fix** working with Casey — explained improved implementation approach
- Approved **Jonathan Bowman's remote work** arrangement
- Told Ryan: **migrations are overkill** — likely scrapping them

---

## Week 4: May 18 - May 24

### Early week (May 18-19)
- **Product Leadership** meeting (May 19, transcribed) — major topics:
  - Ran **Cargas Pay module (05) analysis** — identifying fixes and improving Jira tracking for changed files
  - **Automated release notes** — goal to reduce ~4 hours/release of manual effort, integrating into Customer Hub with filtering/export
  - Product features: sniff testing, days-to-run-out, fleet fueling workflows, service dashboard KPIs, equipment age, work order templates
  - **NOCO go-live delays** — concern about repeated delays due to bugs, ongoing customer pressure
  - **GitHub Copilot cost increase** (5-10x) — distributed info across channels
  - Raised **process gap** — confusion about bundling tasks into releases outside sprints, suggested Jira sprint structure
  - **API security** progress (waiting on resources), **MFA** rollout status
- Rescheduled **1:1 with Tom** due to double-booking
- Rescheduled **1:1 with Nate** to another day

### Mid-week (May 20-22)
- Applied **2026b.04-D to BetaRelease** — confirmed in channel
- **Uploaded delta to Customer Hub** — confirmed in CE Delta Updates channel, clarified it pushes like a normal code update
- Coordinated **NOCO Friday 9:30 AM deployment** with Tony; shared 2026b.04-D.zip
- Assigned Tony as deploy owner ("It will be Tony again")
- Checked QA readiness timing with Gale/Eric
- Heavy **QA debugging with Casey**:
  - Deployed to QA, hit a loop issue, resolved it ("QA works again.. phew")
  - Investigated whether **web.config merge issues** caused Raygun deployment failure
  - Built new package to test on different internal site
  - Guided Casey on branch reuse for fixes
- Requested Casey include remaining items in **Energo's report** before her trip
- **Work intake triage** — "Do you need it ASAP? Do you have QA lined up?" then assigned Jonathan and told them to loop in Gale
- Guided **Jonathan** on deployment tooling (PhoneHome task scheduling) and branching strategy (separate feature branch, PR as draft)
- Asked Ryan to push up changes; discussed branch management
- Discussed **S+ / MFP ownership handoff** with Andrea — Casey handing off remaining work before trip
- **Licensing question** to Fred — "Would we really license by users making routes?"
- Reminded **Justin** to put vacation on his calendar
- **GPS channel** — engaged in delivery center filtering bug discussion
- Shared QA release links in Dev SUM (`siteRemovalExceptions`)
- Light technical reaction with Tom — "These are brutal" / "Maybe we do serially?"

### Team culture
- Daily **Wordle/Connections** posts in Werdlers channel
- Dealt with a **power outage** mid-week — switched to hotspot
- AI infographic discussion in Dev SUM

---

## Top Workstreams (Full Period)

### 1. Release Engineering
The dominant thread across all four weeks. Built and deployed deltas **2026b.04-A through D** to BetaRelease. Made go/no-go calls for customer deployments (NOCO, Taylor). Fixed deployment mistakes in real time. Managed QA timing and deployment assignments (Tony as primary deploy owner). Authored the release audit document. Introduced a new release workflow. Uploaded deltas to Customer Hub. Drove toward **automated release notes** to cut ~4 hours/release of manual work.

### 2. MyFuelPortal
Consistent involvement: MFP squad catch-ups, tech ticket sessions, deployment planning (A&B Propane portal build), server moves, release notes/change log, weekly operational call (MFA, mobile analytics, SMTP, PCI/SOC), SMTP relay clarification, and S+/MFP ownership handoff when Casey went on trip.

### 3. Payment Processing
Investigated and resolved the **eCheck failure** (ProfileType vs CardType bug) across multiple days — involved Casey for initial triage, Tom for deeper payment profile logic review, then validated the fix. Also reviewed **Superior Plus one-time payment customization** and **SPP tank percentage override**.

### 4. QA & Environment Stability
Recurring firefighting: QA loop issues, web.config merge problems causing Raygun deployment failures, rebuilding packages for internal site testing, and coordinating same-day QA validation for customer go-lives. Managed the **delivery center bug** that risked Hall's go-live.

### 5. Sprint & Delivery Management
Ran stand-ups (Dev SUM), sprint planning, sprint retro. Managed customization billing impact on sprint financials. Coordinated branch strategy and PR flow. Raised the process gap around bundling tasks into releases outside sprints.

### 6. Product Strategy
Product Leadership meetings (weekly). Product Team Monthly Meeting (in-person). Cargas Pay module analysis and Jira tracking improvements. Feature discussions: sniff testing, days-to-run-out, fleet fueling, service dashboard KPIs, equipment age, work order templates, Cargas Pay funding platform. Release notes architecture (scoped notes, modular delivery).

### 7. People & Leadership
- **1:1s:** Anne, Ryan, Fred, Tom (rescheduled), Nate (rescheduled)
- **Talent Roadmap Update** with Ed, Gale, Adam, Shawn
- Approved Jonathan's remote work
- Granted Kyle Marten GitHub access
- Granted Ryan repo/branch permissions
- Reminded Justin about vacation calendar
- Team recognition in channels
- Managed Casey's workload transition before her trip

### 8. AI/Tooling Governance
Proposed removing or raising Copilot budget cap (~$200) with Fred. Noted Claude team plan adoption. Acknowledged Copilot cost increase (5-10x) and distributed info. Light Dev SUM discussion on AI tooling.

### 9. Technical Decisions
- CP module discussion with Fred and Tom
- Tank monitor integration — scoped as new epic
- Migrations — decided they're overkill, likely scrapping
- Feature management site cleanup with Ryan
- Zendesk API debugging for Rob Mallon
- Branch protection and `dev/` naming convention
- Decommissioning process (DB + Octopus tenant removal)
- Atlassian API token validation

---

## Key Collaborators

| Person | Role in This Period |
|--------|-------------------|
| **Fred Bowers** | 1:1s, product leadership, FESG, CP module, MFP ops, Copilot budget, licensing |
| **Casey Holland** | MFP squad, tech tickets, payment bugs, QA debugging, Energo report, S+ handoff |
| **Ryan Schubert** | 1:1, deployments, release notes arch, APKs, feature mgmt, migrations decision |
| **Tony Bianco** | Primary deploy owner (NOCO, Taylor), delta coordination, sprint retro |
| **Tom Groff** | Payment profile review, release retro, CP module, ticket prioritization |
| **Andrea Bierly** | MFP squad, product leadership, sprint planning, FICO access, S+ handoff |
| **Justin Madilia** | Billing thread, SPP review, stand-ups, vacation calendar |
| **Jonathan Bowman** | Branching/deployment guidance, bug assignments, remote work |
| **Eric Taylor** | Fleet delta, release coordination, build/deployment status |
| **Gale Shirk** | QA escalation, talent roadmap, release readiness timing |
| **Nate Kindrew** | PR follow-ups, delta kickoff, 1:1 rescheduling |
| **Ed Stewart** | FESG, talent roadmap |
| **Ian Dennis** | Customer Hub delta timing |
| **Matt Hahn** | Payment review, NOCO deployment readiness |
| **Anne Nguyen** | 1:1 |

---

## Carried Work (from daily notes)

Progress confirmed during this window:
- [x] Deploy MFPQueryManager to Silverline
- [x] Write up code review decisions and share with the team
- [x] Branch protection enabled, `dev/` naming convention established
- [ ] Open PR in energy-dev-docs with coding guidelines — [PR #16](https://github.com/Cargas/energy-dev-docs/pull/16) (opened, pending)
- [ ] Implement Jira -> Cargas Pay module review process (in progress — ran analysis on module 05)
- [ ] Get Casey's new MFP release strategy off the ground
- [ ] Implement Octopus API in CustomerHub
- [ ] Automated release notes generation (discussed in Product Leadership, planning integration into Customer Hub)

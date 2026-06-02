---
date: 2026-05-18
updated: 2026-06-02
tags: [project, initiative, planning]
status: active
---
# Code Collective — Setup Outline

## The Three-Layer Model

Code Collective isn't one thing — it's the execution layer in a three-part system.

| Layer | Owner | Function |
|-------|-------|----------|
| **Enterprise Enablement** | Kim Ireland / Biz Ops | Demand pipeline — surfaces workflow pain points company-wide, centralized intake (Asana form), prioritized list |
| **Code Collective** | Scott / Engineering | Execution framework — who builds, when, with what governance |
| **Vibe Coding Server** | Scott / Infrastructure | Deployment platform — container hosting, Entra App Proxy SSO, per-app publishing, CI/CD |

Enterprise Enablement answers *what to build*. Code Collective answers *who builds it and when*. The Vibe Coding Server answers *where it runs and how it ships*.

---

## Phase 1: Alignment & Steering (Weeks 1-3)

### Connect with Enterprise Enablement
- [ ] Meet with Kim Ireland — align Code Collective as execution arm of Enterprise Enablement
- [ ] Agree on shared project board (Kim's Asana list vs. new shared system)
- [ ] Define handoff process: how does an Enterprise Enablement request become a Code Collective project?
- [ ] Establish feedback loop: how do completed projects get surfaced back to the company?

### Form Steering Committee
- [ ] Identify members — cross-functional representation (Engineering, Biz Ops, at least one non-technical sponsor)
- [ ] Kim Ireland as Biz Ops liaison (she's already thinking about this)
- [ ] Fred Bowers as executive champion (he's actively asking for this)
- [ ] 2-3 developers with interest (Jonathan B, others from existing informal projects)
- [ ] Define charter: meeting cadence, decision rights, scope boundaries

### Define Governance Framework
- [ ] Time allocation model — how much dedicated time, who approves, how tracked
- [ ] Project intake criteria — what qualifies as a Code Collective project vs. product work
- [ ] The "30-90 minute rule" — quick hits (under 2 hours) vs. structured projects (multi-sprint)
- [ ] Client work priority guarantee — clear boundary that client work comes first

---

## Phase 2: Infrastructure (Weeks 2-5, parallel with Phase 1)

Bootstrap architecture (Option A): Entra App Proxy on the default `msappproxy.net` domain → connector → container ports. No reverse proxy or internal DNS yet. Full detail in [[Server Setup Guide]] and [[Publishing Guide]].

### Vibe Coding Server — Foundation
- [x] Confirm Entra P2 / App Proxy licensing (confirmed 2026-06-02)
- [ ] Provision Azure VM (`Standard_D4s_v5`, Ubuntu 24.04 LTS) — no public IP
- [ ] Provision small Windows connector VM (same VNet)
- [ ] Install Docker + Docker Compose; create the `vibe` network
- [ ] Install + register the Entra private network connector
- [ ] Open app port range (3001–3099) from the connector to the VM only
- [ ] Deploy a hello-world container on a port; publish via App Proxy; validate external SSO login

### Vibe Coding Server — Database & Templates
- [ ] Stand up shared PostgreSQL 16 container (one DB + role per app)
- [ ] Create app template repo (Dockerfile, port-mapped compose, optional oauth2-proxy sidecar, DB connection)
- [ ] Document the App Contract (host port, relative URLs, healthcheck, optional identity headers)
- [ ] Start the port registry (app → port → publication)
- [ ] Backup automation (pg_dumpall to Azure Blob Storage)

### Vibe Coding Server — CI/CD & Publishing
- [ ] GitHub Actions pipeline (build, Trivy scan, lint/tests, push to GHCR, SSH deploy)
- [ ] Define the developer workflow: push to GitHub → auto-deploy → admin publishes via App Proxy
- [ ] Define the sponsored workflow: request → assignment → build → publish → feedback
- [ ] Define the per-app publication checklist + who holds the Entra admin role

### Centralized Repos & Identity
- [ ] Set up GitHub org structure (`cargas-internal/`)
- [ ] Repo naming conventions and standards
- [ ] README template with project context (incl. assigned port)
- [ ] One shared oauth2-proxy Entra app registration (add a redirect URI per identity app)
- [ ] Documentation standards (lightweight — don't over-process)

### Defer to Graduation (custom domain)
- Wildcard publishing / zero-touch deploys, Traefik routing, internal DNS, clean `*.apps.cargas.com` URLs, and shared cross-app SSO — see [[Server Setup Guide#Graduation Graduating to a Custom Domain]]

---

## Phase 3: Pilot Projects (Weeks 4-8)

### Select 2-3 Pilots
Criteria for good pilot projects:
- Clear, measurable time savings (Fred's 30-90 minute threshold)
- Non-technical requester who can validate the outcome
- Completable in 1-2 sprints by a single developer
- Demonstrates the full loop: request -> build -> deploy -> use

### Candidate Pilots
- [ ] NoCo go-live tracker (Fred/Jaiya example — Zendesk + JIRA merge dashboard)
- [ ] Evaluate existing projects for migration: EnergyScripts, ai.cargas.com tools, Power Automate flows
- [ ] Pull 1-2 from Enterprise Enablement's existing Asana list
- [ ] Marvin's Power Automate new customer flow — formalize and make visible

### Execute Pilots
- [ ] Assign developers (voluntary, passion-driven — core principle)
- [ ] Build and deploy on vibe coding server
- [ ] Get requester feedback and iterate
- [ ] Document time savings and impact (ROI evidence for scaling)

---

## Phase 4: Socialization & Scale (Weeks 8-12)

### Make It Visible
- [ ] App Hub — a published landing page listing all deployed tools and their links
- [ ] Kim's "AI & Automation Marketplace" vision = the app hub
- [ ] Kim's "Job Board" vision = the project pipeline board
- [ ] Present pilot results at Employee Meeting or Tech Connect

### Expand Participation
- [ ] Open project pipeline to company-wide submissions (Enterprise Enablement intake form)
- [ ] Recruit developers beyond initial pilots
- [ ] Establish regular cadence: monthly showcase of completed projects
- [ ] Connect to hackathon/innovation day concepts for bigger ideas

### Governance Maturity
- [ ] Review time allocation model based on pilot data
- [ ] Define app decommissioning process
- [ ] Security review requirements for deployed apps
- [ ] Fabric integration for apps that need analytics/reporting

---

## Key People

| Person | Role | Why |
|--------|------|-----|
| **Scott Dienner** | Initiative lead | Vision, engineering leadership, vibe server architecture |
| **Kim Ireland** | Enterprise Enablement lead | Demand pipeline, Biz Ops socialization, idea intake |
| **Fred Bowers** | Executive sponsor | Sees the opportunity, wants this to happen, has influence |
| **Jonathan B** | Developer contributor | AI-savvy, early adopter potential |
| **Marvin** | Existing contributor | Power Automate work already demonstrates the model |

---

## Success Metrics

### Phase 1 (Alignment)
- Steering committee formed with first meeting held
- Shared project board agreed with Enterprise Enablement

### Phase 3 (Pilots)
- 2-3 tools deployed on vibe coding server
- At least one non-technical requester actively using a tool
- Measurable time savings documented

### Phase 4 (Scale)
- 5+ developers have contributed to at least one project
- 10+ tools deployed on `cargas.internal`
- Enterprise Enablement intake generates steady pipeline of requests

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Competes with billable work | Manager-approved dedicated time model; clear client-first boundary |
| Builds demand faster than capacity | Phase 4 after pilots prove the model; don't over-promise before steering committee is running |
| Overlaps with Enterprise Enablement | Align early (Phase 1); complementary not competitive |
| Tools get built and abandoned | Centralized repos, documentation standards, app contract, decommissioning process |
| Security concerns with internal apps | Trivy scanning in CI/CD, Entra ID SSO, security review gate for sensitive data apps |

---

## Related

- [[Code Collective]] — Original presentation notes and initiative overview
- [[2. Yearly Goals#Engineering Delivery]] — Goal alignment
- [[AI Automation/CLAUDE]] — Related AI tooling work

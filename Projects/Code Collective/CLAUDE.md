# Project: Code Collective

## Overview
A company-wide initiative to formalize collaboration among Cargas engineers and technical staff on internal projects — harnessing existing talent to solve real company problems without distracting from client priorities.

## Status
- **Phase:** Planning → Alignment
- **Progress:** 15%
- **Started:** 2025-05-15
- **Target:** Q4 2026 (pilot projects running)

## Goals
- Steering committee formed with cross-functional representation
- 2-3 pilot projects identified and actively running
- Resource framework defined: time allocation model, repo structure, doc standards
- Idea-to-implementation pipeline connecting non-technical staff with technical contributors

## Current Focus
- Align with Kim Ireland's Enterprise Enablement initiative — meeting scheduled next week
- Position Code Collective as the execution arm of Enterprise Enablement
- Vibe coding server setup (infrastructure for deployed tools)
- Identify pilot project candidates from Enterprise Enablement's Asana list + existing work

## Key Decisions
| Date | Decision | Context |
|------|----------|---------|
| 2025-05-15 | Presented initiative to leadership | Slidev presentation at `d:/repos/cargascodecollective` |
| 2025-05-15 | Manager-approved dedicated time model | Prevents deprioritization vs. client work |
| 2026-05-18 | Align with Enterprise Enablement | Fred's thread + Kim's response revealed perfect fit: EE = demand pipeline, CC = execution framework, Vibe Server = deployment platform |
| 2026-06-02 | Vibe server uses Entra App Proxy for external access | Entra **P2 confirmed**. No VPN, no public IP on VM. APIs/MCP need separate path (APIM/App Gateway) — see [[Server Setup Guide#Scope APIs & MCP Servers]] |
| 2026-06-02 | Start on App Proxy **default `msappproxy.net` domain** (bootstrap) | Fastest start: no custom domain/cert/DNS. Trade-off: per-app publication, ugly URLs. Custom domain `*.apps.cargas.com` is the documented graduation path for wildcard/zero-touch + clean SSO — see [[Server Setup Guide#Graduation Graduating to a Custom Domain]] |
| 2026-06-02 | Bootstrap routing = **direct container ports (Option A)** | No Traefik, no internal DNS. App Proxy publication per app → `http://<vm-ip>:<port>`. Pre-auth-only apps hit the container directly; identity apps use a per-app oauth2-proxy sidecar (reverse-proxy mode). Manual port registry. Reverse proxy + DNS return at custom-domain graduation. |

## Next Actions
- [ ] Reply to Fred's Teams thread — connect Code Collective to his ask
- [ ] Meet with Kim Ireland — align Enterprise Enablement + Code Collective
- [ ] Agree on shared project board with Kim (her Asana list or unified system)
- [ ] Form steering committee (Kim as Biz Ops liaison, Fred as exec champion)
- [ ] Begin vibe coding server Phase 1 (Azure VM + Windows connector VM, Entra App Proxy, container ports)
- [ ] Select 2-3 pilot projects from Enterprise Enablement list
- [ ] Create resource framework (time allocation, repo structure, doc standards)

## Blockers
- Kim alignment meeting needs to happen before formalizing shared pipeline
- Vibe server infrastructure needed before pilots can deploy

## Resources
- **Presentation:** `d:/repos/cargascodecollective` (Slidev)
- **Setup Outline:** [[Setup Outline]] — Full phased setup plan
- **Vibe Server Design:** `C:\Users\sdienner\Downloads\vibe-coding-server-complete-export.md`
- **Enterprise Enablement Intake:** Asana form (managed by Kim Ireland / Biz Ops)
- **Supports:** [[2. Yearly Goals#Engineering Delivery]]
- **Related:** [[AI Automation/CLAUDE]]

## Key People
- **Kim Ireland** — Enterprise Enablement lead, Biz Ops. Building demand pipeline. Wants to understand how CC fits.
- **Fred Bowers** — Executive sponsor energy. Sees the opportunity, openly asking for this system. His NoCo/Jaiya example is the perfect proof point.
- **Jonathan B** — AI-savvy developer, potential early contributor
- **Marvin** — Power Automate work already demonstrates the CC model informally

## Notes for Claude
This is Scott's primary strategic initiative — the Code Collective is the vehicle for expanding his scope beyond direct team management. The key insight from 2026-05-18: Code Collective is the execution arm of Enterprise Enablement. Three-layer model: Enterprise Enablement (demand) + Code Collective (people/governance) + Vibe Coding Server (platform). Kim Ireland is meeting Scott next week to discuss how they connect. Fred's Teams thread is the catalyst — respond there to plant the flag.

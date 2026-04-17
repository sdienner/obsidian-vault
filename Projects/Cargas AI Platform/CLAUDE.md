# Project: Cargas AI Platform

## Overview
Consolidate 5 fragmented AI repos into a single all-TypeScript platform built on Mastra. Eliminates the Python/JS split, unifies auth/logging/tooling, and creates a single deployable service with MCP, REST, and web interfaces.

## Status
- **Phase:** Planning
- **Progress:** 5%
- **Started:** 2026-04-17
- **Target:** TBD (phased — see below)

## Goal Link
Supports: [[2. Yearly Goals#Engineering Delivery]] (Advance AI Automation initiatives)
Related: [[Projects/AI Automation/CLAUDE]]

---

## Repos Being Consolidated

| Repo | Stack | What It Does | Fate |
|------|-------|--------------|------|
| **EnergyAgent** | Python, Agno, FastAPI | Multi-agent AI orchestration (5 agents, 2 teams) with Jira, Zendesk, GitHub, ChromaDB | 🔴 Rewrite → Mastra TypeScript |
| **EnergyMCP** (energymcp-server) | TypeScript, FastMCP, Express | MCP server exposing Zendesk, Jira, Confluence tools | 🟡 Absorb into unified platform |
| **CargasAI-API** (cargasai-api) | JavaScript, Azure Functions | 33 serverless functions: KB search, ticket similarity, API keys, usage logging | 🟡 Absorb into unified platform |
| **JiraSearchWeb** | React + Vite | Frontend: MCP tool browser, API key management | 🟡 Merge into unified web UI |
| **zendesk-cargas-ai** | TypeScript, Remix + ZAF | Zendesk sidebar plugin: AI ticket analysis, KB answers | 🟢 Keep as thin client, gut AI logic |
| **EnergyLicenses** | TypeScript, Remix, Prisma | Customer Hub | 🟢 Keep separate, expose data API |

---

## Target Architecture

Single Node.js service — Mastra + Express — with four internal layers:

1. **Mastra Agent Layer** — 5 agents (Jira, Zendesk KB, Zendesk Support, Codebase, Codebase No Search) + 2 teams (Energy Support, Support)
2. **Shared Tool Layer** — Mastra `createTool` + Zod wrappers for Zendesk, Jira, Confluence, GitHub, Codebase, Customer data
3. **Service Client Layer** (`@cargas/integrations`) — typed clients for each external service
4. **API / Protocol Layer** — `/mcp` (MCP Streamable HTTP), `/api/agents`, `/api/keys`, `/api/roles`, `/api/prompts`, `/api/usage`, `/api/jira`, `/api/zendesk`, `/api/customers`

Cross-cutting: API key auth middleware, unified usage logging (replaces 5 separate log functions), OpenTelemetry → Langfuse tracing.

**Monorepo structure:** `cargas-ai-platform/` with packages: `integrations`, `agents`, `api`, `web`, `zendesk-plugin`. Turborepo.

---

## Phased Implementation Plan

### Phase 1: Foundation — Shared Service Layer (Weeks 1–3)
Build `@cargas/integrations` — all service clients in TypeScript. Foundation everything else builds on.

- [ ] Zendesk Service (lift from energymcp-server — already TS)
- [ ] Jira Service (lift from energymcp-server — already TS)
- [ ] Jira Semantic Search (port Python SQL + embedding logic → TS, uses SQL Server cosine similarity + OpenAI embeddings)
- [ ] Confluence Service (lift from energymcp-server)
- [ ] GitHub Service (port PyGithub → Octokit)
- [ ] Codebase Vector Search (replace ChromaDB → Mastra RAG or pgvector; re-index codebase)
- [ ] Customer Service (new — read-only Prisma client against CustomerMgmt DB from energylicenses)
- [ ] Response Flatteners (lift from energymcp-server, split per domain)

### Phase 2: Agent Layer (Weeks 3–5)
Build Mastra agents and teams using `@cargas/integrations` tools.

- [ ] Port all Mastra tool wrappers (Zendesk, Jira, Confluence, GitHub, Codebase, Customer, Reasoning)
- [ ] Port 5 agent definitions with instructions from Python
- [ ] Port 2 team definitions (Energy Support Team, Support Team)
- [ ] Register all agents/teams in Mastra instance

### Phase 3: API + MCP Server (Weeks 5–7)
Unified Express server replacing Azure Functions and energymcp-server.

- [ ] Port 33 Azure Functions → Express routes + Mastra agent endpoints
- [ ] Port energymcp-server MCP tools → `/mcp` Streamable HTTP
- [ ] Unified API key auth middleware
- [ ] Unified usage logging middleware (replace 5 separate log functions)
- [ ] OpenTelemetry → Langfuse tracing

### Phase 4: Web UI + Zendesk Plugin (Weeks 7–9)
Unified frontend and thin Zendesk client.

- [ ] Migrate JiraSearchWeb into unified web package (React + Vite)
- [ ] Add agent chat, KB search, API key management, usage dashboards
- [ ] Gut zendesk-cargas-ai AI logic — replace with calls to unified API

---

## Key Decisions
| Date | Decision | Context |
|------|----------|---------|
| 2026-04-17 | All-TypeScript with Mastra | Eliminates Python/JS split; Mastra provides agent/team orchestration, tool framework, and Studio dev UI |
| 2026-04-17 | Monorepo with Turborepo | Shared types and clients across packages; single deploy target for API + agents |
| 2026-04-17 | Replace ChromaDB with Mastra RAG or pgvector | ChromaDB is a standalone dependency; moving to pgvector consolidates into existing Azure SQL infrastructure |
| 2026-04-17 | zendesk-cargas-ai stays thin, keeps own deploy | ZAF (Zendesk App Framework) requires its own manifest/deploy; gutting AI logic is sufficient |

---

## Next Actions
- [ ] Identify owner(s) — who on the team drives this? Jonathan B is a candidate (AI-savvy)
- [ ] Scope Phase 1 into Jira and assign
- [ ] Stand up monorepo scaffold (`cargas-ai-platform/`, Turborepo, workspace packages)
- [ ] Start with `@cargas/integrations` — lowest risk, highest leverage

## Blockers
- No owner assigned yet
- ChromaDB → pgvector migration requires re-indexing codebase (non-trivial)
- Phase 3 Azure Functions migration needs API compatibility review before cutting over

## Resources
- **Source repos:** `D:/repos/EnergyAgent`, `D:/repos/EnergyMCP`, `D:/repos/CargasAI-API`, `D:/repos/JiraSearchWeb`, `D:/repos/zendesk-cargas-ai`, `D:/repos/EnergyLicenses`
- **Supports:** [[2. Yearly Goals#Engineering Delivery]]
- **Related:** [[Projects/AI Automation/CLAUDE]]

## Notes
The `@cargas/integrations` service client layer is the critical foundation — everything else depends on it. TypeScript services from energymcp-server (Zendesk, Jira, Confluence) are nearly lift-and-shift. The Python ports (GitHub, Jira semantic search, ChromaDB) are the highest-effort pieces in Phase 1.

Jonathan B is a strong candidate to lead this — AI-savvy, familiar with the existing tools, and this aligns with developing him for expanded scope.

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
| **EnergyAgent** | Python, Agno, FastAPI | Multi-agent AI orchestration (5 agents + 3 workflow-only, 2 teams) — Jira, Zendesk, GitHub, ChromaDB | 🔴 Rewrite → Mastra TypeScript |
| **EnergyMCP** | TypeScript, FastMCP | 18 MCP tools — Zendesk, Jira, Confluence, Customer data; 4 Prisma schemas | 🟡 Absorb into unified platform |
| **CargasAI-API** | JavaScript, Azure Functions | 34 serverless functions — KB search, ticket similarity, API keys, usage logging | 🟡 Absorb into unified platform |
| **JiraSearchWeb** | React + Vite | Frontend: agent chat, Jira search, KB search, API key mgmt — partially migrated already | 🟡 Merge into unified web UI |
| **zendesk-cargas-ai** | TypeScript, Remix + ZAF | Zendesk sidebar plugin; AI logic is 6 files in `ai-calls/` | 🟢 Keep thin, gut `ai-calls/` |
| **EnergyLicenses** | TypeScript, Remix, Prisma | Customer Hub — keep separate, expose data via read-only API | 🟢 Keep separate |

---

## What's Already Done (Ahead of Schedule)

**JiraSearchWeb is partially migrated.** The `/agno-chat` page already calls the unified Agno platform via `VITE_AGNO_API_URL`. `agnoConfig.js` already defines all 4 agents and the `energy_support_team` team with their route IDs. Phase 4 web migration = swap ~3 API call sites (`handleAPI.js`, `KBQuestions.jsx`) — not a structural rewrite.

---

## Agent + Tool Inventory (EnergyAgent)

### Agents
| Agent | Tools |
|-------|-------|
| Codebase Agent | GithubTools, search_codebase (ChromaDB), get_commit/s/range, ReasoningTools |
| Codebase Agent (No Search) | GithubTools, get_commit/s/range |
| Jira Agent | search_similar_issues, get_jira_issue_info/comments/history, search_jira_issues_jql/minimal |
| Zendesk KB Agent | zendesk_kb_search, zendesk_kb_read |
| Zendesk Support Agent | read_ticket |
| *(workflow-only)* | search planner, per-ticket summarizer, results synthesizer (inside Zendesk Ticket Analysis Workflow) |

### Teams
| Team | Members |
|------|---------|
| Energy Support Team | Codebase (No Search) + Jira + Zendesk KB + Zendesk Support |
| Support Team | Zendesk Support + Jira + Zendesk KB |

### LLMs in Use
GPT-4.1, GPT-5, GPT-5-mini (OpenAI) — Gemini 2.5 Flash, Kimi K2 (via OpenRouter)

---

## MCP Tool Inventory (EnergyMCP — 18 tools)

Zendesk: `get-ticket`, `get-ticket-comments`, `search-tickets`, `search-articles-all`, `search-articles-internal` (hardcoded brand ID), `get-article`, `get-article-by-url`

Jira: `get-issue`, `search-jql`, `get-fields`, `list-transitions`, `semantic-search` (embeddings in AI Prisma DB)

Confluence: `search-pages`, `get-page`, `get-page-by-title`

Customer: `get-by-id`, `get-by-name`, `correlate-zendesk`, `get-data` (deployments, customizations, feature flags, CargasPay views)

**Flatten layer** (`flatten.ts`) — normalizes Zendesk tickets/comments/articles and Jira issues for token efficiency. Comprehensive, modular, genuinely lift-and-shift.

---

## Azure Functions Inventory (CargasAI-API — 34 total)

**AI / Core (6 — complex, ~80% of migration risk)**
- `answerKBQuestion` — 2-stage LLM chain: keyword gen → KB search → GPT answer
- `getTicketSummary` — parallel Zendesk fetch + GPT-4o-mini formatting
- `findSimilarTickets` — multi-hop Zendesk search + parallel LLM expansion
- `searchSimilarJiraIssues` — raw Azure SQL `VECTOR_DISTANCE` cosine math (⚠️ Azure SQL-specific, not portable ORM)
- `summarizeGPSThread` — GPT-5 thread summarization
- `getMcpTools` — MCP session bootstrap + dual content-type parsing

**API Keys (2):** `createApiKey`, `getApiKeyUsage` — Prisma CRUD + crypto

**Roles (5):** `addRole`, `getAllRoles`, `assignUserRole`, `getUserRoles`, `getRoleAssignments` — pure Prisma CRUD

**Prompts (3):** `createPrompt`, `savePrompt`, `getAllPrompts` — Prisma + tags many-to-many

**Usage Logging (5):** Writes to 2–3 Azure Table Storage tables per event (by-month + by-user + by-runID). No transactions — partial-write risk at migration.

**Usage Reporting (9):** Reads from Table Storage by partition key. Identical pattern, different table names.

**Jira Helpers (4):** `getAllProjects`, `getAllIssueTypesAndProjects` (raw SQL against zd-client DB), `getJiraJqlAutocompleteData`, `getJiraJqlSuggestions` (thin Jira REST proxies)

**⚠️ Security gap:** All 34 functions have `authLevel: "anonymous"` at the Azure Functions host. No incoming request auth is enforced. The new platform must add API key middleware.

---

## Target Architecture

Single Node.js service — Mastra + Express:

1. **Mastra Agent Layer** — 5 agents + 2 teams (definitions above)
2. **Shared Tool Layer** — Mastra `createTool` + Zod wrappers
3. **Service Client Layer** (`@cargas/integrations`) — typed clients per service
4. **API / Protocol Layer** — `/mcp`, `/api/agents`, `/api/keys`, `/api/roles`, `/api/prompts`, `/api/usage`, `/api/jira`, `/api/zendesk`, `/api/customers`

Cross-cutting: API key auth middleware (fixes current anon gap), unified usage logging, OpenTelemetry → Langfuse.

**Monorepo:** `D:/repos/cargas-ai-platform/` — packages: `integrations`, `agents`, `api`, `web`, `zendesk-plugin`. Turborepo. Created from scratch.

---

## Phased Implementation Plan

### Phase 1: Foundation — `@cargas/integrations` (Weeks 1–3)

| Task | Source | Effort |
|------|--------|--------|
| Zendesk Service | EnergyMCP `services/zendesk.ts` | 🟢 Lift |
| Jira Service | EnergyMCP `services/jira.ts` | 🟢 Lift |
| Confluence Service | EnergyMCP `services/confluence.ts` | 🟢 Lift |
| Response Flatteners | EnergyMCP `services/flatten.ts` | 🟢 Lift |
| Customer Service | EnergyMCP `services/customer.ts` (4 Prisma schemas) | 🟡 Re-point Prisma |
| GitHub Service | EnergyAgent `utils/github_commit_tools.py` | 🟡 Port PyGithub → Octokit |
| Jira Semantic Search | EnergyAgent `utils/jira_client.py` + `vector_search_client.py` | 🟡 Port SQL+embedding logic; embeddings live in AI Prisma DB |
| Codebase Vector Search | EnergyAgent `utils/chroma_search_client.py` + CargasCodeIndexer | 🔴 Replace ChromaDB → pgvector; re-index from `D:/repos/CargasCodeIndexer` |

### Phase 2: Agent Layer (Weeks 3–5)
- [ ] Port all tool wrappers to Mastra `createTool` + Zod (18 tools from EnergyMCP + GitHub/Codebase from EnergyAgent)
- [ ] Port 5 agent definitions + instructions (copy system prompts from Python)
- [ ] Port 2 team definitions
- [ ] ⚠️ Map Agno `Workflow` with typed `Step`/`StepInput`/`StepOutput` → Mastra workflow primitives (highest complexity)
- [ ] Register in Mastra instance

### Phase 3: API + MCP Server (Weeks 5–7)
- [ ] Port 34 Azure Functions → Express routes (18 trivial/moderate first, then 6 complex AI chains)
- [ ] Migrate Azure Table Storage usage logs → Azure SQL (consolidate with main DB)
- [ ] Port EnergyMCP 18 tools → `/mcp` Streamable HTTP endpoint
- [ ] Add API key auth middleware (fix anonymous gap)
- [ ] Unified usage logging middleware (replace 5 separate log functions)
- [ ] OpenTelemetry → Langfuse (Langfuse has official Node.js SDK; port from Python)
- [ ] Replicate Azure SQL `VECTOR_DISTANCE` Jira similarity in Node (`mssql`/`tedious` driver)

### Phase 4: Web UI + Zendesk Plugin (Weeks 7–9)
- [ ] Migrate JiraSearchWeb structure into unified `web/` package
- [ ] Swap ~3 legacy API call sites → unified platform (`handleAPI.js`, `KBQuestions.jsx`)
- [ ] Decommission old `/jira-search` route
- [ ] Gut `zendesk-cargas-ai/ai-calls/` (6 files) → thin `fetch()` calls to unified platform
- [ ] Decide: move Azure Table Storage caching to platform, or drop it

---

## Key Decisions
| Date | Decision | Context |
|------|----------|---------|
| 2026-04-17 | All-TypeScript with Mastra | Eliminates Python/JS split; Mastra provides agent/team/workflow orchestration and Studio dev UI |
| 2026-04-17 | Monorepo with Turborepo | Shared types across packages; single deploy target |
| 2026-04-17 | Replace ChromaDB with pgvector | ChromaDB is standalone; pgvector consolidates into existing Azure SQL infrastructure |
| 2026-04-17 | zendesk-cargas-ai keeps ZAF deploy, guts AI logic | ZAF requires its own manifest; only `ai-calls/` needs replacing |
| 2026-04-17 | Fix anonymous auth gap in new platform | All 34 CargasAI-API functions currently have no request auth; new platform enforces API key middleware |
| 2026-04-17 | Migrate Table Storage usage logs → Azure SQL | Consolidates storage; eliminates partial-write risk from current multi-table write pattern |

---

## Next Actions
- [ ] Identify owner — Jonathan B is the strongest candidate (AI-savvy, aligns with expanding his scope)
- [ ] Scaffold monorepo at `D:/repos/cargas-ai-platform/` (Turborepo + 5 workspace packages)
- [ ] Scope Phase 1 into Jira and assign
- [ ] Start with lift-and-shift services (Zendesk, Jira, Confluence, Flatteners) — lowest risk, immediate value

## Blockers
- No owner assigned
- ChromaDB → pgvector requires re-indexing from `D:/repos/CargasCodeIndexer` — non-trivial, confirm approach before Phase 1 ends
- Agno Workflow → Mastra workflow mapping needs a spike before Phase 2 commit
- `VECTOR_DISTANCE` Jira similarity uses Azure SQL-specific SQL — needs Node `mssql`/`tedious` driver, not generic ORM

## Resources
- **Source repos:** `D:/repos/EnergyAgent`, `D:/repos/EnergyMCP`, `D:/repos/CargasAI-API`, `D:/repos/JiraSearchWeb`, `D:/repos/zendesk-cargas-ai`, `D:/repos/EnergyLicenses`, `D:/repos/CargasCodeIndexer`
- **Target repo:** `D:/repos/cargas-ai-platform/` (to be created)
- **Supports:** [[2. Yearly Goals#Engineering Delivery]]
- **Related:** [[Projects/AI Automation/CLAUDE]]

## Notes
**JiraSearchWeb is further along than expected** — agno-chat is live and calling the platform, all agent/team IDs are already defined in `agnoConfig.js`. Phase 4 is closer to a cleanup than a migration.

**Biggest technical risks:** (1) Agno Workflow → Mastra mapping — do a spike before committing to Phase 2 timeline. (2) ChromaDB re-indexing — `CargasCodeIndexer` is the source but the indexing pipeline will need to change. (3) `VECTOR_DISTANCE` SQL is Azure SQL-specific — can't use Prisma for this, needs raw `mssql` query.

**Jonathan B** is the natural owner — AI-savvy, familiar with the tools, and leading this fits the goal of developing him for expanded scope.

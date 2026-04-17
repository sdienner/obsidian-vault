Now I have a complete picture of every tool, agent, function, and service across all repos. Here's the fully revised consolidation plan built around an all-TypeScript Mastra architecture:

---

# Cargas AI Platform — Unified Consolidation Plan (Revised)

## All-TypeScript Architecture with Mastra

---

## 1. Current State Inventory

### Repos Being Consolidated

| Repo | Stack | What It Does | Fate |
|---|---|---|---|
| **EnergyAgent** | 🐍 Python, Agno, FastAPI | Multi-agent AI orchestration (5 agents, 2 teams) with Jira, Zendesk, GitHub, ChromaDB tools | 🔴 **Rewrite → Mastra TypeScript** |
| **energymcp-server** | 📘 TypeScript, FastMCP, Express | MCP server exposing Zendesk, Jira, Confluence tools | 🟡 **Absorb into unified platform** |
| **cargasai-api** | 📘 JavaScript, Azure Functions | 33 serverless functions: KB search, ticket similarity, API keys, usage logging, role management | 🟡 **Absorb into unified platform** |
| **JiraSearchWeb** | 📘 React + Vite | Frontend: MCP tool browser, API key management | 🟡 **Merge into unified web UI** |
| **zendesk-cargas-ai** | 📘 TypeScript, Remix + ZAF | Zendesk sidebar plugin: AI ticket analysis, KB answers, conversation analysis | 🟢 **Keep as thin client, gut AI logic** |
| **energylicenses** | 📘 TypeScript, Remix, Prisma | Customer Hub: customer management, releases, phone-home, cron jobs | 🟢 **Keep separate, expose data API** |

### Complete Tool/Function Inventory (What Must Be Ported)

**EnergyAgent Python tools → Mastra TypeScript tools:**

| Python Tool | File | What It Does |
|---|---|---|
| `search_similar_issues_with_text` | `utils/jira_client.py` | Vector similarity search on Jira issues via SQL Server embeddings |
| `search_similar_issues_with_issue_key` | `utils/jira_client.py` | Find issues similar to a given Jira key |
| `get_jira_issue_info` | `utils/jira_client.py` | Full issue detail via Jira REST API |
| `get_jira_issue_comments` | `utils/jira_client.py` | Comments with pagination |
| `get_jira_issue_history` | `utils/jira_client.py` | Changelog/field history |
| `search_jira_issues_jql` | `utils/jira_client.py` | Full JQL search with validation |
| `search_jira_issues_minimal` | `utils/jira_client.py` | Token-efficient JQL search |
| `read_ticket` | `utils/zendesk_client.py` | Full Zendesk ticket with comments, custom fields |
| `zendesk_kb_search` | `utils/zendesk_kb_client.py` | KB article search with multibrand support |
| `zendesk_kb_read` | `utils/zendesk_kb_client.py` | Read specific KB article |
| `search_codebase` | `utils/chroma_search_client.py` | Semantic code search via ChromaDB embeddings |
| `get_commit` | `utils/github_commit_tools.py` | Single commit details with diffs |
| `get_commits` | `utils/github_commit_tools.py` | Filtered commit history |
| `get_commit_range` | `utils/github_commit_tools.py` | Compare two branches/commits |
| `GithubTools` | Agno built-in | Browse repos, read files, search code |
| `ReasoningTools` | Agno built-in | Structured chain-of-thought |

**energymcp-server tools (already TypeScript — lift and shift):**

| Tool | What It Does |
|---|---|
| `get-ticket` | Get Zendesk ticket |
| `get-ticket-comments` | Get ticket comments |
| `search-tickets` | Search Zendesk tickets |
| `search-articles` / `search-articles-multibrand` / `search-articles-internal` | KB article search (3 variants) |
| `get-article` / `get-article-by-url` | Read KB article |
| `jira-create-issue` | Create Jira issue |
| `jira-get-issue` | Get Jira issue |
| `jira-search-jql` | JQL search (new v3 endpoint) |
| `jira-list-transitions` / `jira-transition-issue` | Jira workflow transitions |
| `jira-semantic-search` | Semantic similarity search |
| `confluence-search-pages` | CQL search |
| `confluence-get-page` / `confluence-get-page-by-title` | Read Confluence pages |
| Response flatteners (`flatten.ts`) | Token-efficient output formatting |

**cargasai-api Azure Functions (33 total):**

| Category | Functions | Fate |
|---|---|---|
| **AI Core** | `answerKBQuestion`, `getTicketSummary`, `findSimilarTickets`, `summarizeGPSThread`, `searchSimilarJiraIssues`, `zendeskKBSearch` | → Mastra tools/agents |
| **API Key Mgmt** | `createApiKey`, `getApiKeyUsage`, `getMcpTools` | → Unified API routes |
| **Role Mgmt** | `addRole`, `assignUserRole`, `getAllRoles`, `getRoleAssignments`, `getUserRoles` | → Unified API routes |
| **Prompt Mgmt** | `createPrompt`, `getAllPrompts`, `savePrompt` | → Unified API routes |
| **Usage Logging** | `logJiraSearchUsage`, `logKBChatUsage`, `logKBSearchUsage`, `logSimilarTicketSearch`, `logTicketSummaryQuery` | → Unified logging middleware |
| **Usage Reporting** | `getJiraSearchUsageByMonth`, `getJiraSearchUsageForUser`, `getKBQuestionHistoryByMonth`, `getKBQuestionHistoryForUser`, `getKBSearchUsageByMonth`, `getKBSearchUsageForUser`, `getSimilarTicketsUsageForUser`, `getSummaryHistoryByMonth`, `getSummaryHistoryForUser` | → Unified API routes |
| **Jira Helpers** | `getAllProjects`, `getAllIssueTypesAndProjects`, `getJiraJqlAutocompleteData`, `getJiraJqlSuggestions` | → Unified API routes |

---

## 2. Target Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                        FRONTEND LAYER                              │
│                                                                    │
│  ┌───────────────┐  ┌───────────────────┐  ┌───────────────────┐  │
│  │ Unified Web   │  │ Zendesk Plugin    │  │ IDE / Copilot     │  │
│  │ (React+Vite)  │  │ (Remix + ZAF)     │  │ (MCP Clients)     │  │
│  │               │  │ Thin UI only —    │  │ VS Code, Cursor,  │  │
│  │ • Agent chat  │  │ calls unified API │  │ etc.              │  │
│  │ • Jira search │  │ for all AI work   │  │                   │  │
│  │ • KB search   │  │                   │  │                   │  │
│  │ • API keys    │  │                   │  │                   │  │
│  │ • Dashboards  │  │                   │  │                   │  │
│  └───────┬───────┘  └────────┬──────────┘  └────────┬──────────┘  │
└──────────┼───────────────────┼───────────────────────┼─────────────┘
           │ REST              │ REST                   │ MCP
           ▼                   ▼                        ▼
┌────────────────────────────────────────────────────────────────────┐
│              UNIFIED CARGAS AI PLATFORM (TypeScript)                │
│              Single Node.js service — Mastra + Express             │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    MASTRA AGENT LAYER                         │  │
│  │                                                              │  │
│  │  Agents:                        Teams:                       │  │
│  │  • Codebase Agent               • Energy Support Team        │  │
│  │  • Codebase Agent (No Search)     (all 4 agents)             │  │
│  │  • Jira Agent                   • Support Team               │  │
│  │  • Zendesk KB Agent               (Jira + ZD KB + ZD Tix)   │  │
│  │  • Zendesk Support Agent                                     │  │
│  │                                                              │  │
│  │  Each agent: model config + instructions + typed tools       │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                   SHARED TOOL LAYER                           │  │
│  │                   (Mastra createTool + Zod)                   │  │
│  │                                                              │  │
│  │  Zendesk:              Jira:              Confluence:         │  │
│  │  • searchArticles      • searchJQL        • searchPages      │  │
│  │  • searchMultibrand    • searchMinimal    • getPage           │  │
│  │  • searchInternal      • semanticSearch   • getPageByTitle    │  │
│  │  • getArticle          • getIssue                             │  │
│  │  • getArticleByUrl     • getComments      GitHub/Code:        │  │
│  │  • getTicket           • getHistory       • searchCodebase    │  │
│  │  • getTicketComments   • createIssue      • getCommit(s)      │  │
│  │  • searchTickets       • transition       • getCommitRange    │  │
│  │  • readTicket          • listTransitions  • browseRepo        │  │
│  │                                           • readFile          │  │
│  │  Customer Data:        Utility:                               │  │
│  │  • getCustomer         • reasoning (chain-of-thought)         │  │
│  │  • searchCustomers     • Response flatteners (from MCP)       │  │
│  │  • getDeployments                                             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                   SERVICE CLIENT LAYER                        │  │
│  │                   (@cargas/integrations)                       │  │
│  │                                                              │  │
│  │  • ZendeskService (Zenpy → node-fetch + Zendesk REST API)   │  │
│  │  • JiraService (python-jira → node-fetch + Jira REST v3)    │  │
│  │  • ConfluenceService (lifted from energymcp-server)          │  │
│  │  • GitHubService (PyGithub → Octokit)                        │  │
│  │  • VectorSearchService (ChromaDB → Mastra RAG / pgvector)   │  │
│  │  • CustomerService (queries energylicenses DB via Prisma)    │  │
│  │  • LLMService (multi-provider: Anthropic, OpenAI, Gemini)   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                   API / PROTOCOL LAYER                        │  │
│  │                                                              │  │
│  │  /mcp           MCP Streamable HTTP (for IDEs + MCP clients) │  │
│  │  /api/agents    Mastra agent REST endpoints (chat, stream)   │  │
│  │  /api/keys      API key management (create, usage, health)   │  │
│  │  /api/roles     Role management                               │  │
│  │  /api/prompts   Prompt management                             │  │
│  │  /api/usage     Usage reporting & dashboards                  │  │
│  │  /api/jira      Jira helpers (projects, autocomplete)        │  │
│  │  /api/zendesk   Zendesk direct endpoints                     │  │
│  │  /api/customers Customer data proxy (→ energylicenses DB)    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │               AUTH + LOGGING + OBSERVABILITY                  │  │
│  │                                                              │  │
│  │  • API Key auth middleware (unified schema)                  │  │
│  │  • Usage logging middleware (replaces 5 separate log funcs)  │  │
│  │  • OpenTelemetry → Langfuse tracing                          │  │
│  │  • Mastra Studio (dev-time debugging UI)                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                      DATA / STORAGE LAYER                          │
│                                                                    │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌──────────────────┐  │
│  │ Azure SQL│  │ Vector DB│  │ Langfuse  │  │ Azure Table      │  │
│  │ (ai-db + │  │ (pgvector│  │ (Traces)  │  │ Storage          │  │
│  │  zd-db)  │  │  or Mast-│  │           │  │ (legacy usage    │  │
│  │          │  │  ra RAG) │  │           │  │  logs, migrate)  │  │
│  └──────────┘  └──────────┘  └───────────┘  └──────────────────┘  │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ energylicenses DB (read-only access from platform)           │  │
│  │ CustomerMgmt + PhoneHome — queried via Prisma                │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

---

## 3. Monorepo Structure

```
cargas-ai-platform/
├── packages/
│   ├── integrations/                    # @cargas/integrations — shared service clients
│   │   ├── src/
│   │   │   ├── zendesk/
│   │   │   │   ├── zendesk-service.ts   # Unified Zendesk client (tickets + KB)
│   │   │   │   ├── flatten.ts           # Lifted from energymcp-server
│   │   │   │   └── types.ts
│   │   │   ├── jira/
│   │   │   │   ├── jira-service.ts      # Unified Jira client (REST v3)
│   │   │   │   ├── jira-semantic.ts     # Vector similarity (port from jira_client.py)
│   │   │   │   ├── flatten.ts           # Lifted from energymcp-server
│   │   │   │   └── types.ts
│   │   │   ├── confluence/
│   │   │   │   ├── confluence-service.ts # Lifted from energymcp-server
│   │   │   │   ├── flatten.ts
│   │   │   │   └── types.ts
│   │   │   ├── github/
│   │   │   │   ├── github-service.ts    # Octokit wrapper (port from github_commit_tools.py)
│   │   │   │   └── types.ts
│   │   │   ├── codebase/
│   │   │   │   └── vector-search.ts     # Replaces ChromaDB (Mastra RAG or pgvector)
│   │   │   ├── customer/
│   │   │   │   ├── customer-service.ts  # Queries energylicenses DB
│   │   │   │   └── types.ts
│   │   │   └── index.ts
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   ├── agents/                          # Mastra agent definitions
│   │   ├── src/
│   │   │   ├── tools/                   # Mastra createTool() wrappers
│   │   │   │   ├── zendesk-tools.ts     # searchArticles, getTicket, readTicket, etc.
│   │   │   │   ├── jira-tools.ts        # searchJQL, semanticSearch, getIssue, etc.
│   │   │   │   ├── confluence-tools.ts  # searchPages, getPage, etc.
│   │   │   │   ├── github-tools.ts      # getCommit, getCommits, browseRepo, etc.
│   │   │   │   ├── codebase-tools.ts    # searchCodebase (vector search)
│   │   │   │   ├── customer-tools.ts    # getCustomer, searchCustomers
│   │   │   │   └── reasoning-tools.ts   # Chain-of-thought (replaces Agno ReasoningTools)
│   │   │   ├── agents/
│   │   │   │   ├── jira-agent.ts
│   │   │   │   ├── zendesk-kb-agent.ts
│   │   │   │   ├── zendesk-support-agent.ts
│   │   │   │   ├── codebase-agent.ts
│   │   │   │   └── codebase-agent-no-search.ts
│   │   │   ├── teams/
│   │   │   │   ├── energy-team.ts       # Orchestrator with all 4 agents
│   │   │   │   └── support-team.ts      # Jira + Zendesk only
│   │   │   ├── instructions/            # Prompt strings (copy from Python)
│   │   │   │   ├── jira-agent.ts
│   │   │   │   ├── zendesk-kb-agent.ts
│   │   │   │   ├── zendesk-support-agent.ts
│   │   │   │   ├── github-agent.ts
│   │   │   │   ├── github-agent-no-search.ts
│   │   │   │   └── energy-team.ts
│   │   │   └── mastra.ts               # Mastra instance (registers all agents/teams)
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   ├── api/                             # Unified API server
│   │   ├── src/
│   │   │   ├── routes/
│   │   │   │   ├── agents.ts            # /api/agents — Mastra agent chat endpoints
│   │   │   │   ├── keys.ts             # /api/keys — API key CRUD + usage
│   │   │   │   ├── roles.ts            # /api/roles — role management
│   │   │   │   ├── prompts.ts          # /api/prompts — prompt management
│   │   │   │   ├── usage.ts            # /api/usage — unified reporting
│   │   │   │   ├── jira.ts             # /api/jira — projects, autocomplete, suggestions
│   │   │   │   ├── zendesk.ts          # /api/zendesk — direct KB/ticket endpoints
│   │   │   │   └── customers.ts        # /api/customers — proxy to energylicenses
│   │   │   ├── mcp/
│   │   │   │   └── server.ts           # /mcp — MCP Streamable HTTP (from energymcp-server)
│   │   │   ├── middleware/
│   │   │   │   ├── auth.ts             # API key validation
│   │   │   │   ├── logging.ts          # Replaces 5 separate log* functions
│   │   │   │   └── tracing.ts          # OpenTelemetry → Langfuse
│   │   │   └── server.ts              # Express app entry point
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   ├── web/                             # Unified web UI (absorbs JiraSearchWeb)
│   │   ├── src/
│   │   │   ├── components/
│   │   │   ├── pages/
│   │   │   │   ├── chat/               # Agent chat interface
│   │   │   │   ├── jira-search/        # Jira search (from JiraSearchWeb)
│   │   │   │   ├── kb-search/          # KB search
│   │   │   │   ├── api-keys/           # API key management
│   │   │   │   └── dashboards/         # Usage dashboards
│   │   │   └── App.tsx
│   │   ├── package.json
│   │   └── vite.config.ts
│   │
│   └── zendesk-plugin/                  # Thin ZAF client (keeps its own deploy)
│       ├── packages/cargas-ai-remix/
│       │   ├── app/
│       │   │   ├── routes/
│       │   │   │   ├── $ticketid.ai-analysis.tsx     # Calls unified API
│       │   │   │   ├── $ticketid.conversation-analysis.tsx
│       │   │   │   └── $ticketid.kb-answers.tsx
│       │   │   └── utils/
│       │   │       └── api-client.ts    # Thin HTTP client to unified API
│       │   └── package.json
│       └── manifest.json
│
├── prisma/
│   ├── ai-schema.prisma                # Unified AI platform schema
│   └── generated/
│
├── docker-compose.yml                  # Local dev: API + web + vector DB
├── Dockerfile                          # Single container for API + agents
├── turbo.json                          # Turborepo config
├── package.json                        # Workspace root
└── .env.example
```

---

## 4. Phased Implementation Plan

### Phase 1: Foundation — Shared Service Layer (Weeks 1–3)

**Goal:** Create `@cargas/integrations` with all service clients in TypeScript. This is the foundation everything builds on.

| Task | Source | Target | Effort | Notes |
|---|---|---|---|---|
| **Zendesk Service** | `energymcp-server/src/services/zendesk*.ts` + `flatten.ts` | `integrations/src/zendesk/` | 🟢 Low | Already TypeScript — lift, clean, export |
| **Jira Service** | `energymcp-server/src/services/jira*.ts` + `flatten.ts` | `integrations/src/jira/` | 🟢 Low | Already TypeScript — lift, clean, export |
| **Jira Semantic Search** | `EnergyAgent/utils/jira_client.py` (vector search via SQL Server) + `EnergyAgent/utils/vector_search_client.py` | `integrations/src/jira/jira-semantic.ts` | 🟡 Med | Port Python SQL+embedding logic to TypeScript; uses SQL Server cosine similarity + OpenAI embeddings |
| **Confluence Service** | `energymcp-server/src/services/confluence*.ts` | `integrations/src/confluence/` | 🟢 Low | Lift and shift |
| **GitHub Service** | `EnergyAgent/utils/github_commit_tools.py` | `integrations/src/github/` | 🟡 Med | Port PyGithub → Octokit; 3 functions |
| **Codebase Vector Search** | `EnergyAgent/utils/chroma_search_client.py` | `integrations/src/codebase/` | 🟡 Med | Replace ChromaDB with Mastra RAG pipeline or pgvector; need to re-index codebase |
| **Customer Service** | New — queries `energylicenses` Prisma schemas | `integrations/src/customer/` | 🟡 Med | Read-only Prisma client against CustomerMgmt DB |
| **Response Flatteners** | `energymcp-server/src/services/flatten.ts` | `integrations/src/*/flatten.ts` | 🟢 Low | Already TypeScript, split per domain |

**Deliverable:** `@cargas/integrations` npm package usable by all downstream packages. Unit tests with mocks (port existing `energymcp-server`
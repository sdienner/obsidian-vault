---
date: 2026-05-18
updated: 2026-06-02
tags: [project, infrastructure, technical]
status: active
---
# Vibe Coding Server — Setup Guide

Reference guide for standing up the Code Collective deployment platform on Azure.

**Target state:** An internal Azure VM running Docker with Traefik reverse proxy, Entra ID SSO, and shared PostgreSQL. The VM has **no public IP**. External access is published through **Microsoft Entra Application Proxy**, which pre-authenticates users at Microsoft's edge and tunnels to the VM via an outbound-only connector. Developers push to GitHub; apps appear at `*.apps.cargas.com` automatically — reachable from anywhere with no VPN.

> **Scope note:** App Proxy is the exposure path for **browser-based web apps**. APIs, webhook receivers, and MCP servers are a poor fit for App Proxy (pre-auth model, connection timeouts) and need a separate path — see [Scope: APIs & MCP Servers](#scope-apis--mcp-servers) at the end. This guide covers the web-app platform.

---

## Architecture Overview

```
External user (any device, no VPN)
   │
   ▼
Entra ID  ──── pre-authentication at Microsoft's edge
   │           (only authenticated cargas.com users pass)
   ▼
Azure App Proxy service  (Microsoft cloud, DDoS/WAF, TLS edge)
   │
   │  outbound-only TLS tunnel (connector dials out — no inbound firewall rule)
   ▼
App Proxy Connector  (small Windows VM in Cargas VNet)
   │
   ▼  https://<app>.apps.cargas.com  (resolves internally to the Linux VM)
┌──────────────────────────────────────────────────────────┐
│ Linux VM (Ubuntu 24.04) — internal only, NO public IP      │
│                                                            │
│   Traefik v3  ──►  oauth2-proxy  ──►  app containers        │
│   (routing,        (issues             (read auth headers)  │
│    backend TLS)     X-Forwarded-* )                         │
│                                                            │
│   Shared PostgreSQL 16  (one DB + role per app)            │
└──────────────────────────────────────────────────────────┘
        ▲
        │  Internal / VPN users resolve *.apps.cargas.com
        │  directly to the VM (split-horizon DNS), bypassing
        └─ App Proxy. oauth2-proxy still authenticates them.
```

### Why oauth2-proxy stays (even though App Proxy pre-authenticates)

These two auth layers do **different jobs** and we keep both:

- **App Proxy pre-auth** is the *access gate* — it ensures only authenticated Cargas users from the internet ever reach the VM. It does **not** hand the app the user's identity (that would require PingAccess header-based SSO — extra cost/complexity we're avoiding).
- **oauth2-proxy** is the *identity provider for apps* — it populates the `X-Forwarded-User` / `X-Forwarded-Groups` headers that every app reads (the App Contract). It also authenticates internal/VPN users who hit the VM directly and never touch App Proxy.

**Result:** the internal stack works identically whether reached via App Proxy (external) or directly (internal/VPN). The App Contract and [[Publishing Guide]] auth model are **unchanged**.

**On the "double login":** Both layers use Entra ID, so the user signs in **once interactively** at App Proxy. When oauth2-proxy then redirects to Entra, Entra sees the existing session and returns a token silently (no second credential prompt). If this ever causes friction, App Proxy can be set to *passthrough* pre-auth and let oauth2-proxy be the sole authenticator — but you lose edge pre-auth, so prefer keeping both.

---

## 1. Azure VM Provisioning

### App VM Specification

| Setting | Value |
|---------|-------|
| **Size** | `Standard_D4s_v5` (4 vCPU, 16 GB RAM) |
| **OS** | Ubuntu 24.04 LTS |
| **OS Disk** | 64 GB Premium SSD |
| **Data Disk** | 128 GB Premium SSD (mount at `/data` for Docker volumes + Postgres) |
| **Region** | Same as existing Cargas Azure resources |
| **Network** | Corporate VNet, **no public IP** |
| **Inbound** | Allow 443 (and 80 for redirect) from the connector VM + internal/VPN subnets only. No internet inbound. |

### Companion: App Proxy Connector VM

The Entra private network connector is **Windows-only software** — it cannot run on the Ubuntu VM. Stand up a small Windows host for it (or reuse an existing Windows Server in the VNet).

| Setting | Value |
|---------|-------|
| **Size** | `Standard_B2s` / `D2s_v5` (2 vCPU, 4–8 GB) — connector is lightweight |
| **OS** | Windows Server 2022 |
| **Network** | Same VNet as the app VM; **outbound 443 to Azure**; line-of-sight to the app VM |
| **HA** | Two connectors in one connector group recommended for production; one is fine to start |

### Post-Provision Steps (App VM)

- [ ] Mount data disk at `/data`
- [ ] Set up SSH access (key-based, no password auth)
- [ ] Install Docker Engine + Docker Compose v2
- [ ] Create directory structure:

```
/data/
  traefik/
    config/      # dynamic config (TLS certs)
    certs/       # wildcard cert + key
  postgres/
    data/
    backups/
  apps/
```

### Scale Triggers
- Memory >80% sustained → upgrade app VM to `D8s_v5`
- CPU >70% sustained → evaluate workload or upgrade
- Disk >75% → expand data disk

---

## 2. Microsoft Entra Application Proxy

This is the external front door. The connector dials out to Microsoft; nothing inbound is opened on the corporate firewall.

> **Licensing:** App Proxy requires Entra ID P1 or P2. ✅ **Confirmed (2026-06-02): Cargas has Entra ID P2** — App Proxy is available, and P2 additionally unlocks risk-based Conditional Access (Identity Protection) and PIM for securing published apps.

### Setup Steps

- [ ] Install the **Entra private network connector** on the Windows connector VM (download from Entra admin center → Application Proxy)
- [ ] Confirm the connector registers and shows **Active** in the Entra admin center
- [ ] Verify Cargas domain `apps.cargas.com` (or `cargas.com`) as a **custom domain** in Entra
- [ ] Upload the wildcard TLS cert for `*.apps.cargas.com` (see [Section 3](#3-dns--certificates))
- [ ] Publish the application (wildcard — see below)

### Publish as a Wildcard Application

To preserve the "deploy and it just shows up" workflow, publish a **single wildcard app** rather than one publication per tool. Any new subdomain Traefik serves is then reachable externally with **no new App Proxy publication**.

| App Proxy setting | Value |
|-------------------|-------|
| **External URL** | `https://*.apps.cargas.com` |
| **Internal URL** | `https://*.apps.cargas.com` (same host — resolved internally to the VM) |
| **Pre-authentication** | Microsoft Entra ID |
| **Connector group** | The group containing your connector(s) |
| **Backend cert validation** | On (Traefik presents the public wildcard cert, so it's trusted) |
| **Translate URLs in headers/body** | **Off** — not needed because external and internal hostnames are identical |

> **Critical design choice — single hostname end-to-end.** Because the External URL and Internal URL use the *same* host (`*.apps.cargas.com`), there is **no host-header translation**. This is what keeps oauth2-proxy's redirect URIs and session cookies working cleanly. If you instead translated `*.cargas.com` → `*.cargas.internal`, oauth2-proxy would build redirect URLs the external browser can't resolve, and you'd be fighting App Proxy's URL-rewriting limits. Avoid that — keep one hostname.

> **Verify against current Microsoft docs:** wildcard application publishing support, and the backend request timeout (historically ~85s default, extendable to ~180s via the "Long" backend timeout). These have changed over time and the timeout is why streaming/long-poll workloads don't belong here.

### Conditional Access (recommended)

Because apps are now internet-reachable, layer Entra Conditional Access on the published app:
- [ ] Require compliant/managed device or MFA for sensitive apps
- [ ] Scope per-app or per-group as appropriate (e.g., the customer-list site with PII gets stricter policy)

---

## 3. DNS & Certificates

### Split-Horizon DNS for `*.apps.cargas.com`

Use a dedicated subdomain (`apps.cargas.com`) so you only split-horizon that zone — you are **not** shadowing the whole corporate `cargas.com`.

| Resolver | `*.apps.cargas.com` resolves to | Used by |
|----------|----------------------------------|---------|
| **Public DNS** | App Proxy endpoint (CNAME to the `…msappproxy.net` host, or per Entra instructions) | External users |
| **Internal DNS** (private zone) | The app VM's internal IP | Connector + internal/VPN users |

This means:
- External users → public DNS → App Proxy → connector → VM
- Internal/VPN users → internal DNS → **straight to the VM** (low latency, bypasses App Proxy; oauth2-proxy still authenticates them)
- The connector itself is internal, so it resolves the Internal URL directly to the VM

- [ ] Request the internal **private DNS zone** for `apps.cargas.com` → app VM IP (wildcard `*`)
- [ ] Create the **public** CNAME/record per App Proxy's published instructions
- [ ] Decide: wildcard record vs. per-app records (wildcard preserves zero-touch deploys)

### TLS Certificate

One **public-CA wildcard cert** for `*.apps.cargas.com`, used in two places:

1. **App Proxy edge** — uploaded to the published app (presented to internet users)
2. **Traefik backend** — installed on the VM so the connector's backend TLS validation trusts it (public CA = trusted everywhere, no internal-CA distribution needed)

- [ ] Obtain wildcard cert for `*.apps.cargas.com` (public CA)
- [ ] Upload to App Proxy
- [ ] Place cert + key in `/data/traefik/certs/` and reference via Traefik dynamic config

---

## 4. Traefik v3 (Reverse Proxy)

Traefik is the internal front door behind the connector. It auto-discovers Docker containers via labels and routes traffic to them — no config editing when deploying new apps. It now presents the wildcard cert for backend TLS rather than fetching Let's Encrypt certs.

### Docker Compose — Traefik

```yaml
# /data/traefik/docker-compose.yml
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedByDefault=false"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # Redirect HTTP → HTTPS (for internal/VPN direct hits)
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.websecure.http.tls=true"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config/dynamic:/etc/traefik/dynamic:ro
      - ./certs:/certs:ro
    networks:
      - proxy
    labels:
      # Dashboard at traefik.apps.cargas.com (protected by oauth2-proxy)
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.apps.cargas.com`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=oauth@docker"

networks:
  proxy:
    name: proxy
    external: true
```

### Dynamic config — wildcard cert

```yaml
# /data/traefik/config/dynamic/certs.yml
tls:
  certificates:
    - certFile: /certs/apps.cargas.com.crt
      keyFile: /certs/apps.cargas.com.key
  stores:
    default:
      defaultCertificate:
        certFile: /certs/apps.cargas.com.crt
        keyFile: /certs/apps.cargas.com.key
```

### Key Points
- `exposedByDefault: false` — containers must opt in with `traefik.enable=true`
- Docker socket mounted read-only — Traefik watches for container start/stop
- All apps share the `proxy` network
- App routing rules use `Host(`<app>.apps.cargas.com`)` (see [[Publishing Guide]])

### Create the network first

```bash
docker network create proxy
```

---

## 5. oauth2-proxy (SSO with Entra ID)

A single oauth2-proxy instance acts as ForwardAuth middleware for all apps. It populates the identity headers apps consume, and authenticates internal/VPN users directly. (See [Architecture Overview](#why-oauth2-proxy-stays-even-though-app-proxy-pre-authenticates) for why this coexists with App Proxy.)

### Entra ID App Registration (separate from the App Proxy app)

- [ ] Register a **second** app in Entra ID for oauth2-proxy (App Proxy auto-creates its own; this one is distinct)
- [ ] Redirect URIs — register **both** domains so external and internal access both work:
  - `https://*.apps.cargas.com/oauth2/callback` (or per-app callbacks if wildcard redirect URIs aren't permitted)
- [ ] Enable ID tokens; configure **group claims** (Security groups in token)
- [ ] Note: Client ID, Client Secret, Tenant ID

### Docker Compose — oauth2-proxy

```yaml
# /data/traefik/docker-compose.yml (add to same file)
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    container_name: oauth2-proxy
    restart: unless-stopped
    environment:
      # Entra ID OIDC (use OIDC provider, not Azure provider — better group claims)
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_OIDC_ISSUER_URL: https://login.microsoftonline.com/${TENANT_ID}/v2.0
      OAUTH2_PROXY_CLIENT_ID: ${CLIENT_ID}
      OAUTH2_PROXY_CLIENT_SECRET: ${CLIENT_SECRET}

      # Cookie — domain covers the app subdomain
      OAUTH2_PROXY_COOKIE_SECRET: ${COOKIE_SECRET}  # generate: python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'
      OAUTH2_PROXY_COOKIE_DOMAINS: .apps.cargas.com
      OAUTH2_PROXY_COOKIE_SECURE: "true"

      # Auth behavior
      OAUTH2_PROXY_EMAIL_DOMAINS: cargas.com
      OAUTH2_PROXY_WHITELIST_DOMAINS: .apps.cargas.com
      OAUTH2_PROXY_SET_XAUTHREQUEST: "true"
      OAUTH2_PROXY_PASS_ACCESS_TOKEN: "true"

      # Reverse proxy mode — honor forwarded host/proto when building redirects
      OAUTH2_PROXY_REVERSE_PROXY: "true"
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      # Auth endpoint
      - "traefik.http.routers.oauth2.rule=Host(`auth.apps.cargas.com`)"
      - "traefik.http.services.oauth2.loadbalancer.server.port=4180"
      # ForwardAuth middleware (all apps reference this)
      - "traefik.http.middlewares.oauth.forwardAuth.address=http://oauth2-proxy:4180/oauth2/auth"
      - "traefik.http.middlewares.oauth.forwardAuth.trustForwardHeader=true"
      - "traefik.http.middlewares.oauth.forwardAuth.authResponseHeaders=X-Forwarded-User,X-Forwarded-Groups,X-Forwarded-Email,X-Forwarded-Access-Token"
```

> **Single-hostname payoff:** because App Proxy does not translate the host (External = Internal = `*.apps.cargas.com`), oauth2-proxy sees the same hostname the browser used, builds correct `https://<app>.apps.cargas.com/oauth2/callback` redirects, and sets a cookie on `.apps.cargas.com` that the browser keeps. This is why the hostname strategy in Section 2/3 matters — get it wrong and you get redirect loops.

### What Apps Receive

After SSO, every request to any app includes these headers:

| Header | Value |
|--------|-------|
| `X-Forwarded-User` | User's UPN |
| `X-Forwarded-Email` | User's email |
| `X-Forwarded-Groups` | Comma-separated Entra group IDs |
| `X-Forwarded-Access-Token` | OAuth token (if app needs to call Graph API) |

Apps don't implement auth. They just read headers. (Unchanged by the App Proxy addition.)

---

## 6. Shared PostgreSQL

One Postgres instance, one database per app, one role per app. (Unaffected by App Proxy — internal only, never published.)

### Docker Compose — PostgreSQL

```yaml
# /data/postgres/docker-compose.yml
services:
  postgres:
    image: postgres:16
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_ADMIN_PASSWORD}
    volumes:
      - /data/postgres/data:/var/lib/postgresql/data
    networks:
      - proxy
    # Not exposed to Traefik or App Proxy — internal only
    # Apps connect via Docker network: postgres://appuser:pass@postgres:5432/db_appname
```

### Per-App Database Provisioning

```sql
-- Run as postgres admin
CREATE DATABASE db_appname;
CREATE ROLE appname_user WITH LOGIN PASSWORD 'generated-password';
GRANT ALL PRIVILEGES ON DATABASE db_appname TO appname_user;
-- Restrict to only this database
REVOKE ALL ON DATABASE postgres FROM appname_user;
```

### Backups

```bash
# /data/postgres/backup.sh — run via cron daily
#!/bin/bash
BACKUP_DIR="/data/postgres/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker exec postgres pg_dumpall -U postgres > "$BACKUP_DIR/full_$TIMESTAMP.sql"

# Retain 30 days
find "$BACKUP_DIR" -name "*.sql" -mtime +30 -delete

# Optional: sync to Azure Blob Storage
# az storage blob upload-batch --source "$BACKUP_DIR" --destination backups
```

- [ ] Set up cron job: `0 2 * * * /data/postgres/backup.sh`
- [ ] Configure Azure Blob Storage for off-VM backup copies

---

## 7. Environment File

Store secrets in a `.env` file on the VM (not in Git):

```bash
# /data/.env
TENANT_ID=your-entra-tenant-id
CLIENT_ID=oauth2-proxy-app-registration-client-id
CLIENT_SECRET=oauth2-proxy-app-registration-client-secret
COOKIE_SECRET=generated-base64-string
POSTGRES_ADMIN_PASSWORD=strong-generated-password
```

- [ ] Restrict file permissions: `chmod 600 /data/.env`
- [ ] Document secret rotation procedure (oauth2-proxy client secret, Postgres passwords)
- [ ] Track wildcard cert expiry — renewal updates **both** App Proxy and Traefik

---

## 8. Validation Checklist

After setup, verify each layer works — outside-in.

### App Proxy & Connector
- [ ] Connector shows **Active** in Entra admin center
- [ ] From an **external** network (off VPN), navigating to `https://hello.apps.cargas.com` triggers Entra login
- [ ] After login, the request reaches the VM (check Traefik access logs)
- [ ] Conditional Access policy applies as expected (MFA / device compliance)

### DNS & Cert
- [ ] External DNS resolves `*.apps.cargas.com` to the App Proxy endpoint
- [ ] Internal DNS resolves `*.apps.cargas.com` to the VM IP (test from the connector VM and a VPN client)
- [ ] Cert is valid and trusted at both the App Proxy edge and the Traefik backend (no cert warnings)

### Traefik
- [ ] `https://traefik.apps.cargas.com` loads the dashboard (after SSO)
- [ ] HTTP redirects to HTTPS for direct internal hits
- [ ] Invalid subdomains return 404 (not a proxy error)

### SSO (both paths)
- [ ] **External path:** single interactive sign-in (App Proxy); oauth2-proxy completes silently — no second prompt
- [ ] **Internal path:** on VPN, hitting `https://hello.apps.cargas.com` resolves straight to the VM and oauth2-proxy authenticates (no App Proxy involved)
- [ ] Only `@cargas.com` emails can authenticate
- [ ] Group claims appear in `X-Forwarded-Groups` header

### Hello World App
- [ ] Deploy the hello-world container (see [[Publishing Guide]])
- [ ] Reachable externally at `hello.apps.cargas.com` with no new App Proxy publication (wildcard works)
- [ ] Displays authenticated user's email + groups from headers

### PostgreSQL
- [ ] App connects via `DATABASE_URL` on the Docker network
- [ ] App role cannot access other app databases
- [ ] Backup cron produces valid SQL dumps

---

## 9. Monitoring (Lightweight Start)

Don't over-engineer monitoring at Phase 1. Start with:

- **App Proxy health** — connector status + the published app's health in the Entra admin center
- **Traefik dashboard** — active routes, health status, request metrics
- **Docker health checks** — each app exposes `/healthz`; Docker restarts unhealthy containers
- **Disk space alert** — simple cron that emails if `/data` exceeds 75%
- **Backup verification** — weekly manual check that backups are valid
- **Cert expiry alert** — wildcard cert renewal hits two places (App Proxy + Traefik)

Scale monitoring later if the platform grows beyond 10 apps.

---

## Startup Order

```bash
# On the app VM:

# 1. Create shared network
docker network create proxy

# 2. Start infrastructure (from /data/traefik/)
docker compose --env-file /data/.env up -d

# 3. Start PostgreSQL (from /data/postgres/)
docker compose --env-file /data/.env up -d

# 4. Deploy apps (each app has its own docker-compose.yml)
cd /data/apps/hello-world && docker compose up -d

# On the connector VM (one-time): install + register the Entra private network connector.
# App Proxy publication is configured once in the Entra admin center (wildcard app).
```

---

## Scope: APIs & MCP Servers

App Proxy is built for **interactive, browser-based web apps**. It is a **poor fit** for:

- **APIs called by non-browser clients** — pre-auth expects a browser login flow; service-to-service and webhook senders don't do that
- **MCP servers (HTTP transport)** — long-lived/streaming connections collide with App Proxy's backend timeout; MCP clients use OAuth device flow, not browser SSO
- **Webhook receivers** (Zendesk, JIRA) — senders POST with a signing secret, not an interactive login

### Recommended path for these

| Traffic | Exposure | Notes |
|---------|----------|-------|
| Web UIs | **App Proxy** | This guide |
| APIs / MCP / webhooks | **Azure API Management** or **App Gateway + WAF** | First-class API/OAuth semantics, handles long-lived connections, client-credentials flow |
| Service-to-service (both on this VM) | **Docker network** | Don't leave the VM at all |
| Admin/debug (Traefik dashboard, Postgres) | **VPN-only** | Never publish |

- [ ] Decide whether APIs/MCP are Phase 1 or future. If future, App Proxy for web apps now; add APIM/App Gateway later when needed.
- [ ] If MCP servers are in scope: host the **HTTP transport**, register the MCP server as its own Entra app (OAuth 2.1), expose via APIM/App Gateway, and flow user/group claims into the server for data-access enforcement.

---

## Related

- [[Setup Outline]] — Full phased plan including organizational setup
- [[Publishing Guide]] — How to create and deploy apps
- [[Code Collective]] — Initiative overview

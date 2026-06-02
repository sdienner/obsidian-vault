---
date: 2026-05-18
updated: 2026-06-02
tags: [project, infrastructure, technical]
status: active
---
# Vibe Coding Server — Setup Guide

Reference guide for standing up the Code Collective deployment platform on Azure.

**Target state (bootstrap):** An internal Azure VM running Docker containers and a shared PostgreSQL. The VM has **no public IP**. Each app is published through **Microsoft Entra Application Proxy**, which pre-authenticates users at Microsoft's edge and tunnels — via an outbound-only connector — directly to that app's **container port** on the VM. No reverse proxy, no internal DNS, no internal certs.

> **Current mode — default domain + direct ports (Option A).** We start on App Proxy's **default `msappproxy.net` domain** and point each publication straight at a container port (`http://<vm-ip>:<port>`). Fastest possible start. Trade-offs: **one App Proxy publication per app**, **manual port assignment**, `msappproxy.net` URLs, and a reverse proxy is reintroduced only when we [graduate to a custom domain](#graduation-graduating-to-a-custom-domain).

> **Scope note:** App Proxy is for **browser-based web apps**. APIs, webhooks, and MCP servers need a different path — see [Scope: APIs & MCP Servers](#scope-apis--mcp-servers).

---

## Architecture Overview

```
External user (any device, no VPN)
   │
   ▼
Entra ID  ──── pre-authentication at Microsoft's edge
   │           (only authenticated cargas.com users pass)
   ▼
Azure App Proxy service  (Microsoft cloud, DDoS/WAF, TLS edge, msappproxy.net cert)
   │   one publication per app:  https://<app>-cargas.msappproxy.net
   │
   │  outbound-only TLS tunnel (connector dials out — no inbound firewall rule)
   ▼
App Proxy Connector  (small Windows VM in Cargas VNet)
   │
   ▼  internal URL:  http://<vm-private-ip>:<port>
┌──────────────────────────────────────────────────────────┐
│ Linux VM (Ubuntu 24.04) — internal only, NO public IP      │
│                                                            │
│   :3001  hello            ← pre-auth-only app (container)   │
│   :3002  oauth2-proxy ──► noco-tracker  ← identity app      │
│   :3003  ...                                               │
│                                                            │
│   Shared PostgreSQL 16  (one DB + role per app)            │
└──────────────────────────────────────────────────────────┘
```

### Two layers of auth, and when you need each

- **App Proxy pre-auth (always on)** — the *access gate*. Only authenticated, assigned Cargas users reach the app. For many internal tools (dashboards, lookups) this is **all you need**.
- **oauth2-proxy (per-app, only when needed)** — runs **in reverse-proxy mode** in front of an app that must know **who** the user is. It injects `X-Forwarded-User` / `X-Forwarded-Groups` for the app to authorize on. App Proxy points at the oauth2-proxy port instead of the app port.

> Because each identity app gets its **own** oauth2-proxy, its redirect URL is simply its own `msappproxy.net` callback — no shared-instance juggling. (Shared SSO across many apps is a custom-domain benefit; see [graduation](#graduation-graduating-to-a-custom-domain).)

---

## 1. Azure VM Provisioning

### App VM Specification

| Setting | Value |
|---------|-------|
| **Size** | `Standard_D4s_v5` (4 vCPU, 16 GB RAM) |
| **OS** | Ubuntu 24.04 LTS |
| **OS Disk** | 64 GB Premium SSD |
| **Data Disk** | 128 GB Premium SSD (mount at `/data`) |
| **Region** | Same as existing Cargas Azure resources |
| **Network** | Corporate VNet, **no public IP** |
| **Inbound** | Allow the app port range (e.g. **3001–3099**) from the connector VM only. No internet inbound. |

### Companion: App Proxy Connector VM

The Entra private network connector is **Windows-only** — it can't run on the Ubuntu VM. Stand up a small Windows host (or reuse an existing Windows Server in the VNet).

| Setting | Value |
|---------|-------|
| **Size** | `Standard_B2s` / `D2s_v5` (2 vCPU, 4–8 GB) — lightweight |
| **OS** | Windows Server 2022 |
| **Network** | Same VNet; **outbound 443 to Azure**; can reach `<vm-private-ip>:<port range>` |
| **HA** | Two connectors in one group for production; one is fine to start |

### Post-Provision Steps (App VM)

- [ ] Mount data disk at `/data`
- [ ] SSH access (key-based, no password auth)
- [ ] Install Docker Engine + Docker Compose v2
- [ ] Create the shared network and dirs:

```
/data/
  postgres/
    data/
    backups/
  apps/
    hello/
    noco-tracker/
```
```bash
docker network create vibe   # shared network: apps ↔ postgres ↔ oauth2-proxy
```

### Scale Triggers
- Memory >80% sustained → upgrade to `D8s_v5`
- CPU >70% sustained → evaluate or upgrade
- Disk >75% → expand data disk

---

## 2. Microsoft Entra Application Proxy (Default Domain)

The external front door. The connector dials out to Microsoft; nothing inbound is opened on the corporate firewall.

> **Licensing:** App Proxy requires Entra ID P1 or P2. ✅ **Confirmed (2026-06-02): Cargas has Entra ID P2** — App Proxy is available, and P2 also unlocks risk-based Conditional Access (Identity Protection) and PIM for securing published apps.

### One-Time Setup

- [ ] Install the **Entra private network connector** on the Windows connector VM
- [ ] Confirm the connector registers and shows **Active**
- [ ] Confirm the connector can reach `http://<vm-private-ip>:<port>`

### Publish Each App (per-app, direct to port)

One Enterprise Application publication per tool:

| App Proxy setting | Value |
|-------------------|-------|
| **External URL** | `https://<app>-cargas.msappproxy.net` (auto-assigned; `<tenant>` = `cargas`) |
| **Internal URL** | `http://<vm-private-ip>:<port>` (the app's container port — or its oauth2-proxy port) |
| **Pre-authentication** | Microsoft Entra ID |
| **Connector group** | The group containing your connector(s) |
| **Backend cert validation** | N/A — internal hop is HTTP inside the VNet (harden later) |
| **Translate URLs in headers / body** | On (rewrites internal links in responses to the external URL) |

- [ ] Assign the users/groups who may access each published app
- [ ] (Sensitive apps) attach a Conditional Access policy — Entra P2 supports MFA / compliant-device / risk-based policies

> **App authors:** because the external host differs from the internal `ip:port`, build apps with **relative URLs** so links work behind the published hostname. App Proxy's URL translation handles most absolute-link cases, but relative is safest.

> **Verify against current Microsoft docs:** the backend request timeout (historically ~85s, extendable to ~180s via "Long") — the reason streaming/long-poll workloads don't belong here.

---

## 3. Port Assignment

With no reverse proxy or DNS, the one thing you must manage centrally is **which app owns which host port**. Keep a simple registry (this note, or a file in an ops repo).

| App | Host port | Identity? | App Proxy external URL |
|-----|-----------|-----------|------------------------|
| hello | 3001 | no | `hello-cargas.msappproxy.net` |
| noco-tracker | 3002 | yes (oauth2-proxy) | `noco-tracker-cargas.msappproxy.net` |
| _next app_ | 3003 | … | … |

Conventions:
- Reserve **3001–3099** for apps; open that range on the VM from the connector only
- One host port per publication (the port App Proxy's Internal URL targets)
- For an **identity app**, the registered port is the **oauth2-proxy** port; the app container itself is not host-published

---

## 4. oauth2-proxy (Per-App — only for apps that need identity)

Skip entirely for pre-auth-only pilots. For an app that must know the user, run oauth2-proxy **in reverse-proxy mode** in the app's own compose stack: App Proxy → oauth2-proxy port → app.

### Entra App Registration (one, reused across apps)

- [ ] Register a single app for oauth2-proxy
- [ ] Add a **redirect URI per identity app**: `https://<app>-cargas.msappproxy.net/oauth2/callback`
- [ ] Enable ID tokens; configure **group claims**
- [ ] Note Client ID, Client Secret, Tenant ID (shared via each stack's env)

### Compose snippet (added to an identity app's stack)

```yaml
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    restart: unless-stopped
    environment:
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_OIDC_ISSUER_URL: https://login.microsoftonline.com/${TENANT_ID}/v2.0
      OAUTH2_PROXY_CLIENT_ID: ${CLIENT_ID}
      OAUTH2_PROXY_CLIENT_SECRET: ${CLIENT_SECRET}
      OAUTH2_PROXY_COOKIE_SECRET: ${COOKIE_SECRET}
      OAUTH2_PROXY_COOKIE_SECURE: "true"          # browser is on https (App Proxy edge)
      OAUTH2_PROXY_EMAIL_DOMAINS: cargas.com
      # Per-app redirect — host-only cookie (do NOT set a .msappproxy.net cookie domain)
      OAUTH2_PROXY_REDIRECT_URL: https://noco-tracker-cargas.msappproxy.net/oauth2/callback
      OAUTH2_PROXY_UPSTREAMS: http://app:3000     # proxies to the app container
      OAUTH2_PROXY_PASS_USER_HEADERS: "true"      # injects X-Forwarded-User/Email/Groups to the app
      OAUTH2_PROXY_REVERSE_PROXY: "true"
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
    ports:
      - "3002:4180"      # App Proxy Internal URL = http://<vm-ip>:3002
    networks: [vibe]
    depends_on: [app]
```

The app container stays **un-published** (no `ports:`) — only oauth2-proxy reaches it over the `vibe` network. The app reads `X-Forwarded-*` exactly as in the App Contract.

---

## 5. Shared PostgreSQL

One Postgres instance, one database + role per app. Internal only — never published.

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
    networks: [vibe]
    # No host port — apps reach it via the vibe network: postgres://appuser:pass@postgres:5432/db_app
networks:
  vibe:
    external: true
```

### Per-App Database Provisioning
```sql
CREATE DATABASE db_appname;
CREATE ROLE appname_user WITH LOGIN PASSWORD 'generated-password';
GRANT ALL PRIVILEGES ON DATABASE db_appname TO appname_user;
REVOKE ALL ON DATABASE postgres FROM appname_user;
```

### Backups
```bash
# /data/postgres/backup.sh — daily cron
#!/bin/bash
BACKUP_DIR="/data/postgres/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker exec postgres pg_dumpall -U postgres > "$BACKUP_DIR/full_$TIMESTAMP.sql"
find "$BACKUP_DIR" -name "*.sql" -mtime +30 -delete
```
- [ ] Cron: `0 2 * * * /data/postgres/backup.sh`
- [ ] Azure Blob Storage for off-VM copies

---

## 6. Environment File

```bash
# /data/.env   (oauth2-proxy vars only needed for identity apps)
TENANT_ID=your-entra-tenant-id
CLIENT_ID=oauth2-proxy-app-registration-client-id
CLIENT_SECRET=oauth2-proxy-app-registration-client-secret
COOKIE_SECRET=generated-base64-string
POSTGRES_ADMIN_PASSWORD=strong-generated-password
```
- [ ] `chmod 600 /data/.env`
- [ ] Document secret rotation

---

## 7. Validation Checklist

### App Proxy & Connector
- [ ] Connector shows **Active** in Entra admin center
- [ ] From an **external** network (off VPN), `https://hello-cargas.msappproxy.net` triggers Entra login
- [ ] After login the request reaches the container (check container logs)
- [ ] Only assigned users/groups can open the published app

### Ports
- [ ] Each app answers on its assigned `<vm-ip>:<port>` from the connector VM
- [ ] App port range is closed to everything except the connector

### Apps
- [ ] Pre-auth-only app: reachable externally after publication; no identity headers expected
- [ ] Identity app: oauth2-proxy port published; app shows the authenticated user's email + groups

### PostgreSQL
- [ ] App connects via `DATABASE_URL` on the `vibe` network
- [ ] App role cannot access other app databases
- [ ] Backup cron produces valid dumps

---

## 8. Monitoring (Lightweight Start)

- **App Proxy health** — connector status + published-app health in the Entra admin center
- **Docker health checks** — each app exposes `/healthz`; Docker restarts unhealthy containers
- **Disk space alert** — cron emails if `/data` exceeds 75%
- **Backup verification** — weekly manual check
- **Port registry** — keep [Section 3](#3-port-assignment) current; it's the source of truth without a dashboard

---

## Startup Order

```bash
# On the app VM:
docker network create vibe
cd /data/postgres        && docker compose --env-file /data/.env up -d
cd /data/apps/hello      && docker compose up -d
cd /data/apps/noco-tracker && docker compose --env-file /data/.env up -d

# In Entra admin center (per app, one-time):
#   publish: external <app>-cargas.msappproxy.net → internal http://<vm-ip>:<port>
#   assign users/groups
```

---

## Graduation: Graduating to a Custom Domain

Move here when you have more than a few apps, tire of managing ports/publications, or want clean URLs + shared SSO. This **reintroduces a reverse proxy (Traefik) and DNS**.

| Capability | Now (default domain + ports) | Custom domain (`*.apps.cargas.com`) |
|------------|------------------------------|-------------------------------------|
| URL | `https://<app>-cargas.msappproxy.net` | `https://<app>.apps.cargas.com` |
| New app | New publication **+ pick a port** | **Wildcard** publication + Traefik label — zero-touch |
| Routing | App Proxy → container port | Traefik routes by hostname |
| TLS cert | Microsoft's (none to manage) | Wildcard `*.apps.cargas.com` (edge + Traefik) |
| DNS | None | Public CNAME + internal split-horizon → VM |
| Identity | Per-app oauth2-proxy | One shared oauth2-proxy; shared SSO across apps |
| Port management | Manual registry | Gone — Traefik handles it |

**The single-hostname principle (at scale):** publish External and Internal URL on the **same** host (`*.apps.cargas.com`, internal resolved via split-horizon to the VM) so there's no host translation and oauth2-proxy redirects/cookies "just work." Migration: verify custom domain → wildcard cert → wildcard publication → split-horizon DNS → add Traefik routing → consolidate to one oauth2-proxy → update [[Publishing Guide]].

---

## Scope: APIs & MCP Servers

App Proxy is built for **interactive, browser-based web apps**. Poor fit for:
- **APIs from non-browser clients** — pre-auth expects a browser login
- **MCP servers (HTTP transport)** — long-lived/streaming vs. App Proxy's backend timeout; clients use OAuth device flow
- **Webhook receivers** — senders POST with a signing secret, not an interactive login

| Traffic | Exposure |
|---------|----------|
| Web UIs | **App Proxy** (this guide) |
| APIs / MCP / webhooks | **Azure API Management** or **App Gateway + WAF** |
| Service-to-service (same VM) | **Docker `vibe` network** |
| Admin/debug (Postgres) | **VPN-only** |

---

## Related

- [[Setup Outline]] — Full phased plan including organizational setup
- [[Publishing Guide]] — How to create and deploy apps
- [[Code Collective]] — Initiative overview

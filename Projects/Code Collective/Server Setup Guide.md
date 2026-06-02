---
date: 2026-05-18
updated: 2026-06-02
tags: [project, infrastructure, technical]
status: active
---
# Vibe Coding Server — Setup Guide

Reference guide for standing up the Code Collective deployment platform on Azure.

**Target state:** An internal Azure VM running Docker with Traefik reverse proxy and shared PostgreSQL. The VM has **no public IP**. External access is published through **Microsoft Entra Application Proxy**, which pre-authenticates users at Microsoft's edge and tunnels to the VM via an outbound-only connector.

> **Current mode — default domain (bootstrap).** We are starting on App Proxy's **default `msappproxy.net` domain**, not a custom domain. This is the fastest way to get the first pilots live (no domain verification, no wildcard cert, no split-horizon DNS). Trade-off: **each app needs its own App Proxy publication** (a one-time Entra step per app) and gets a URL like `https://<app>-cargas.msappproxy.net`. When the platform grows past a few apps, [graduate to a custom domain](#graduation-graduating-to-a-custom-domain) for wildcard publishing (zero-touch deploys) and prettier URLs.

> **Scope note:** App Proxy is the exposure path for **browser-based web apps**. APIs, webhook receivers, and MCP servers are a poor fit (pre-auth model, connection timeouts) and need a separate path — see [Scope: APIs & MCP Servers](#scope-apis--mcp-servers). This guide covers the web-app platform.

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
   │   external URL:  https://<app>-cargas.msappproxy.net   (one publication per app)
   │
   │  outbound-only TLS tunnel (connector dials out — no inbound firewall rule)
   ▼
App Proxy Connector  (small Windows VM in Cargas VNet)
   │
   ▼  internal URL:  https://<app>.cargas.internal   (connector resolves to the VM)
┌──────────────────────────────────────────────────────────┐
│ Linux VM (Ubuntu 24.04) — internal only, NO public IP      │
│                                                            │
│   Traefik v3  ──►  (oauth2-proxy, optional)  ──►  apps      │
│   routes on        only for apps that need        (read    │
│   *.cargas.internal user/group identity            headers)│
│                                                            │
│   Shared PostgreSQL 16  (one DB + role per app)            │
└──────────────────────────────────────────────────────────┘
        ▲
        │  Internal / VPN users resolve *.cargas.internal
        └─ directly to the VM, bypassing App Proxy.
```

### Two layers of auth, and when you need each

- **App Proxy pre-auth (always on)** — the *access gate*. Only authenticated Cargas users from the internet reach the VM. For many internal tools (read-only dashboards, lookups), this is **all you need** — every authenticated employee can use the tool.
- **oauth2-proxy (optional, per need)** — the *identity provider for apps*. It populates `X-Forwarded-User` / `X-Forwarded-Groups` so an app can tell **who** the user is and authorize by group. Add it only when an app needs per-user/per-group behavior.

> **Why oauth2-proxy is optional on the default domain.** On `msappproxy.net`, each app's external hostname differs from its internal hostname, which complicates oauth2-proxy's sign-in redirect (see [Section 5](#5-oauth2-proxy-optional--identity-for-apps-that-need-it)). For bootstrap pilots that only need "authenticated employee" access, skipping oauth2-proxy avoids that entirely. Shared single-sign-on identity across many apps is one of the things the [custom-domain graduation](#graduation-graduating-to-a-custom-domain) makes clean.

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
| **Network** | Same VNet as the app VM; **outbound 443 to Azure**; line-of-sight to the app VM; resolves `*.cargas.internal` to the VM |
| **HA** | Two connectors in one connector group recommended for production; one is fine to start |

### Post-Provision Steps (App VM)

- [ ] Mount data disk at `/data`
- [ ] Set up SSH access (key-based, no password auth)
- [ ] Install Docker Engine + Docker Compose v2
- [ ] Create directory structure:

```
/data/
  traefik/
    config/      # dynamic config (TLS cert for *.cargas.internal)
    certs/
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

## 2. Microsoft Entra Application Proxy (Default Domain)

This is the external front door. The connector dials out to Microsoft; nothing inbound is opened on the corporate firewall.

> **Licensing:** App Proxy requires Entra ID P1 or P2. ✅ **Confirmed (2026-06-02): Cargas has Entra ID P2** — App Proxy is available, and P2 additionally unlocks risk-based Conditional Access (Identity Protection) and PIM for securing published apps.

### One-Time Setup

- [ ] Install the **Entra private network connector** on the Windows connector VM (download from Entra admin center → Application Proxy)
- [ ] Confirm the connector registers and shows **Active**
- [ ] Confirm the connector can resolve `*.cargas.internal` to the app VM

### Publish Each App (per-app on the default domain)

There is **no wildcard** on the default domain, so you create one Enterprise Application publication per tool:

| App Proxy setting | Value |
|-------------------|-------|
| **External URL** | `https://<app>-cargas.msappproxy.net` (auto-assigned; `<tenant>` = `cargas`) |
| **Internal URL** | `https://<app>.cargas.internal` (the connector reaches Traefik here) |
| **Pre-authentication** | Microsoft Entra ID |
| **Connector group** | The group containing your connector(s) |
| **Backend cert validation** | On if Traefik presents a connector-trusted cert; see [Section 3](#3-internal-dns--certificates) |
| **Translate URLs in headers / body** | On (lets App Proxy rewrite internal links in responses to the external URL) |

- [ ] Assign the users/groups who may access each published app
- [ ] (Sensitive apps) attach a Conditional Access policy — Entra P2 supports MFA / compliant-device / risk-based policies

> **The per-app cost.** Each new tool = one new publication + a user/group assignment. Acceptable for a handful of pilots; it's the main reason to graduate to a custom domain later.

> **Verify against current Microsoft docs:** the backend request timeout (historically ~85s default, extendable to ~180s via the "Long" setting) — this is why streaming/long-poll workloads don't belong here.

---

## 3. Internal DNS & Certificates

On the default domain there is **nothing external to manage** — Microsoft owns `msappproxy.net`, its DNS, and its edge TLS cert. You only configure the **internal** side.

### Internal DNS

| Record | Resolves to | Used by |
|--------|-------------|---------|
| `*.cargas.internal` | The app VM's internal IP | Connector + internal/VPN users |

- [ ] Request internal DNS: wildcard `*.cargas.internal` → app VM IP (or per-app A records)
- Internal/VPN users can hit `https://<app>.cargas.internal` directly (bypassing App Proxy); App Proxy pre-auth applies only to the external path

### Backend TLS (connector → Traefik)

The connector talks to Traefik over the internal URL. Two pragmatic options:

- **Bootstrap-simple:** set the App Proxy **Internal URL to `http://<app>.cargas.internal`** and let Traefik serve the backend over HTTP. The connector→VM hop stays inside the corporate network. Avoids all cert work to start. (App Proxy edge is still HTTPS to the user.)
- **Hardened:** serve HTTPS on Traefik with an **internal-CA** cert for `*.cargas.internal`, and install the internal CA root on the connector VM so backend validation passes.

Start bootstrap-simple; move to hardened before any sensitive-data app goes live.

---

## 4. Traefik v3 (Reverse Proxy)

Traefik is the internal front door behind the connector. It auto-discovers Docker containers via labels and routes on `*.cargas.internal` — no config editing when deploying new apps.

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
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.cargas.internal`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      # Protect the dashboard: publish it via its own App Proxy app, or keep it VPN-only
networks:
  proxy:
    name: proxy
    external: true
```

> If you go **bootstrap-simple (HTTP backend)**, drop the file provider / certs volume and the `tls=true` redirect, and serve the apps on the `web` entrypoint. Re-add TLS when you harden.

### Key Points
- `exposedByDefault: false` — containers must opt in with `traefik.enable=true`
- Docker socket mounted read-only — Traefik watches for container start/stop
- All apps share the `proxy` network
- App routing rules use `Host(`<app>.cargas.internal`)` (see [[Publishing Guide]])

### Create the network first
```bash
docker network create proxy
```

---

## 5. oauth2-proxy (Optional — identity for apps that need it)

Skip this entirely for pilots that only need "authenticated employee" access — App Proxy pre-auth already gates them. Add it when an app must know **who** the user is or authorize **by group**.

### The default-domain redirect wrinkle

Because the external host (`<app>-cargas.msappproxy.net`) differs from the internal host (`<app>.cargas.internal`), oauth2-proxy must build its sign-in redirect against the **external** URL or the round-trip to Entra breaks. Practical handling:

- **Single pilot app:** run one oauth2-proxy and pin `OAUTH2_PROXY_REDIRECT_URL=https://<app>-cargas.msappproxy.net/oauth2/callback`. Register that exact URI in the oauth2-proxy app registration. Set a **host-only cookie** (leave `OAUTH2_PROXY_COOKIE_DOMAINS` unset). This definitely works.
- **Several apps needing identity:** a single shared oauth2-proxy can't carry a different static redirect per app. Either validate that App Proxy forwards `X-Forwarded-Host` (then derive per-app) — or take it as the signal to [graduate to a custom domain](#graduation-graduating-to-a-custom-domain), where one shared `*.apps.cargas.com` cookie + redirect serves every app cleanly.

### Entra App Registration (for oauth2-proxy, separate from the App Proxy app)
- [ ] Register an app for oauth2-proxy; redirect URI = `https://<app>-cargas.msappproxy.net/oauth2/callback`
- [ ] Enable ID tokens; configure **group claims**
- [ ] Note Client ID, Client Secret, Tenant ID

### Docker Compose — oauth2-proxy (single-app pattern)
```yaml
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    container_name: oauth2-proxy
    restart: unless-stopped
    environment:
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_OIDC_ISSUER_URL: https://login.microsoftonline.com/${TENANT_ID}/v2.0
      OAUTH2_PROXY_CLIENT_ID: ${CLIENT_ID}
      OAUTH2_PROXY_CLIENT_SECRET: ${CLIENT_SECRET}
      OAUTH2_PROXY_COOKIE_SECRET: ${COOKIE_SECRET}
      # Host-only cookie on the default domain — do NOT set a .msappproxy.net cookie domain
      OAUTH2_PROXY_COOKIE_SECURE: "true"
      OAUTH2_PROXY_EMAIL_DOMAINS: cargas.com
      OAUTH2_PROXY_REDIRECT_URL: https://APP-cargas.msappproxy.net/oauth2/callback
      OAUTH2_PROXY_SET_XAUTHREQUEST: "true"
      OAUTH2_PROXY_REVERSE_PROXY: "true"
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.middlewares.oauth.forwardAuth.address=http://oauth2-proxy:4180/oauth2/auth"
      - "traefik.http.middlewares.oauth.forwardAuth.trustForwardHeader=true"
      - "traefik.http.middlewares.oauth.forwardAuth.authResponseHeaders=X-Forwarded-User,X-Forwarded-Groups,X-Forwarded-Email"
```

Apps behind oauth2-proxy read `X-Forwarded-User` / `X-Forwarded-Groups` (unchanged App Contract). The forwardAuth route must also be reachable at the external host — another reason this is cleaner under a shared custom domain.

---

## 6. Shared PostgreSQL

One Postgres instance, one database per app, one role per app. (Internal only — never published.)

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
    # Apps connect via Docker network: postgres://appuser:pass@postgres:5432/db_appname
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
# /data/postgres/backup.sh — run via cron daily
#!/bin/bash
BACKUP_DIR="/data/postgres/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker exec postgres pg_dumpall -U postgres > "$BACKUP_DIR/full_$TIMESTAMP.sql"
find "$BACKUP_DIR" -name "*.sql" -mtime +30 -delete
# Optional: az storage blob upload-batch --source "$BACKUP_DIR" --destination backups
```
- [ ] Cron: `0 2 * * * /data/postgres/backup.sh`
- [ ] Configure Azure Blob Storage for off-VM copies

---

## 7. Environment File

```bash
# /data/.env
TENANT_ID=your-entra-tenant-id
CLIENT_ID=oauth2-proxy-app-registration-client-id      # only if using oauth2-proxy
CLIENT_SECRET=oauth2-proxy-app-registration-client-secret
COOKIE_SECRET=generated-base64-string
POSTGRES_ADMIN_PASSWORD=strong-generated-password
```
- [ ] `chmod 600 /data/.env`
- [ ] Document secret rotation procedure

---

## 8. Validation Checklist

### App Proxy & Connector
- [ ] Connector shows **Active** in Entra admin center
- [ ] From an **external** network (off VPN), `https://hello-cargas.msappproxy.net` triggers Entra login
- [ ] After login, the request reaches the VM (check Traefik access logs)
- [ ] Only assigned users/groups can open the published app

### Internal DNS
- [ ] `*.cargas.internal` resolves to the VM from the connector VM and from a VPN client

### Traefik
- [ ] App reachable internally at `https://hello.cargas.internal` (or `http://` in bootstrap-simple)
- [ ] Invalid internal hostnames return 404

### Hello World App
- [ ] Deploy the hello-world container (see [[Publishing Guide]])
- [ ] Reachable externally via its msappproxy.net URL after publication
- [ ] (If using oauth2-proxy) shows the authenticated user's email + groups from headers

### PostgreSQL
- [ ] App connects via `DATABASE_URL` on the Docker network
- [ ] App role cannot access other app databases
- [ ] Backup cron produces valid SQL dumps

---

## 9. Monitoring (Lightweight Start)

- **App Proxy health** — connector status + published-app health in the Entra admin center
- **Traefik dashboard** — active routes, health, metrics
- **Docker health checks** — each app exposes `/healthz`; Docker restarts unhealthy containers
- **Disk space alert** — cron emails if `/data` exceeds 75%
- **Backup verification** — weekly manual check

---

## Startup Order

```bash
# On the app VM:
docker network create proxy
cd /data/traefik   && docker compose --env-file /data/.env up -d
cd /data/postgres  && docker compose --env-file /data/.env up -d
cd /data/apps/hello-world && docker compose up -d

# In Entra admin center (per app, one-time on the default domain):
#   create the App Proxy publication: external <app>-cargas.msappproxy.net → internal <app>.cargas.internal
#   assign users/groups
```

---

## Graduation: Graduating to a Custom Domain

Move here when you have more than a few apps, want zero-touch deploys, or want clean URLs / shared SSO.

| Capability | Default domain (now) | Custom domain (`*.apps.cargas.com`) |
|------------|----------------------|-------------------------------------|
| URL | `https://<app>-cargas.msappproxy.net` | `https://<app>.apps.cargas.com` |
| New app | One App Proxy publication **per app** | **Wildcard** publication covers all — zero-touch |
| TLS cert | Microsoft's (nothing to manage) | You provide a wildcard `*.apps.cargas.com` cert (edge + Traefik backend) |
| DNS | None to manage | Public CNAME + internal **split-horizon** private zone → VM |
| oauth2-proxy | Per-app redirect; host-only cookie; awkward across apps | One shared instance; cookie domain `.apps.cargas.com`; clean SSO across all apps |
| Identity/SSO across apps | Re-establish per app | Shared session |

**The single-hostname principle:** with the custom domain, publish External URL and Internal URL on the **same** host (`*.apps.cargas.com`, internal resolved via split-horizon to the VM). No host translation → oauth2-proxy redirects and cookies "just work." That is the main technical reason the custom domain is the real answer at scale.

Migration steps (when ready): verify the custom domain in Entra → obtain wildcard cert → publish the wildcard app → set up split-horizon DNS → switch Traefik routing rules to `*.apps.cargas.com` → consolidate to one shared oauth2-proxy → update [[Publishing Guide]] hostnames.

---

## Scope: APIs & MCP Servers

App Proxy is built for **interactive, browser-based web apps**. It is a **poor fit** for:

- **APIs called by non-browser clients** — pre-auth expects a browser login flow
- **MCP servers (HTTP transport)** — long-lived/streaming connections collide with App Proxy's backend timeout; MCP clients use OAuth device flow, not browser SSO
- **Webhook receivers** (Zendesk, JIRA) — senders POST with a signing secret, not an interactive login

### Recommended path for these

| Traffic | Exposure | Notes |
|---------|----------|-------|
| Web UIs | **App Proxy** | This guide |
| APIs / MCP / webhooks | **Azure API Management** or **App Gateway + WAF** | First-class API/OAuth semantics, handles long-lived connections |
| Service-to-service (both on this VM) | **Docker network** | Don't leave the VM at all |
| Admin/debug (Traefik dashboard, Postgres) | **VPN-only** | Never publish |

---

## Related

- [[Setup Outline]] — Full phased plan including organizational setup
- [[Publishing Guide]] — How to create and deploy apps
- [[Code Collective]] — Initiative overview

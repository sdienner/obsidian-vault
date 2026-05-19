---
date: 2026-05-18
tags: [project, infrastructure, technical]
status: active
---
# Vibe Coding Server — Setup Guide

Reference guide for standing up the Code Collective deployment platform on Azure.

**Target state:** An Azure VM running Docker with Traefik reverse proxy, Entra ID SSO, shared PostgreSQL, and automated CI/CD. Developers push to GitHub; apps appear at `*.cargas.internal` automatically.

---

## 1. Azure VM Provisioning

### VM Specification

| Setting | Value |
|---------|-------|
| **Size** | `Standard_D4s_v5` (4 vCPU, 16 GB RAM) |
| **OS** | Ubuntu 24.04 LTS |
| **OS Disk** | 64 GB Premium SSD |
| **Data Disk** | 128 GB Premium SSD (mount at `/data` for Docker volumes + Postgres) |
| **Region** | Same as existing Cargas Azure resources |
| **Network** | Corporate VNet, internal-only (no public IP needed) |

### Post-Provision Steps

- [ ] Mount data disk at `/data`
- [ ] Configure firewall: allow 80/443 from corporate network only
- [ ] Set up SSH access (key-based, no password auth)
- [ ] Install Docker Engine + Docker Compose v2
- [ ] Create directory structure:

```
/data/
  traefik/
    config/
    certs/
    acme/
  postgres/
    data/
    backups/
  apps/
```

### Scale Triggers
- Memory >80% sustained → upgrade to `D8s_v5`
- CPU >70% sustained → evaluate workload or upgrade
- Disk >75% → expand data disk

---

## 2. DNS Configuration

### Wildcard DNS
Request from IT: wildcard A record pointing to the VM's internal IP.

```
*.cargas.internal  →  10.x.x.x  (VM internal IP)
cargas.internal    →  10.x.x.x
```

This means any subdomain (`timesheet.cargas.internal`, `fleet.cargas.internal`) automatically resolves to the VM. Traefik handles routing from there.

### Alternative: Individual A Records
If IT can't do wildcard DNS, you'll need a new A record for each app. Workable but adds friction to every deployment.

### Open Question
- [ ] Wildcard DNS vs individual records — confirm with IT what's possible
- [ ] Internal CA cert vs Let's Encrypt — depends on whether VM has internet access for ACME challenges

---

## 3. Traefik v3 (Reverse Proxy)

Traefik is the front door. It auto-discovers Docker containers via labels and routes traffic to them. No config file editing when deploying new apps.

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
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # Redirect HTTP → HTTPS
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      # TLS — adjust based on cert strategy
      - "--entrypoints.websecure.http.tls=true"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config:/etc/traefik
      - ./certs:/certs
    networks:
      - proxy
    labels:
      # Traefik dashboard at traefik.cargas.internal (protected by SSO)
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.cargas.internal`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=oauth@docker"

networks:
  proxy:
    name: proxy
    external: true
```

### Key Points
- `exposedByDefault: false` — containers must opt in with `traefik.enable=true`
- Docker socket mounted read-only — Traefik watches for container start/stop
- All apps share the `proxy` network

### Create the network first

```bash
docker network create proxy
```

---

## 4. oauth2-proxy (SSO with Entra ID)

Single oauth2-proxy instance acts as ForwardAuth middleware for all apps. Users authenticate once, get a session cookie, and are passed through to any app.

### Entra ID App Registration

- [ ] Register new app in Azure Entra ID
- [ ] Set redirect URI: `https://auth.cargas.internal/oauth2/callback`
- [ ] Enable ID tokens
- [ ] Configure group claims (Security groups in token)
- [ ] Note: Client ID, Client Secret, Tenant ID

### Docker Compose — oauth2-proxy

```yaml
# /data/traefik/docker-compose.yml (add to same file)
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    container_name: oauth2-proxy
    restart: unless-stopped
    environment:
      # Entra ID OIDC (use OIDC provider, not Azure provider)
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_OIDC_ISSUER_URL: https://login.microsoftonline.com/${TENANT_ID}/v2.0
      OAUTH2_PROXY_CLIENT_ID: ${CLIENT_ID}
      OAUTH2_PROXY_CLIENT_SECRET: ${CLIENT_SECRET}

      # Cookie
      OAUTH2_PROXY_COOKIE_SECRET: ${COOKIE_SECRET}  # generate: python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'
      OAUTH2_PROXY_COOKIE_DOMAINS: .cargas.internal
      OAUTH2_PROXY_COOKIE_SECURE: "true"

      # Auth behavior
      OAUTH2_PROXY_EMAIL_DOMAINS: cargas.com
      OAUTH2_PROXY_WHITELIST_DOMAINS: .cargas.internal
      OAUTH2_PROXY_SET_XAUTHREQUEST: "true"
      OAUTH2_PROXY_PASS_ACCESS_TOKEN: "true"

      # Reverse proxy mode
      OAUTH2_PROXY_REVERSE_PROXY: "true"
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      # Auth endpoint
      - "traefik.http.routers.oauth2.rule=Host(`auth.cargas.internal`)"
      - "traefik.http.services.oauth2.loadbalancer.server.port=4180"
      # ForwardAuth middleware (all apps reference this)
      - "traefik.http.middlewares.oauth.forwardAuth.address=http://oauth2-proxy:4180/oauth2/auth"
      - "traefik.http.middlewares.oauth.forwardAuth.trustForwardHeader=true"
      - "traefik.http.middlewares.oauth.forwardAuth.authResponseHeaders=X-Forwarded-User,X-Forwarded-Groups,X-Forwarded-Email,X-Forwarded-Access-Token"
```

### What Apps Receive

After SSO, every request to any app includes these headers:

| Header | Value |
|--------|-------|
| `X-Forwarded-User` | User's UPN |
| `X-Forwarded-Email` | User's email |
| `X-Forwarded-Groups` | Comma-separated Entra group IDs |
| `X-Forwarded-Access-Token` | OAuth token (if app needs to call Graph API) |

Apps don't implement auth. They just read headers.

---

## 5. Shared PostgreSQL

One Postgres instance, one database per app, one role per app.

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
    # Not exposed to Traefik — internal only
    # Apps connect via Docker network: postgres://appuser:pass@postgres:5432/db_appname
```

### Per-App Database Provisioning

When onboarding a new app that needs a database:

```sql
-- Run as postgres admin
CREATE DATABASE db_appname;
CREATE ROLE appname_user WITH LOGIN PASSWORD 'generated-password';
GRANT ALL PRIVILEGES ON DATABASE db_appname TO appname_user;
-- Restrict to only this database
REVOKE ALL ON DATABASE postgres FROM appname_user;
```

Automate this with a provisioning script (future: part of `vibe create-app` CLI).

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

## 6. Environment File

Store secrets in a `.env` file on the VM (not in Git):

```bash
# /data/.env
TENANT_ID=your-entra-tenant-id
CLIENT_ID=your-app-registration-client-id
CLIENT_SECRET=your-app-registration-client-secret
COOKIE_SECRET=generated-base64-string
POSTGRES_ADMIN_PASSWORD=strong-generated-password
```

- [ ] Restrict file permissions: `chmod 600 /data/.env`
- [ ] Document secret rotation procedure

---

## 7. Validation Checklist

After setup, verify each layer works:

### Traefik
- [ ] `https://traefik.cargas.internal` loads the dashboard (after SSO)
- [ ] HTTP redirects to HTTPS
- [ ] Invalid subdomains return 404 (not proxy error)

### SSO
- [ ] Navigating to any `*.cargas.internal` URL triggers Entra ID login
- [ ] After login, session cookie persists across subdomains
- [ ] Only `@cargas.com` emails can authenticate
- [ ] Group claims appear in `X-Forwarded-Groups` header

### Hello World App
- [ ] Deploy the hello-world container (see [[Publishing Guide]])
- [ ] Accessible at `hello.cargas.internal`
- [ ] Displays authenticated user's email from headers
- [ ] Shows group memberships

### PostgreSQL
- [ ] App can connect via `DATABASE_URL` on Docker network
- [ ] App role cannot access other app databases
- [ ] Backup cron produces valid SQL dumps

---

## 8. Monitoring (Lightweight Start)

Don't over-engineer monitoring at Phase 1. Start with:

- **Traefik dashboard** — shows active routes, health status, request metrics
- **Docker health checks** — each app exposes `/healthz`; Docker restarts unhealthy containers
- **Disk space alert** — simple cron that emails if `/data` exceeds 75%
- **Backup verification** — weekly manual check that backups are valid

Scale monitoring later if the platform grows beyond 10 apps.

---

## Startup Order

```bash
# 1. Create shared network
docker network create proxy

# 2. Start infrastructure (from /data/traefik/)
docker compose --env-file /data/.env up -d

# 3. Start PostgreSQL (from /data/postgres/)
docker compose --env-file /data/.env up -d

# 4. Deploy apps (each app has its own docker-compose.yml)
cd /data/apps/hello-world && docker compose up -d
```

---

## Related

- [[Setup Outline]] — Full phased plan including organizational setup
- [[Publishing Guide]] — How to create and deploy apps
- [[Code Collective]] — Initiative overview

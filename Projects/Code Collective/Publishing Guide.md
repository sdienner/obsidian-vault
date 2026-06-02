---
date: 2026-05-18
updated: 2026-06-02
tags: [project, infrastructure, technical]
status: active
---
# Publishing Guide — Deploying Apps to the Vibe Coding Server

How to build and deploy an app. Each app runs as a container on the VM, exposes a **host port**, and is published externally through Entra Application Proxy at `https://<app>-cargas.msappproxy.net` — reachable from **any device with no VPN**, behind Entra ID single sign-on. Covers both the developer workflow and the sponsored development workflow for non-technical requests.

> **Current setup: default domain + direct ports.** No reverse proxy, no internal DNS. App Proxy points straight at your container's port. Each app needs a one-time App Proxy publication (an admin step in Entra) and a port from the registry. See [[Server Setup Guide]] for the full architecture and the custom-domain graduation path.

---

## The App Contract

Every app deployed to the vibe server must conform to this contract:

### Required

| Requirement | Detail |
|-------------|--------|
| **Dockerfile** | Builds to a single container |
| **HTTP port** | Listens on one port (default 3000 in-container) |
| **Host port** | Publishes a unique host port from the registry (e.g. `3001:3000`) — this is what App Proxy targets |
| **Relative URLs** | Build links relative so they work behind the `msappproxy.net` hostname |
| **Healthcheck** | Expose `GET /healthz` returning 200 when healthy |

### Optional

| Feature | Detail |
|---------|--------|
| **Identity** | Need to know the user? Add an oauth2-proxy sidecar (below) and read `X-Forwarded-User` / `X-Forwarded-Groups` |
| **Database** | Request a PostgreSQL database — you'll receive a `DATABASE_URL` env var |
| **Fabric sync** | Opt in to sync your database to Microsoft Fabric for reporting |

### What you get for free

- **SSO** — App Proxy pre-authenticates every external user with Entra ID before requests reach your app (no login code)
- **HTTPS** — App Proxy terminates TLS at the edge
- **External access** — reachable from anywhere (no VPN) behind Entra sign-in, once an admin publishes the app
- **Container restart** — Docker restarts your app on crash if a healthcheck is configured

> **You manage two things per app:** a **host port** (from the [registry in the Server Setup Guide](Server%20Setup%20Guide.md)) and a **one-time App Proxy publication**. There's no auto-routing on the default domain.

---

## ⚠️ Your App Is Internet-Facing (Behind SSO)

Once published, your app is reachable from the public internet at `https://<app>-cargas.msappproxy.net` — **after** Entra ID sign-in. No VPN. That's the point: it's what makes these tools get used (a manager can glance at a dashboard from their phone). But it changes your responsibilities:

- **Authorize, don't trust the network.** Anyone assigned to the publication passes the SSO gate; there is no internal-network boundary behind it. Restrict the publication's user/group assignment — and if the app runs behind oauth2-proxy, also check `X-Forwarded-Groups` in-app.
- **Treat sensitive data accordingly.** PII/financials warrant a scoped Conditional Access policy. Cargas has **Entra P2**, so risk-based / MFA / device-compliance policies are available — request them when scoping a sensitive app.
- **No secrets in the front end.** Assume the URL can be hit by any assigned, authenticated employee.

---

## Creating a New App

### 1. Start from the template repo

```bash
gh repo create cargas-internal/my-app --template cargas-internal/vibe-app-template --private
git clone git@github.com:cargas-internal/my-app.git
cd my-app
```

The template includes a `Dockerfile`, a `docker-compose.yml` (port-mapped, with an optional oauth2-proxy block), `.github/workflows/deploy.yml`, starter `src/`, and a `README.md`.

### 2. Pick a port and configure the container

Claim the next free host port from the registry in [[Server Setup Guide]] (§ Port Assignment).

**Pre-auth-only app** (most pilots — every authenticated employee may use it):

```yaml
services:
  app:
    build: .
    container_name: my-app
    restart: unless-stopped
    environment:
      - PORT=3000
      # - DATABASE_URL=postgres://my_app_user:password@postgres:5432/db_my_app
    ports:
      - "3001:3000"        # host 3001 → container 3000; App Proxy Internal URL = http://<vm-ip>:3001
    networks: [vibe]
networks:
  vibe:
    external: true
```

**Identity app** (needs to know the user / authorize by group) — add an oauth2-proxy sidecar; App Proxy targets *its* port, and the app stays un-published:

```yaml
services:
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    restart: unless-stopped
    environment:
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_OIDC_ISSUER_URL: https://login.microsoftonline.com/${TENANT_ID}/v2.0
      OAUTH2_PROXY_CLIENT_ID: ${CLIENT_ID}
      OAUTH2_PROXY_CLIENT_SECRET: ${CLIENT_SECRET}
      OAUTH2_PROXY_COOKIE_SECRET: ${COOKIE_SECRET}
      OAUTH2_PROXY_COOKIE_SECURE: "true"
      OAUTH2_PROXY_EMAIL_DOMAINS: cargas.com
      OAUTH2_PROXY_REDIRECT_URL: https://my-app-cargas.msappproxy.net/oauth2/callback
      OAUTH2_PROXY_UPSTREAMS: http://app:3000
      OAUTH2_PROXY_PASS_USER_HEADERS: "true"
      OAUTH2_PROXY_REVERSE_PROXY: "true"
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
    ports:
      - "3002:4180"        # App Proxy Internal URL = http://<vm-ip>:3002
    networks: [vibe]
    depends_on: [app]
  app:
    build: .
    container_name: my-app
    restart: unless-stopped
    environment:
      - PORT=3000
    networks: [vibe]       # NOT host-published — only oauth2-proxy reaches it
networks:
  vibe:
    external: true
```

> An admin must register `https://my-app-cargas.msappproxy.net/oauth2/callback` as a redirect URI on the shared oauth2-proxy app registration.

### 3. Read auth headers (identity apps only)

```javascript
// Node/Express — only populated when behind oauth2-proxy
app.get("/", (req, res) => {
  const user = req.headers["x-forwarded-user"];
  const groups = (req.headers["x-forwarded-groups"] || "").split(",");
  res.json({ user, groups });
});
```
```python
# Python/Flask
@app.route("/")
def index():
    user = request.headers.get("X-Forwarded-User")
    groups = request.headers.get("X-Forwarded-Groups", "").split(",")
    return {"user": user, "groups": groups}
```

> **Authorization pattern:** for anything beyond "all employees," gate on group membership, e.g. `if "energy-implementation" not in groups: return 403`.

### 4. Request a database (if needed)

```sql
-- Admin runs this on the shared Postgres instance
CREATE DATABASE db_my_app;
CREATE ROLE my_app_user WITH LOGIN PASSWORD 'generated-password';
GRANT ALL PRIVILEGES ON DATABASE db_my_app TO my_app_user;
```
Add the `DATABASE_URL` to your app's environment.

---

## Developer Workflow

### Local Development
```bash
docker compose up --build
# or run natively for faster iteration:
cd src && npm run dev
```
Mock identity headers locally:
```bash
curl -H "X-Forwarded-User: you@cargas.com" http://localhost:3000
```

### Deploy
```bash
git add -A && git commit -m "Initial app" && git push
# GitHub Actions: build → scan → push to GHCR → SSH to VM → docker compose up -d
```

**What happens on push:**
1. GitHub Actions builds the image
2. Trivy scans for vulnerabilities
3. Lints / runs tests
4. Pushes to GitHub Container Registry
5. SSHes to the VM, `docker compose pull && up -d` on the app's assigned port
6. Container is live on `<vm-ip>:<port>`
7. For external access, an admin creates a one-time App Proxy publication (external `my-app-cargas.msappproxy.net` → internal `http://<vm-ip>:<port>`) and assigns users/groups — then it's reachable from anywhere

### Manual Deploy (fallback)
```bash
ssh vibe-server
cd /data/apps/my-app
git pull
docker compose up -d --build
```

---

## Sponsored Development Workflow

For non-technical users who need a tool built.

```
1. Requester describes the problem
   → Enterprise Enablement intake form (Asana)
   → or direct Teams message to the Code Collective channel

2. Request lands on the project board
   → Steering committee triages (or developer self-selects)
   → Classified: quick hit (<2 hours) or structured project (multi-sprint)

3. Developer picks it up
   → Schedules during Code Collective dedicated time
   → Builds from app template; claims a port; AI-assisted scaffolding (optional)

4. Requester tests
   → Admin publishes the app; developer shares the URL: https://my-tool-cargas.msappproxy.net
   → Requester opens it from any device — laptop, phone, off the VPN —
     and signs in with their normal Cargas login (Entra SSO)
   → Provides feedback

5. Iterate and ship
   → Each push auto-deploys; when the requester is satisfied, it's done
```

> **Why "no VPN" matters here:** Fred's thesis is that these tools save time and frustration. A tool that requires a VPN to open adds friction back. Through App Proxy the requester just clicks a link and signs in — like any Microsoft 365 app. (The `msappproxy.net` URL is functional but not pretty; a custom domain later gives clean `apps.cargas.com` URLs.)

### Quick Hits vs. Structured Projects

| | Quick Hit | Structured Project |
|-|-----------|-------------------|
| **Time** | Under 2 hours | Multi-sprint |
| **Governance** | Developer self-selects | Steering committee scopes and assigns |
| **Identity** | Usually pre-auth-only | Often needs oauth2-proxy + group checks |
| **Examples** | Jaiya's Zendesk/JIRA merge dashboard, lookups | Customer list site, fleet dashboard |

---

## CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
name: Build and Deploy
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t ghcr.io/cargas-internal/${{ github.event.repository.name }}:latest .
      - name: Security scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/cargas-internal/${{ github.event.repository.name }}:latest
          exit-code: 1
          severity: CRITICAL,HIGH
      - name: Push to GHCR
        run: |
          echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
          docker push ghcr.io/cargas-internal/${{ github.event.repository.name }}:latest
  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to vibe server
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.VM_HOST }}
          username: ${{ secrets.VM_USER }}
          key: ${{ secrets.VM_SSH_KEY }}
          script: |
            cd /data/apps/${{ github.event.repository.name }}
            docker compose pull
            docker compose up -d
```

### Required GitHub Secrets (set at the `cargas-internal` org level)

| Secret | Value |
|--------|-------|
| `VM_HOST` | VM internal IP or hostname |
| `VM_USER` | SSH user on VM |
| `VM_SSH_KEY` | SSH private key for deployment |

---

## App Lifecycle

### Deploying a new version
Push to `main`. CI/CD handles it.

### Rolling back
```bash
cd /data/apps/my-app
docker compose pull        # pin a previous tag if versioned
docker compose up -d
# or revert the commit and push
```

### Decommissioning an app
```bash
cd /data/apps/my-app
docker compose down
docker exec postgres psql -U postgres -c "DROP DATABASE db_my_app;"
docker exec postgres psql -U postgres -c "DROP ROLE my_app_user;"
```
- [ ] Delete the **App Proxy publication** (Enterprise Application) in Entra
- [ ] If an identity app, remove its redirect URI from the oauth2-proxy app registration
- [ ] **Free the port** in the registry
- [ ] Archive the GitHub repo

---

## Security Checklist for New Apps

- [ ] No hardcoded secrets (use environment variables)
- [ ] **Access restricted** where the tool isn't for everyone — scope the publication's user/group assignment, and (if behind oauth2-proxy) check `X-Forwarded-Groups` in-app. Network location is NOT a control
- [ ] Sensitive-data apps: request a scoped Conditional Access policy (Entra P2)
- [ ] Parameterized SQL only (no string concatenation)
- [ ] Trivy scan passes (no CRITICAL/HIGH)
- [ ] Healthcheck endpoint at `/healthz`
- [ ] Uses relative URLs (works behind the published hostname)
- [ ] README states what the app does and who requested it

---

## Template Repo Structure

```
vibe-app-template/
├── .github/workflows/deploy.yml   # CI/CD pipeline
├── src/                           # App source (pick your stack)
├── Dockerfile                     # Multi-stage build
├── docker-compose.yml             # Port-mapped; optional oauth2-proxy block
├── .env.example                   # Required env vars
└── README.md                      # App name, requester, purpose, assigned port
```

- [ ] Create `cargas-internal/vibe-app-template` on GitHub
- [ ] Starter apps for common stacks (Node, Python, Go)
- [ ] Pre-fill the host-port mapping and a commented oauth2-proxy sidecar
- [ ] Include a sample group-authorization snippet

---

## Related

- [[Server Setup Guide]] — Infrastructure, App Proxy, port registry
- [[Setup Outline]] — Full phased plan
- [[Code Collective]] — Initiative overview

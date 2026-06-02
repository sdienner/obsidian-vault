---
date: 2026-05-18
updated: 2026-06-02
tags: [project, infrastructure, technical]
status: active
---
# Publishing Guide — Deploying Apps to the Vibe Coding Server

How to build and deploy an app. Internally, apps route on `*.cargas.internal`. Externally, each app is published through Entra Application Proxy at `https://<app>-cargas.msappproxy.net` and is reachable from **any device with no VPN**, behind Entra ID single sign-on. Covers both the developer workflow and the sponsored development workflow for non-technical requests.

> **We're on App Proxy's default domain for now.** That means each app needs a one-time App Proxy publication (an admin step in Entra) and gets a `msappproxy.net` URL. See [[Server Setup Guide]] for the bootstrap-vs-custom-domain trade-off.

---

## The App Contract

Every app deployed to the vibe server must conform to this contract:

### Required

| Requirement | Detail |
|-------------|--------|
| **Dockerfile** | Builds to a single container |
| **HTTP port** | Listens on one port (default 3000, configurable) |
| **Auth via headers** | Reads `X-Forwarded-User` and `X-Forwarded-Groups` — do NOT implement your own login |
| **Healthcheck** | Expose `GET /healthz` returning 200 when healthy |

### Optional

| Feature | Detail |
|---------|--------|
| **Database** | Request a PostgreSQL database — you'll receive a `DATABASE_URL` env var |
| **Fabric sync** | Opt in to sync your database to Microsoft Fabric for reporting |

### What you get for free

- **SSO** — App Proxy pre-authenticates every external user with Entra ID before requests reach your app (no login code needed)
- **HTTPS** — App Proxy terminates TLS at the edge; Traefik handles the internal hop
- **Internal routing** — `appname.cargas.internal` just works via Docker labels
- **External access** — reachable from anywhere (no VPN) behind Entra sign-in, once an admin creates the app's App Proxy publication (a one-time step per app while we're on the default `msappproxy.net` domain)
- **Container restart** — Docker restarts your app on crash if healthcheck is configured

> **Identity headers are not automatic on the default domain.** `X-Forwarded-User` / `X-Forwarded-Groups` only appear if your app is placed behind oauth2-proxy (see [[Server Setup Guide#5 oauth2-proxy Optional — identity for apps that need it]]). Pilots that only need "any authenticated employee" access don't need it. If your app needs to know *who* the user is, flag it when scoping.

---

## ⚠️ Your App Is Internet-Facing (Behind SSO)

Once published, your app is reachable from the public internet at `https://<app>-cargas.msappproxy.net` — **after** Entra ID sign-in. No VPN required. That's the point: it's what makes these tools actually get used (a manager can glance at a dashboard from their phone). But it changes your responsibilities as an author:

- **Authorize, don't trust the network.** *Anyone* you (or the admin) assign to the publication passes the SSO gate. There is no internal network boundary protecting the data behind it. If your tool should be limited to specific people, restrict the App Proxy publication's user/group assignment — and, if the app runs behind oauth2-proxy, also check `X-Forwarded-Groups` inside your app.
- **Treat sensitive data accordingly.** Customer PII, financials, etc. warrant a stricter Conditional Access policy on the published app. Cargas has **Entra P2**, so risk-based Conditional Access (block risky sign-ins, require MFA/compliant device) is available — request it for sensitive apps when you scope the project.
- **No secrets in the front end.** Assume the URL can be hit by any assigned, authenticated employee.

---

## Creating a New App

### 1. Start from the template repo

```bash
# Clone the app template
gh repo create cargas-internal/my-app --template cargas-internal/vibe-app-template --private
git clone git@github.com:cargas-internal/my-app.git
cd my-app
```

The template includes:
- `Dockerfile` with sensible defaults
- `docker-compose.yml` with Traefik labels pre-configured
- `.github/workflows/deploy.yml` — CI/CD pipeline
- `src/` — starter app (Node/Python/Go — pick your stack)
- `README.md` — fill in what this app does

### 2. Configure your app identity

Edit `docker-compose.yml` — replace `APP_NAME` with your app's subdomain:

```yaml
services:
  app:
    build: .
    container_name: my-app
    restart: unless-stopped
    environment:
      - PORT=3000
      # If you need a database, uncomment:
      # - DATABASE_URL=postgres://my_app_user:password@postgres:5432/db_my_app
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-app.rule=Host(`my-app.cargas.internal`)"
      # Only add the oauth middleware if this app needs user/group identity headers
      # (requires oauth2-proxy — see Server Setup Guide §5). Omit for pre-auth-only pilots.
      # - "traefik.http.routers.my-app.middlewares=oauth@docker"
      - "traefik.http.services.my-app.loadbalancer.server.port=3000"

networks:
  proxy:
    external: true
```

### 3. Read auth headers in your app

Your app receives the authenticated user's identity via headers. No auth library needed.

**Node/Express example:**
```javascript
app.get("/", (req, res) => {
  const user = req.headers["x-forwarded-user"];
  const groups = (req.headers["x-forwarded-groups"] || "").split(",");
  res.json({ user, groups });
});
```

**Python/Flask example:**
```python
@app.route("/")
def index():
    user = request.headers.get("X-Forwarded-User")
    groups = request.headers.get("X-Forwarded-Groups", "").split(",")
    return {"user": user, "groups": groups}
```

> **Authorization pattern:** for anything beyond "all employees," gate on group membership. Example: `if "energy-implementation" not in groups: return 403`. The SSO gate proves *who* the user is; your app decides *what they can do*.

### 4. Request a database (if needed)

File a request (or run the provisioning script when it exists):

```sql
-- Admin runs this on the shared Postgres instance
CREATE DATABASE db_my_app;
CREATE ROLE my_app_user WITH LOGIN PASSWORD 'generated-password';
GRANT ALL PRIVILEGES ON DATABASE db_my_app TO my_app_user;
```

Add the `DATABASE_URL` to your app's environment in `docker-compose.yml`.

---

## Developer Workflow

### Local Development

```bash
# Run locally with Docker
docker compose up --build

# Or run natively (faster iteration)
cd src && npm run dev   # or python app.py, go run main.go, etc.
```

For local dev, mock the auth headers or set them manually:
```bash
curl -H "X-Forwarded-User: you@cargas.com" http://localhost:3000
```

### Deploy

```bash
# Push to GitHub
git add -A && git commit -m "Initial app" && git push

# GitHub Actions handles: build → scan → push to GHCR → deploy to VM
```

**What happens on push:**
1. GitHub Actions builds the Docker image
2. Trivy scans for vulnerabilities
3. Lints and runs tests
4. Pushes image to GitHub Container Registry
5. SSHes to the VM and runs `docker compose pull && docker compose up -d`
6. Traefik auto-discovers the new container
7. App is live **internally** at `my-app.cargas.internal`. For external access, an admin creates a one-time App Proxy publication (external `my-app-cargas.msappproxy.net` → internal `my-app.cargas.internal`) and assigns users/groups — then it's reachable from anywhere

### Manual Deploy (fallback)

If CI/CD isn't set up yet or for quick iteration:

```bash
# SSH to VM
ssh vibe-server

# Navigate to app directory
cd /data/apps/my-app

# Pull latest and restart
git pull
docker compose up -d --build
```

---

## Sponsored Development Workflow

For non-technical users who need a tool built.

### How it works

```
1. Requester describes the problem
   → Enterprise Enablement intake form (Asana)
   → or direct Teams message to Code Collective channel

2. Request lands on the project board
   → Steering committee triages (or developer self-selects)
   → Classified: quick hit (<2 hours) or structured project (multi-sprint)

3. Developer picks it up
   → Schedules during Code Collective dedicated time
   → Builds from app template
   → AI-assisted development for rapid scaffolding (optional)

4. Requester tests
   → Admin publishes the app; developer shares the URL: https://my-tool-cargas.msappproxy.net
   → Requester opens it from any device — laptop, phone, off the VPN —
     and signs in with their normal Cargas login (Entra SSO)
   → Provides feedback

5. Iterate and ship
   → Developer refines based on feedback
   → Each push auto-deploys
   → When requester is satisfied, it's done
```

> **Why "no VPN" matters here:** Fred's whole thesis is that these tools save people time and frustration. A tool that requires a VPN connection to open adds friction back. Because apps publish through App Proxy, the requester just clicks a link and signs in — same as any Microsoft 365 app.

### Quick Hits vs. Structured Projects

| | Quick Hit | Structured Project |
|-|-----------|-------------------|
| **Time** | Under 2 hours | Multi-sprint |
| **Governance** | Developer self-selects, no formal approval | Steering committee scopes and assigns |
| **Template** | Start from vibe-app-template | Start from template + architecture discussion |
| **Examples** | Jaiya's Zendesk/JIRA merge dashboard, simple lookup tools | Customer list site, fleet dashboard |

---

## CI/CD Pipeline

### GitHub Actions Workflow

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

### Required GitHub Secrets

| Secret | Value |
|--------|-------|
| `VM_HOST` | VM internal IP or hostname |
| `VM_USER` | SSH user on VM |
| `VM_SSH_KEY` | SSH private key for deployment |

Set these at the GitHub org level (`cargas-internal`) so all app repos inherit them.

---

## App Lifecycle

### Deploying a new version
Push to `main`. CI/CD handles everything.

### Rolling back
```bash
# SSH to VM
cd /data/apps/my-app
# Pin to a previous image tag (if using versioned tags)
docker compose pull
docker compose up -d
# Or revert the git commit and push again
```

### Decommissioning an app
```bash
# Stop and remove the container
cd /data/apps/my-app
docker compose down

# Remove the database (if applicable)
docker exec postgres psql -U postgres -c "DROP DATABASE db_my_app;"
docker exec postgres psql -U postgres -c "DROP ROLE my_app_user;"

# Archive the repo on GitHub
# Remove /data/apps/my-app from VM
```

> **No App Proxy cleanup needed.** Under the wildcard publication, removing the container removes the route — the subdomain stops resolving to anything and external access ends automatically. There's no per-app App Proxy publication to delete.

---

## Security Checklist for New Apps

Before deploying any app, verify:

- [ ] No hardcoded secrets (use environment variables)
- [ ] Auth headers are read, not bypassed (no public endpoints with sensitive data)
- [ ] **Authorization by `X-Forwarded-Groups`** wherever the tool isn't meant for all employees — apps are internet-reachable behind SSO, so network location is NOT a control
- [ ] Sensitive-data apps: request a scoped Conditional Access policy (Entra P2 supports risk-based / MFA / device-compliance policies)
- [ ] If using a database, parameterized queries only (no string concatenation in SQL)
- [ ] Trivy scan passes (no CRITICAL/HIGH vulnerabilities in dependencies)
- [ ] Healthcheck endpoint exists at `/healthz`
- [ ] README describes what the app does and who requested it

---

## Template Repo Structure

```
vibe-app-template/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD pipeline
├── src/
│   └── ...                     # App source (pick your stack)
├── Dockerfile                  # Multi-stage build
├── docker-compose.yml          # Traefik labels pre-configured (*.apps.cargas.com)
├── .env.example                # Document required env vars
├── .dockerignore
├── .gitignore
└── README.md                   # Template: fill in app name, requester, purpose
```

- [ ] Create `cargas-internal/vibe-app-template` repo on GitHub
- [ ] Include starter apps for common stacks (Node, Python, Go)
- [ ] Pre-configure Traefik labels, healthcheck, auth header reading
- [ ] Include a sample group-authorization snippet so authors default to checking `X-Forwarded-Groups`

---

## Related

- [[Server Setup Guide]] — Infrastructure setup for the VM and App Proxy
- [[Setup Outline]] — Full phased plan
- [[Code Collective]] — Initiative overview

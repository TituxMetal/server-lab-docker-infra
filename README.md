# Server Lab Docker Infra

A modular Docker Compose infrastructure for managing containerized services across a
lab/production server environment. Each service is self-contained with its own
`compose.yaml`, environment configuration, and documentation, making it easy to deploy
individually via the CLI or through the Portainer web interface.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Network Setup](#network-setup)
- [Quick Start](#quick-start)
- [Service Documentation](#service-documentation)
  - [Main -- Core Infrastructure](#main----core-infrastructure)
  - [Projects -- Custom Applications](#projects----custom-applications)
  - [Utils -- Utility Services](#utils----utility-services)
- [Environment Variables Reference](#environment-variables-reference)
- [Deployment Methods](#deployment-methods)
- [Automated Updates with Renovate](#automated-updates-with-renovate)
- [Common Commands](#common-commands)

## Architecture Overview

The project is organized into three layers, each serving a distinct purpose:

```
server-lab-docker-infra/
|
|-- main/                        Core infrastructure services
|   |-- dockerNetwork.sh         Creates the default bridge network
|   |-- portainer/               Container management (agent + optional server)
|   |-- nginx-proxy-manager/     Reverse proxy with SSL termination
|   |-- fail2ban/                Intrusion prevention system
|
|-- projects/                    Custom web applications
|   |-- logi-prod-report/        Production reporting tool (SQLite)
|   |-- work-journal/            Work journal application (SQLite)
|
|-- utils/                       Utility and self-hosted services
|   |-- duckdns/                 Dynamic DNS updater
|   |-- excalidraw/              Collaborative whiteboard
|   |-- flame/                   Application dashboard / start page
|   |-- lobechat/                AI chat interface (OpenAI-compatible)
|   |-- rustdesk/                Remote desktop (ID + relay servers)
|   |-- uptime-kuma/             Uptime monitoring dashboard
|
|-- renovate.json                Automated dependency update configuration
|-- .gitignore                   Excludes all .env files from version control
```

### Network Topology

```
                          Internet
                             |
                    +--------+--------+
                    |  Host Firewall  |
                    +--------+--------+
                             |
              +--------------+--------------+
              |              |              |
         80/443/81     9001/9443/8000   21115-21119
              |              |              |
   +----------+----------+  |  +-----------+-----------+
   |  reverse-proxy-nw   |  |  |     rustdesk-nw       |
   |  (external bridge)  |  |  |  (isolated bridge)    |
   |                      |  |  |                       |
   |  - NPM + main-site  |  |  |  - hbbs (ID server)   |
   |  - excalidraw       |  |  |  - hbbr (relay)       |
   |  - flame            |  |  +-----------+-----------+
   |  - lobechat         |  |              |
   |  - logi-prod-report |  |  +-----------+-----------+
   |  - work-journal     |  |  |                       |
   |  - uptime-kuma      |  |  |      default-nw       |
   |  - (portainer srv)  |  |  |  192.168.10.0/24      |
   |                      |  |  |  (internal bridge)    |
   +----------+-----------+  |  |                       |
              |              |  |  All services connect  |
              +--------------+--+  here for internal    |
                                |  communication        |
                                +-----------------------+
                                         |
                                   host network
                                   (fail2ban only)
```

## Prerequisites

- Docker Engine 20.10 or later
- Docker Compose V2 (the `docker compose` plugin)
- A Linux host with `bash` available
- Sufficient firewall rules (UFW or iptables) for exposed ports
- (Optional) A Portainer server instance for GUI-based deployment

## Network Setup

Before deploying any service, the Docker networks must be created.

### 1. Create the default bridge network

Run the provided script to create the internal communication network:

```bash
cd main/
bash dockerNetwork.sh
```

This creates the `default-nw` bridge network with the following configuration:

| Parameter | Value              |
|-----------|--------------------|
| Driver    | bridge             |
| Subnet    | 192.168.10.0/24    |
| Gateway   | 192.168.10.1       |
| IP Range  | 192.168.10.0/26    |

### 2. Create the reverse proxy network

The `reverse-proxy-nw` network is declared as `external: true` in services that need
public-facing access through Nginx Proxy Manager. Create it manually:

```bash
docker network create reverse-proxy-nw
```

### 3. RustDesk network (automatic)

The `rustdesk-nw` network is defined as a non-external network in the RustDesk compose
file and is created automatically when the RustDesk stack is deployed.

## Quick Start

### CLI Deployment

```bash
# 1. Set up networks
cd main/
bash dockerNetwork.sh
docker network create reverse-proxy-nw

# 2. Deploy core infrastructure
cd portainer/
cp example.env .env    # Edit .env with your values
docker compose up -d

cd ../nginx-proxy-manager/
docker compose up -d

cd ../fail2ban/
cp example.env .env    # Edit .env with your values
docker compose up -d

# 3. Deploy any additional service
cd ../../utils/uptime-kuma/
docker compose up -d
```

### Portainer Deployment

1. Ensure the Portainer agent (or server) is running on the target host.
2. In the Portainer web UI, navigate to **Stacks > Add stack**.
3. Paste the contents of the desired `compose.yaml` into the web editor.
4. Replace any `${HOSTNAME}` references with the actual server hostname.
5. Add each required environment variable using the **Environment variables** fields.
6. Click **Deploy the stack**.

## Service Documentation

### Main -- Core Infrastructure

#### Portainer

Container management platform deployed as an agent on each server, with an optional
server instance on a single node.

| Property       | Value                                  |
|----------------|----------------------------------------|
| Directory      | `main/portainer/`                      |
| Agent image    | `portainer/agent:alpine-sts`           |
| Server image   | `portainer/portainer-ce:alpine-sts`    |
| Restart policy | `always` (agent), `unless-stopped` (server) |

**Exposed ports:**

| Port | Service         | Purpose                    |
|------|-----------------|----------------------------|
| 9001 | Agent           | Agent communication        |
| 9443 | Server (opt.)   | HTTPS web UI               |
| 8000 | Server (opt.)   | Edge agent communication   |

**Configuration:**

```bash
cd main/portainer/
cp example.env .env
```

| Variable             | Description                           | Example            |
|----------------------|---------------------------------------|--------------------|
| `PORTAINER_HOSTNAME` | Hostname used in container naming     | `$HOSTNAME`        |
| `AGENT_SECRET`       | Shared secret for agent communication | `your_secret`      |

**Volumes:**

- `/` mounted as `/host` (read-only host filesystem access for the agent)
- `/var/run/docker.sock` (Docker socket)
- `/var/lib/docker/volumes` (volume management)
- `/srv/portainer/data` (server data, when server is enabled)

**Notes:** To enable the Portainer server, uncomment the `portainer-server` block in
`compose.yaml`. The server should only run on one node. See `NOTES.md` for firewall
requirements.

---

#### Nginx Proxy Manager

Reverse proxy with a web-based UI for managing proxy hosts, SSL certificates (Let's
Encrypt), and redirections. Includes a companion `main-site` container serving a
default landing page.

| Property       | Value                              |
|----------------|------------------------------------|
| Directory      | `main/nginx-proxy-manager/`        |
| NPM image      | `jc21/nginx-proxy-manager:2`      |
| Site image     | `lgdweb/nginx-test:latest`         |
| Restart policy | `unless-stopped`                   |

**Exposed ports:**

| Port | Purpose                          |
|------|----------------------------------|
| 80   | HTTP traffic                    |
| 443  | HTTPS traffic                   |
| 81   | NPM admin panel                 |

**Volumes:**

- `/srv/nginx-proxy-manager/data` -- NPM application data
- `/srv/logs/nginx-proxy-manager` -- NPM logs
- `/srv/nginx-proxy-manager/data/letsencrypt` -- SSL certificates

**Configuration:** No `.env` file required. Uses the system `$HOSTNAME` directly.

**Default credentials (first login):**

| Field    | Value              |
|----------|--------------------|
| Email    | admin@example.com  |
| Password | changeme           |

---

#### Fail2ban

Intrusion prevention system that monitors log files and bans IPs showing malicious
activity. Sends email notifications via SMTP.

| Property       | Value                        |
|----------------|------------------------------|
| Directory      | `main/fail2ban/`             |
| Image          | `crazymax/fail2ban:1.0.1`    |
| Network mode   | `host`                       |
| Privileged     | `true`                       |
| Restart policy | `unless-stopped`             |

**Configuration:**

```bash
cd main/fail2ban/
cp example.env .env
```

| Variable          | Description                        | Example                 |
|-------------------|------------------------------------|-------------------------|
| `HOSTNAME`        | Server hostname for container name | `homer`                 |
| `F2B_DEST_EMAIL`  | Notification recipient email       | `alerts@example.com`    |
| `SSMTP_USER`      | SMTP authentication username       | `smtp-user@example.com` |
| `SSMTP_PASSWORD`  | SMTP authentication password       | (your SMTP password)    |
| `SSMTP_HOSTNAME`  | SMTP hostname / FQDN              | `mail.example.com`      |

**Volumes:**

- `/srv/fail2ban/data` -- Fail2ban persistent data and jail configs
- `/srv/logs` -- Application logs (read/write)
- `/var/log` -- System logs (read-only)

**Capabilities:** `NET_ADMIN`, `NET_RAW` (required for iptables manipulation).

---

#### dockerNetwork.sh

Shell script to create the `default-nw` bridge network used for internal service-to-service
communication. Must be run once before deploying any stack.

```bash
bash main/dockerNetwork.sh
```

---

### Projects -- Custom Applications

#### Logi Prod Report

Production reporting web application with a SQLite database backend.

| Property       | Value                            |
|----------------|----------------------------------|
| Directory      | `projects/logi-prod-report/`     |
| Image          | `lgdweb/logi-prod-report:latest` |
| Restart policy | `unless-stopped`                 |

**Configuration:**

```bash
cd projects/logi-prod-report/
cp example.env .env
```

| Variable               | Description                           | Example                                          |
|------------------------|---------------------------------------|--------------------------------------------------|
| `DATABASE_URL`         | SQLite connection string              | `file:./data.sqlite?connection_limit=1`          |
| `AUTH_SESSION_SECRET`  | Secret key for session signing        | (random string)                                  |
| `AUTH_SESSION_MAX_AGE` | Session duration in seconds           | `1800` (30 minutes)                              |

**Volumes:**

- Named volume `data` mounted at `/data` for SQLite persistence

**Networks:** `reverse-proxy-nw` (external access via NPM), `default-nw` (internal).

---

#### Work Journal

Work journal web application with a SQLite database backend and admin authentication.

| Property       | Value                          |
|----------------|--------------------------------|
| Directory      | `projects/work-journal/`       |
| Image          | `lgdweb/work-journal:latest`   |
| Restart policy | `unless-stopped`               |

**Configuration:**

```bash
cd projects/work-journal/
cp example.env .env
```

| Variable          | Description                    | Example                                 |
|-------------------|--------------------------------|-----------------------------------------|
| `DATABASE_URL`    | SQLite connection string       | `file:./data.sqlite?connection_limit=1` |
| `SESSION_SECRET`  | Secret key for session signing | (random string)                         |
| `ADMIN_PASSWORD`  | Admin login password           | (strong password)                       |

**Volumes:**

- Named volume `data` mounted at `/data` for SQLite persistence

**Networks:** `reverse-proxy-nw` (external access via NPM), `default-nw` (internal).

---

### Utils -- Utility Services

#### DuckDNS

Dynamic DNS client that periodically updates a DuckDNS subdomain with the server's
current public IPv4 address.

| Property       | Value                    |
|----------------|--------------------------|
| Directory      | `utils/duckdns/`         |
| Image          | `linuxserver/duckdns`    |
| Restart policy | `unless-stopped`         |

**Configuration:** Create a `.env` file in `utils/duckdns/`:

| Variable     | Description                          | Example       |
|--------------|--------------------------------------|---------------|
| `SUBDOMAINS` | DuckDNS subdomain(s) to update       | `mysubdomain` |
| `TOKEN`      | DuckDNS account token                | (your token)  |

**Networks:** `default-nw` only (no external access needed).

---

#### Excalidraw

Self-hosted collaborative whiteboard for sketching diagrams and wireframes.

| Property       | Value                           |
|----------------|---------------------------------|
| Directory      | `utils/excalidraw/`             |
| Image          | `excalidraw/excalidraw:latest`  |
| Restart policy | `unless-stopped`                |

**Exposed ports:**

| Port | Purpose          |
|------|------------------|
| 5000 | Web UI           |

**Configuration:** No `.env` file required. Uses the system `$HOSTNAME` for container naming.

**Networks:** `reverse-proxy-nw` (external access via NPM), `default-nw` (internal).

---

#### Flame

Self-hosted application dashboard and start page with Docker integration for automatic
service discovery.

| Property       | Value                  |
|----------------|------------------------|
| Directory      | `utils/flame/`         |
| Image          | `pawelmalak/flame`     |
| Restart policy | `unless-stopped`       |

**Configuration:** Create a `.env` file in `utils/flame/`:

| Variable   | Description                  | Example            |
|------------|------------------------------|--------------------|
| `PASSWORD` | Dashboard login password     | (strong password)  |

**Volumes:**

- Named volume `data` mounted at `/app/data`
- `/var/run/docker.sock` for Docker container discovery

**Networks:** `reverse-proxy-nw` only (accessed through NPM).

---

#### LobeChat

Self-hosted AI chat interface compatible with OpenAI and other LLM providers.

| Property       | Value                  |
|----------------|------------------------|
| Directory      | `utils/lobechat/`      |
| Image          | `lobehub/lobe-chat`    |
| Restart policy | `unless-stopped`       |

**Configuration:** Create a `.env` file in `utils/lobechat/`:

| Variable           | Description                        | Example                     |
|--------------------|------------------------------------|-----------------------------|
| `ACCESS_CODE`      | Access code to protect the UI      | (strong passphrase)         |
| `OPENAI_API_KEY`   | OpenAI API key                     | `sk-proj-...`               |
| `OPENAI_PROXY_URL` | Proxy URL for OpenAI API (set in compose) | `https://api-proxy.com/v1` |

**Networks:** `reverse-proxy-nw` (external access via NPM), `default-nw` (internal).

---

#### RustDesk

Self-hosted remote desktop solution with an ID server and a relay server running as
separate containers on an isolated network.

| Property       | Value                              |
|----------------|------------------------------------|
| Directory      | `utils/rustdesk/`                  |
| Image          | `rustdesk/rustdesk-server:latest`  |
| Restart policy | `unless-stopped`                   |

**Exposed ports:**

| Port  | Protocol | Service | Purpose                  |
|-------|----------|---------|--------------------------|
| 21115 | TCP      | hbbs    | NAT type test            |
| 21116 | TCP/UDP  | hbbs    | ID server / hole punch   |
| 21117 | TCP      | hbbr    | Relay server             |
| 21118 | TCP      | hbbs    | WebSocket (ID)           |
| 21119 | TCP      | hbbr    | WebSocket (relay)        |

**Configuration:** No `.env` variables required. The relay address is derived from
`$HOSTNAME` in the `hbbs` command: `hbbs -r rustdesk.${HOSTNAME}.lgdweb.ovh:21117`.

**Volumes:**

- Shared named volume `data` mounted at `/root` for both containers (stores keys and
  configuration)

**Networks:** `rustdesk-nw` (isolated bridge, auto-created), `default-nw` (internal).

---

#### Uptime Kuma

Self-hosted uptime monitoring tool with support for HTTP(S), TCP, DNS, Docker, and
other check types. Provides a status page and notifications.

| Property       | Value                      |
|----------------|----------------------------|
| Directory      | `utils/uptime-kuma/`       |
| Image          | `louislam/uptime-kuma:1`   |
| Restart policy | `always`                   |

**Exposed ports:**

| Port | Binding        | Purpose        |
|------|----------------|----------------|
| 3001 | 127.0.0.1 only | Web UI         |

The port is bound to localhost only. Use Nginx Proxy Manager to expose it externally
with SSL.

**Volumes:**

- Named volume `data` mounted at `/app/data`
- `/var/run/docker.sock` for Docker container monitoring

**Networks:** `reverse-proxy-nw` (external access via NPM), `default-nw` (internal).

---

## Environment Variables Reference

All `.env` files are excluded from version control via `.gitignore`. Each service that
requires environment variables provides an `example.env` file as a template.

### Core Infrastructure

| Service    | Variable             | Required | Description                        |
|------------|----------------------|----------|------------------------------------|
| Portainer  | `PORTAINER_HOSTNAME` | Yes      | Hostname for container naming      |
| Portainer  | `AGENT_SECRET`       | Yes      | Shared secret for agent auth       |
| Fail2ban   | `HOSTNAME`           | Yes      | Server hostname                    |
| Fail2ban   | `F2B_DEST_EMAIL`     | Yes      | Alert notification email           |
| Fail2ban   | `SSMTP_USER`         | Yes      | SMTP username                      |
| Fail2ban   | `SSMTP_PASSWORD`     | Yes      | SMTP password                      |
| Fail2ban   | `SSMTP_HOSTNAME`     | Yes      | SMTP server FQDN                   |

### Custom Applications

| Service          | Variable               | Required | Description                 |
|------------------|------------------------|----------|-----------------------------|
| Logi Prod Report | `DATABASE_URL`         | Yes      | SQLite connection string    |
| Logi Prod Report | `AUTH_SESSION_SECRET`  | Yes      | Session signing secret      |
| Logi Prod Report | `AUTH_SESSION_MAX_AGE` | No       | Session TTL in seconds      |
| Work Journal     | `DATABASE_URL`         | Yes      | SQLite connection string    |
| Work Journal     | `SESSION_SECRET`       | Yes      | Session signing secret      |
| Work Journal     | `ADMIN_PASSWORD`       | Yes      | Admin login password        |

### Utility Services

| Service   | Variable           | Required | Description                      |
|-----------|--------------------|----------|----------------------------------|
| DuckDNS   | `SUBDOMAINS`       | Yes      | DuckDNS subdomain(s)            |
| DuckDNS   | `TOKEN`            | Yes      | DuckDNS account token            |
| Flame     | `PASSWORD`         | Yes      | Dashboard login password         |
| LobeChat  | `ACCESS_CODE`      | Yes      | UI access protection code        |
| LobeChat  | `OPENAI_API_KEY`   | Yes      | OpenAI API key                   |

## Deployment Methods

### Method 1: Docker Compose CLI

Recommended for automated or scripted deployments.

```bash
# Navigate to the service directory
cd <layer>/<service>/

# Create the environment file from the template (if example.env exists)
cp example.env .env

# Edit the environment variables
nano .env

# Deploy the stack
docker compose up -d

# Verify the containers are running
docker compose ps
```

### Method 2: Portainer GUI

Recommended for manual deployments and visual management.

1. Open the Portainer web UI (default: `https://<server>:9443`).
2. Select the target environment (endpoint).
3. Navigate to **Stacks** and click **Add stack**.
4. Give the stack a name matching the service.
5. Paste the `compose.yaml` content into the **Web editor**.
6. Replace all `${HOSTNAME}` occurrences with the actual server hostname.
7. Under **Environment variables**, add each required variable with its name and value.
8. Click **Deploy the stack**.

To update a stack in Portainer, navigate to the stack, click **Editor**, make changes,
and click **Update the stack**.

## Automated Updates with Renovate

This repository uses [Renovate](https://docs.renovatebot.com/) to keep Docker image
versions up to date. The configuration is in `renovate.json`.

| Setting                   | Value                                                           |
|---------------------------|-----------------------------------------------------------------|
| Base config               | `config:recommended`                                            |
| Assignee                  | `TituxMetal`                                                    |
| Auto-merge                | Minor, patch, and digest updates                                |
| Auto-merge strategy       | Branch (no PR created for auto-merged updates)                  |
| Dependency dashboard      | Enabled (auto-closes when all updates are applied)              |
| Schedule                  | Weekdays 10 PM -- 5 AM, all day on weekends                    |

Major version updates require manual review and are not auto-merged.

## Common Commands

### Stack Management

```bash
# Start a stack in detached mode
docker compose up -d

# Stop and remove a stack
docker compose down

# Restart a specific service
docker compose restart <service-name>

# View logs (follow mode)
docker compose logs -f

# View logs for a specific service
docker compose logs -f <service-name>

# Pull latest images and recreate containers
docker compose pull && docker compose up -d
```

### Network Management

```bash
# Create the default internal network
bash main/dockerNetwork.sh

# Create the reverse proxy network
docker network create reverse-proxy-nw

# List all Docker networks
docker network ls

# Inspect a network
docker network inspect default-nw
```

### Monitoring and Troubleshooting

```bash
# List all running containers
docker ps

# Inspect a container
docker inspect <container-name>

# Execute a command inside a running container
docker exec -it <container-name> /bin/sh

# Check resource usage
docker stats

# View container logs directly
docker logs -f <container-name>
```

### Image Maintenance

```bash
# Remove unused images
docker image prune -a

# Remove all stopped containers
docker container prune

# Full system cleanup (use with caution)
docker system prune -a --volumes
```

---

**Timezone:** All services are configured with `TZ=Europe/Paris` and mount
`/etc/localtime` and `/etc/timezone` from the host for consistent time handling.

**Security:** All `.env` files are excluded from version control. Never commit
credentials or secrets. Use `example.env` files as templates and create local `.env`
copies with actual values.

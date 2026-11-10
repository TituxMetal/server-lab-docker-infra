# Server Lab Docker Infra

A modular Docker Compose infrastructure for managing containerized services across a
lab/production server environment. Each service is self-contained with its own
`compose.yaml`, environment configuration, and documentation, making it easy to deploy
individually via the CLI or through the Arcane web interface.

**Fallback repository.** The managed fleet is provisioned by Ansible, which is the
source of truth for the system, Docker, NPM, fail2ban and Arcane. This repository is
kept as a **standalone fallback**: it mounts a server without Ansible, or repairs one
that is already broken. It is not amputated when a service moves to Ansible — only
kept in sync.

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
|   |-- arcane/                  Container management (manager, no published port)
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
|   |-- plausible/               Privacy-friendly web analytics (Plausible CE)
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
         80/443/81     21115-21119
              |              |
   +----------+----------+  +-----------+-----------+
   |  reverse-proxy-nw   |  |     rustdesk-nw       |
   |  (external bridge)  |  |  (isolated bridge)    |
   |                      |  |                       |
   |  - NPM + main-site  |  |  - hbbs (ID server)   |
   |  - excalidraw       |  |  - hbbr (relay)       |
   |  - plausible        |  +-----------+-----------+
   |  - lobechat         |              |
   |  - logi-prod-report |  +-----------+-----------+
   |  - work-journal     |  |                       |
   |  - uptime-kuma      |  |      default-nw       |
   |  - arcane manager   |  |  192.168.10.0/24      |
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
- (Optional) An Arcane manager to deploy and manage the stacks from a web UI

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
cd arcane/
cp example.env .env    # Edit .env with your values (APP_URL, keys)
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

### Arcane Deployment

1. Ensure the Arcane agent is running on the target host and appears in the manager.
2. In the Arcane web UI, create a project from the git repository (or paste the
   `compose.yaml`).
3. Set the environment variables from the service's `example.env`.
4. Deploy.

## Service Documentation

### Main -- Core Infrastructure

#### Arcane

Container management platform. The manager runs on a single node and publishes no
port: it is reached through Nginx Proxy Manager, or an SSH tunnel. Agents are deployed
per host, not from this directory. Ansible is the source of truth on the managed
fleet; this stack is the standalone fallback.

| Property       | Value                          |
|----------------|--------------------------------|
| Directory      | `main/arcane/`                 |
| Image          | `ghcr.io/getarcaneapp/manager:v2.17.3` |
| Restart policy | `unless-stopped`               |

**Exposed ports:** none. Proxy host -> `arcane-manager-<instance>:3552` (WebSocket
enabled). `3553` is the agent port, not the manager.

**Configuration:**

```bash
cd main/arcane/
cp example.env .env
```

| Variable                | Description                                                   | Example                    |
|-------------------------|---------------------------------------------------------------|----------------------------|
| `ARCANE_INSTANCE`       | Hostname used in the container name                           | `$HOSTNAME`                |
| `ARCANE_VERSION`        | Pinned manager image tag                                      | `v2.17.3`                  |
| `APP_URL`               | Public URL of the manager                                     | `https://arcane.example.com` |
| `ENCRYPTION_KEY`        | `openssl rand -hex 32`. **Never change it once data exists**  | (random)                   |
| `ADMIN_STATIC_API_KEY`  | `arc_` + 64 hex, any other format is rejected at startup      | `arc_...`                  |
| `TRUSTED_PROXIES`       | CIDR of the reverse proxy network                             | `192.168.10.0/26`          |

**Volumes:** `/var/run/docker.sock`, named volume `arcane-manager-data` mounted at
`/app/data`.

**Notes:** see `NOTES.md`. Use an SSH tunnel for the NPM admin panel; a proxy host
pointing at port `81` would expose it publicly even though Docker binds it to
`127.0.0.1`.

---

#### Nginx Proxy Manager

Reverse proxy with a web-based UI for managing proxy hosts, SSL certificates (Let's
Encrypt), and redirections. Includes a companion `main-site` container serving a
default landing page.

| Property       | Value                              |
|----------------|------------------------------------|
| Directory      | `main/nginx-proxy-manager/`        |
| NPM image      | `jc21/nginx-proxy-manager:2.16.0`  |
| Site image     | `lgdweb/nginx-test:latest`         |
| Restart policy | `unless-stopped`                   |

**Exposed ports:**

| Port | Binding        | Purpose                          |
|------|----------------|----------------------------------|
| 80   | all            | HTTP traffic                     |
| 443  | all            | HTTPS traffic                    |
| 81   | `127.0.0.1`    | NPM admin panel (SSH tunnel)     |

> The admin panel listens on `0.0.0.0:81` **inside** the container: a proxy host
> forwarding to port 81 would republish it through 80/443 despite the loopback
> binding. Use an SSH tunnel (`ssh -N -L 8181:127.0.0.1:81 <host>`).

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
| Image          | `crazymax/fail2ban:1.1.1`    |
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
| `SMTP_USER`       | SMTP authentication username       | `smtp-user@example.com` |
| `SMTP_PASSWORD`   | SMTP authentication password       | (your SMTP password)    |

`destemail`/`sender` are not environment variables: the image entrypoint never
read `F2B_DEST_EMAIL`. They live in `fail2ban/data/jail.d/default.conf`.

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

#### Plausible Analytics

Privacy-friendly, self-hosted web analytics platform (Plausible Community Edition).
Composed of three services: the Plausible app, a PostgreSQL database, and a ClickHouse
events database.

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Directory      | `utils/plausible/`                             |
| Image          | `ghcr.io/plausible/community-edition:v3.2.0`  |
| Dependencies   | PostgreSQL 16, ClickHouse 24.12                |
| Restart policy | `always`                                       |

**Configuration:** Create a `.env` file in `utils/plausible/` (see `example.env`):

| Variable             | Required | Description                             |
|----------------------|----------|-----------------------------------------|
| `BASE_URL`           | Yes      | Public URL (e.g. `https://analytics.example.com`) |
| `SECRET_KEY_BASE`    | Yes      | 64-char random secret for session encryption      |
| `DISABLE_REGISTRATION` | No    | Set to `invite_only` after first signup           |
| `SMTP_HOST_ADDR`     | No       | SMTP server for email notifications               |

**Volumes:**

- `db-data` — PostgreSQL data
- `event-data` — ClickHouse analytics data (can be very large, 20GB+)
- `event-logs` — ClickHouse logs, rotated at 100 MB x 5 by `clickhouse/logs.xml`
- `plausible-data` — Plausible app data
- `clickhouse/` config files mounted read-only (logs, IPv4, low-resources tuning)

Container logs are capped at 10 MB x 3 for all three services. Host-level log
rotation and `event-data` retention are **not** solved here.

**Networks:** `reverse-proxy-nw` (external access via NPM), `default-nw` (internal).

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
| Directory      | `utils/rustdesk/`                 |
| Image          | `rustdesk/rustdesk-server:1.1.16` |
| Restart policy | `unless-stopped`                  |

**Exposed ports:**

| Port  | Protocol | Service | Purpose                  |
|-------|----------|---------|--------------------------|
| 21115 | TCP      | hbbs    | NAT type test            |
| 21116 | TCP/UDP  | hbbs    | ID server / hole punch   |
| 21117 | TCP      | hbbr    | Relay server             |
| 21118 | TCP      | hbbs    | WebSocket (ID)           |
| 21119 | TCP      | hbbr    | WebSocket (relay)        |

**Configuration:** create `.env` from `example.env`:

| Variable              | Description                                                     | Example               |
|-----------------------|-----------------------------------------------------------------|-----------------------|
| `RUSTDESK_INSTANCE`   | Suffix of the container names                                   | `laura`               |
| `RUSTDESK_RELAY_HOST` | Hostname announced to clients for the relay (port 21117)        | `laura.lgdweb.ovh`    |
| `RUSTDESK_KEY`        | **Public** key, already present in every deployed client        | `Qrr...db8=`          |

Two rules that are not optional:

1. **`RUSTDESK_RELAY_HOST` is a stable client-facing name, not the hostname of the
   machine running the service.** It is what makes a migration transparent: the
   record is repointed to the new host and nothing changes on the clients.
2. **The private key must already be in the volume before the first start.**
   `hbbs` signs the peer public keys with `id_ed25519`; without it a new pair is
   generated and every client fails to connect. Seed `rustdesk-data` first.

Never pass the **public** key as `hbbs -k <key>`: `hbbs` then skips `id_ed25519`
entirely and runs without a signing key. `-k` is used on `hbbr` only, as an opaque
string that relay requests must carry.

> **Firewall note:** open `21116` TCP **and** UDP and `21117` TCP (`21115`, `21118`,
> `21119` only for the web client) on the provider firewall. Docker-published ports
> bypass `ufw`: the provider firewall is the real gate. This service is not managed by
> Ansible — it is deployed manually via Arcane or Docker Compose on the target server.

**Volumes:**

- Named volume `rustdesk-data` (fixed `name:`, not prefixed by the compose project),
  mounted at `/root` on both containers. It stores the key pair and the peer database.

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
| Arcane     | `ARCANE_INSTANCE`    | Yes      | Hostname for container naming      |
| Arcane     | `APP_URL`            | Yes      | Public URL of the manager          |
| Arcane     | `ENCRYPTION_KEY`     | Yes      | Never change once data exists      |
| Arcane     | `ADMIN_STATIC_API_KEY` | Yes    | `arc_` + 64 hex                    |
| Fail2ban   | `HOSTNAME`           | Yes      | Server hostname                    |
| Fail2ban   | `SMTP_USER`          | Yes      | SMTP username (msmtpd)             |
| Fail2ban   | `SMTP_PASSWORD`      | Yes      | SMTP password (msmtpd)             |

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
| Plausible | `BASE_URL`         | Yes      | Public URL for the analytics instance |
| Plausible | `SECRET_KEY_BASE`  | Yes      | 64-char secret for session encryption |
| LobeChat  | `ACCESS_CODE`      | Yes      | UI access protection code        |
| LobeChat  | `OPENAI_API_KEY`   | Yes      | OpenAI API key                   |
| RustDesk  | `RUSTDESK_INSTANCE` | Yes     | Container name suffix            |
| RustDesk  | `RUSTDESK_RELAY_HOST` | Yes   | Client-facing relay hostname     |
| RustDesk  | `RUSTDESK_KEY`     | Yes      | Public key (relay authentication) |

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

### Method 2: Arcane GUI

Recommended for manual deployments and visual management.

1. Open the Arcane manager (`https://<manager host>`).
2. Select the target environment.
3. Create a project, either from a git repository or by pasting the compose file.
4. Set the environment variables from `example.env` in the project.
5. Deploy.

To update a project, change the compose file or the variables and redeploy. A git
project can also be imported once instead of being synced continuously.

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

# Arcane

The manager listens on `3552` inside `default-nw` and publishes **no port**: it
is reachable through Nginx Proxy Manager only (proxy host -> `arcane-manager-<instance>:3552`,
**not** `3553`, which is the agent). Enable WebSocket on the proxy host.

Agents listen on `3553` and talk outbound to the manager; they are deployed per
host, not from this directory.

Firewall: nothing to open on the host. Do not proxy port `81` (NPM admin) — use
an SSH tunnel, the container listens on `0.0.0.0:81` internally.

Ansible is the source of truth on the managed fleet; this compose file is the
standalone fallback.

No agent in this compose, on purpose: the manager mounts the local Docker socket
and manages its own host directly, and an agent needs an `AGENT_TOKEN` fetched
from the API at runtime, which a static compose file cannot provide. Ansible does
deploy an agent on every host it manages, master included — a different topology
that this file does not try to reproduce.

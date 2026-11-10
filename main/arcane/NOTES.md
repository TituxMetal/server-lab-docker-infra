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

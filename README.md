# Server Lab Docker Infra

Infrastructure for Lgdweb Lab on a five nodes Docker Swarm.

## Pre-Requisites

- Five vps servers from Ovh Cloud (or other)
- Latest version of Debian (Bullseye) installed on each server
- Docker installed on each server
- Ssh access with a dedicated admin user
- A main domain name pointing to the main server
- At least five sub-domains, pointing to each server

## Deployement

Define a name for each server and point to the respective ip address. Choose two servers as
'managers', but only one will be the 'leader'. It is on this 'leader' that we will connect in ssh
and initialize the swarm.

### Portainer Server + Agent

Portainer is the most popular container management platform. The server will be deployed on one
manager node and agents on each five nodes.

Create an external network for reverse proxy:

```
  docker network create --scope swarm --driver overlay --attachable reverse-proxy-nw
```

Create a workspace folder for storing all containers important data and custom config. I choose to
create a /srv folder for my workspace, in this folder I create another folder named portainer-stack.

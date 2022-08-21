# Server Lab Docker Infra

Infrastructure for Lgdweb Lab on a five nodes Docker Swarm.

## Pre-Requisites

- Five vps servers from Ovh Cloud (or other)
- Latest version of Debian (Bullseye) installed on each server
- Docker installed on each server
- Ssh access with a dedicated admin user
- A main domain name pointing to the main server
- At least five sub-domains, pointing to each server

## Services

### Portainer Server + Agent

Portainer is the most popular container management platform. The server will be deployed on one
manager node and agents on each five nodes.

# Docker Swarm Platform

This folder contains the Swarm-oriented deployment path for the platform.

## What this profile does

- Installs Docker Engine and enables Swarm mode.
- Bootstraps `swarm-cd` for Git-driven stack updates.
- Deploys Swarm stacks for databases, Gitea, Kong, logging, monitoring, and Trivy.

## Important difference from Kubernetes

- Longhorn is Kubernetes-only. The Swarm profile uses host-path volumes under `/srv/swarm` instead of Longhorn StorageClasses.
- Harbor is not a first-class Swarm controller in this repo yet. The Swarm path currently gives you the Docker-native registry/CD/runtime pieces and leaves a full Harbor bundle as a follow-up if you want the upstream Harbor compose release wired in.

## Run

```powershell
ansible-playbook -i inventory/swarm_hosts.yml site-swarm.yml
```

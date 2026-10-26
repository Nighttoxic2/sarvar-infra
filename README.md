# Sarvar Home Infrastructure

Production-grade home infrastructure running 20+ containerized services with zero public exposure, automated monitoring, and 3-2-1 disaster recovery.

## 🏗️ Architecture Overview

```
Internet → Router (DDNS) → Nginx Proxy Manager (TLS) → LAN Services (LAN_IP)
                                    ↓
                            Tailscale VPN → Remote Admin
                                    ↓
                            Docker Networks (DOCKER_CIDR)
```

**Hardware:** Intel i7-7700HQ | GTX 1050 Ti 4GB | 16GB RAM | 256GB NVMe + 931GB HDD  
**OS:** Ubuntu Server 24.04 LTS

## 📦 Services

| Category | Services |
|----------|----------|
| **Reverse Proxy** | Nginx Proxy Manager (SSL termination, routing) |
| **Photos** | Immich v3.3.5 (ML search, faces, QuickSync transcoding) |
| **Media** | Jellyfin (streaming), *Arr stack (Prowlarr, Sonarr, Radarr, Lidarr, Bazarr) |
| **Downloads** | qBittorrent, FlareSolverr |
| **Identity** | Vaultwarden (password manager), Tailscale (VPN) |
| **Automation** | n8n (workflows), Pi-hole (DNS/ad-block) |
| **Monitoring** | Custom healthchecks, Watchtower (auto-updates) |
| **Game Server** | Project Zomboid B42 (dedicated, 80+ mods) |

## 🔒 Security Posture

- **Zero public exposure** — all services bind to LAN IP only
- **Default-deny firewall** — UFW with explicit CIDR allows (LAN, Docker, Tailscale)
- **Fail2Ban** — SSH, Nginx, application auth jails
- **Non-root containers** — PUID/PGID=1000, read-only rootfs where supported
- **Resource limits** — CPU/memory on all containers
- **Healthchecks** — All critical services
- **Secrets** — Docker secrets / `.env` (gitignored)

## 📁 Repository Structure

```
sarvar-infra/
├── docker/
│   ├── docker-compose.yml          # Full service stack
│   ├── .env.example                # Template (no secrets)
│   └── hwaccel.transcoding.yml     # Intel QuickSync config
├── backup/
│   └── backup.sh                   # 3-2-1 pg_dump + rclone to B2
├── monitoring/
│   └── healthcheck.sh              # Container/restart/disk/memory/SSH alerts
├── hardening/
│   ├── ufw-rules.sh                # Default-deny firewall rules
│   └── fail2ban-jails.local        # Fail2Ban configuration
└── docs/
    ├── architecture.md             # Full architecture documentation
    ├── backup-restore-procedure.md # Tested DR runbook
    └── incident-postmortem-immich-crashloop.md # SEV-2 postmortem
```

## 🚀 Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/Nighttoxic2/sarvar-infra.git
cd sarvar-infra
cp docker/.env.example docker/.env
# Edit docker/.env with your values

# 2. Deploy
cd docker
docker compose up -d

# 3. Verify
./monitoring/healthcheck.sh
```

## 📋 Key Documentation

- **[Architecture](docs/architecture.md)** — Network topology, service matrix, security model, capacity planning
- **[Backup & Restore](docs/backup-restore-procedure.md)** — Tested quarterly DR procedure
- **[Incident Postmortem](docs/incident-postmortem-immich-crashloop.md)** — 12,425 restart root cause analysis

## 🛡️ Security Notes

This repository contains **configuration templates only**. All secrets (passwords, API keys, tokens) are stored in `.env` files that are **gitignored** and never committed.

Operational details (internal CIDRs, DDNS hostname, Tailscale IP) are included for portfolio demonstration. In production, these would be parameterized.

## 📄 License

MIT — Use as reference for your own infrastructure.

# Sarvar Home SOC Architecture

## Overview
Production-grade home infrastructure running 20+ containerized services with zero public exposure, automated monitoring, and 3-2-1 disaster recovery.

---

## Network Topology

```
Internet
    │
    ▼
┌─────────────────────────────────────┐
│  ASUS Router (ROUTER_IP)         │
│  DDNS: YOUR_DDNS_DOMAIN       │
│  Port Forwards: 80, 443 → Sarvar    │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  Sarvar (LAN_IP)            │
│  i7-7700HQ / GTX 1050 Ti / 16GB RAM │
│  256GB NVMe + 931GB HDD             │
│  Ubuntu Server 24.04 LTS            │
└─────────────────────────────────────┘
    │
    ├── Tailscale (TAILSCALE_IP) ──► Remote Admin
    ├── Docker Networks (DOCKER_CIDR)
    │   ├── immich-net
    │   ├── media-net
    │   ├── arr-net
    │   └── proxy-net
    └── LAN Services (LAN_IP:port)
```

---

## Service Matrix

| Service | Port | Network | Purpose |
|---------|------|---------|---------|
| **Reverse Proxy** | | | |
| Nginx Proxy Manager | 80, 443, 81 | LAN + Tailscale | SSL termination, routing |
| **Identity & Access** | | | |
| Vaultwarden | 8083 | LAN | Password manager |
| Tailscale | - | TAILSCALE_CIDR | Zero-trust VPN |
| **Media** | | | |
| Jellyfin | 8096 | LAN | Media streaming |
| Immich | 2283 | LAN + Tailscale | Photos + ML search |
| **Automation (*Arr)** | | | |
| Prowlarr | 9696 | LAN | Indexer manager |
| Sonarr | 8989 | LAN | TV automation |
| Radarr | 7878 | LAN | Movie automation |
| Lidarr | 8686 | LAN | Music automation |
| Bazarr | 6767 | LAN | Subtitles |
| **Downloads** | | | |
| qBittorrent | 6881, 8082 | LAN | Torrent client |
| FlareSolverr | 8181 | LAN | Cloudflare bypass |
| **Monitoring & Utils** | | | |
| Seerr | 5055 | LAN | Media requests |
| n8n | 5678 | LAN | Workflow automation |
| Pi-hole | 53, 8081 | LAN + Tailscale | DNS + ad blocking |
| Watchtower | - | - | Auto-updates |
| **Game Server** | | | |
| Project Zomboid | 16261, 16262, 27015 | LAN + WAN (Steam) | Dedicated game server |

---

## Security Architecture

### Zero-Trust Network Segmentation
```
┌─────────────────────────────────────────────────────────────┐
│                    INTERNET (UNTRUSTED)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  ASUS ROUTER — Port Forwards: 80, 443 only                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  NGINX PROXY MANAGER (DMZ)                                   │
│  - Terminates TLS (Let's Encrypt)                            │
│  - Routes to internal services by hostname                   │
│  - Access lists per service (LAN/Tailscale/IP)               │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│    LAN ZONE     │ │  TAILSCALE ZONE │ │  DOCKER ZONE    │
│  LAN_CIDR│ │  TAILSCALE_CIDR  │ │  DOCKER_CIDR  │
│                 │ │                 │ │                 │
│ • Jellyfin      │ │ • Immich        │ │ • Inter-service │
│ • *Arr Stack    │ │ • Pi-hole Admin │ │   communication │
│ • qBittorrent   │ │ • Stirling PDF  │ │ • Databases     │
│ • Vaultwarden   │ │ • Sarvar API    │ │ • Redis         │
│ • Seerr, n8n    │ │                 │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### Firewall Policy (UFW)
- **Default:** Deny incoming, Allow outgoing, Deny routed
- **Explicit allow** per service per CIDR (LAN, Docker, Tailscale)
- **No service binds to 0.0.0.0** — all bind to `LAN_IP`

### Container Hardening
- Non-root users (PUID/PGID=1000)
- Read-only root filesystem where supported
- No privileged containers
- Resource limits (CPU, memory) on all containers
- Healthchecks on all critical services
- Secrets via Docker secrets / .env (gitignored)

---

## Storage Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    256GB NVMe (OS)                           │
│  / (root), /home, /var/lib/docker, /tmp                      │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                    931GB HDD (Data)                          │
│  /mnt/Data/                                                  │
│  ├── immich/                                                 │
│  │   ├── upload/           (36GB originals)                  │
│  │   ├── library/          (9.4GB organized)                 │
│  │   ├── thumbs/           (1.4GB)                           │
│  │   ├── encoded-video/   (2.6GB)                            │
│  │   └── backups/         (3 DB dumps)                       │
│  ├── media/              (Movies, TV, Music)                 │
│  ├── config/             (All service configs)               │
│  ├── downloads/          (qBittorrent)                       │
│  └── backups/            (System backups)                    │
└──────────────────────────────────────────────────────────────┘
```

---

## Backup Strategy (3-2-1)

| Data | Frequency | Local | Offsite | Retention |
|------|-----------|-------|---------|-----------|
| PostgreSQL (Immich) | Daily 02:00 | ✅ NVMe | ✅ Backblaze B2 | 30d / 90d |
| Immich Uploads | Daily 03:00 | ✅ HDD | ✅ Backblaze B2 | 90d |
| Service Configs | On change | ✅ HDD | ✅ GitHub (private) | Indefinite |
| System Config | Weekly | ✅ HDD | ✅ Backblaze B2 | 4 weeks |

**Test Restore:** Quarterly (documented in runbook)

---

## Hardware Acceleration

| Workload | Hardware | Config |
|----------|----------|--------|
| Video Transcoding | Intel HD 630 (QuickSync) | VAAPI via `/dev/dri/renderD128` |
| ML Inference | CPU (i7-7700HQ, 8 threads) | SigLIP model, 6GB RAM limit |
| *Not Used* | GTX 1050 Ti (4GB) | Insufficient VRAM for ML |

---

## Monitoring & Alerting

| Component | Tool | Alert Channel |
|-----------|------|---------------|
| Container Health | Custom `healthcheck.sh` (cron 5min) | Discord/Telegram webhook |
| Disk Usage | `healthcheck.sh` | Webhook |
| Memory Usage | `healthcheck.sh` | Webhook |
| Failed SSH | `healthcheck.sh` + fail2ban | Webhook + email |
| Backup Success | `backup.sh` exit code | Webhook |
| Service Uptime | Watchtower + custom | Webhook |

---

## Incident Response

| Severity | Response Time | Escalation |
|----------|---------------|------------|
| SEV-1 (Data loss, total outage) | 15 min | Immediate |
| SEV-2 (Core service degraded) | 1 hour | 2 hours |
| SEV-3 (Non-critical service) | 4 hours | Next business day |

**Runbooks:** `docs/incident-postmortem-*.md`, `backup/restore-procedure.md`

---

## Capacity Planning

| Resource | Current | Headroom | Action at 80% |
|----------|---------|----------|---------------|
| NVMe (256GB) | 45% | 55% | Add 1TB NVMe |
| HDD (931GB) | 68% | 32% | Add 4TB HDD |
| RAM (16GB) | 72% | 28% | Upgrade to 32GB |
| CPU (8 threads) | 35% avg | 65% | - |

---

## Disaster Recovery

### RTO / RPO Targets
| Service | RTO | RPO |
|---------|-----|-----|
| Immich (photos) | 2 hours | 24 hours |
| Jellyfin (media) | 4 hours | 1 week |
| *Arr Stack | 1 hour | 1 hour |
| Vaultwarden | 30 min | 1 hour |
| PZ Server | 30 min | 0 (live world) |

### Recovery Procedure
1. Provision fresh Ubuntu Server
2. Install Docker, Tailscale, rclone
3. Clone `sarvar-infra` repo
4. Restore `.env` from 1Password/secure backup
5. `docker compose up -d`
6. Restore PostgreSQL from latest dump
7. Restore uploads from B2 (if needed)
8. Verify all healthchecks pass
9. Update DNS/DDNS if IP changed

---

## Future Improvements

- [ ] Migrate to Kubernetes (k3s) for self-healing
- [ ] Add Prometheus + Grafana for metrics
- [ ] Implement Loki for log aggregation
- [ ] Add automated security scanning (Trivy, Grype)
- [ ] Geo-redundant offsite (second B2 region)
- [ ] Hardware: 32GB RAM, 2TB NVMe, 4TB HDD

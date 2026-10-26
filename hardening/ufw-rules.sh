#!/bin/bash
# Sarvar UFW Firewall Rules
# Default-deny, explicit allow per service per CIDR
# Run as root: sudo ./ufw-rules.sh

set -euo pipefail

# ===== RESET =====
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# ===== TRUSTED NETWORKS =====
LAN="192.168.50.0/24"           # Home LAN
DOCKER_NETS="172.16.0.0/12"     # Docker networks
TAILSCALE="100.64.0.0/10"       # Tailscale CGNAT

# ===== SSH (LAN only) =====
ufw allow from "${LAN}" to any port 22 proto tcp comment 'SSH from LAN'

# ===== WEB SERVICES (LAN + Tailscale) =====
# Nginx Proxy Manager (public via DDNS, but firewall restricts)
ufw allow from "${LAN}" to any port 80,443 proto tcp comment 'HTTP/HTTPS from LAN'
ufw allow from "${TAILSCALE}" to any port 80,443 proto tcp comment 'HTTP/HTTPS from Tailscale'

# NPM Admin
ufw allow from "${LAN}" to any port 81 proto tcp comment 'NPM Admin from LAN'

# ===== APPLICATION SERVICES (LAN only) =====
# Media
ufw allow from "${LAN}" to any port 8096 proto tcp comment 'Jellyfin from LAN'

# *Arr Stack
ufw allow from "${LAN}" to any port 7878,8989,8686,9696,6767 proto tcp comment '*Arr from LAN'

# Downloads
ufw allow from "${LAN}" to any port 6881 proto tcp comment 'qBittorrent TCP from LAN'
ufw allow from "${LAN}" to any port 6881 proto udp comment 'qBittorrent UDP from LAN'
ufw allow from "${LAN}" to any port 8082 proto tcp comment 'qBittorrent WebUI from LAN'
ufw allow from "${LAN}" to any port 8181 proto tcp comment 'FlareSolverr from LAN'

# Immich
ufw allow from "${LAN}" to any port 2283 proto tcp comment 'Immich from LAN'

# Monitoring & Utils
ufw allow from "${LAN}" to any port 5055,8083,5678 proto tcp comment 'Seerr/Vaultwarden/n8n from LAN'

# Pi-hole DNS (LAN + Tailscale)
ufw allow from "${LAN}" to any port 53 proto tcp comment 'Pi-hole DNS TCP from LAN'
ufw allow from "${LAN}" to any port 53 proto udp comment 'Pi-hole DNS UDP from LAN'
ufw allow from "${TAILSCALE}" to any port 53 proto tcp comment 'Pi-hole DNS TCP from Tailscale'
ufw allow from "${TAILSCALE}" to any port 53 proto udp comment 'Pi-hole DNS UDP from Tailscale'
ufw allow from "${TAILSCALE}" to any port 8081 proto tcp comment 'Pi-hole Admin from Tailscale'

# Stirling PDF
ufw allow from "${LAN}" to any port 8090 proto tcp comment 'Stirling PDF from LAN'
ufw allow from "${TAILSCALE}" to any port 8090 proto tcp comment 'Stirling PDF from Tailscale'
ufw allow from "${DOCKER_NETS}" to any port 8090 proto tcp comment 'Stirling PDF from Docker'

# Sarvar API
ufw allow from "${DOCKER_NETS}" to any port 3002 proto tcp comment 'Sarvar API from Docker'

# ===== GAME SERVERS =====
# Project Zomboid (Steam networking)
ufw allow 16261/udp comment 'PZ Steam UDP'
ufw allow 16262/udp comment 'PZ RakNet UDP'
ufw allow 27015/tcp comment 'PZ RCON'

# ===== VPN & REMOTE =====
# Tailscale (auto-managed by tailscale, but explicit for clarity)
ufw allow in on tailscale0 comment 'Tailscale interface'

# XRDP (LAN only)
ufw allow from "${LAN}" to any port 3389 proto tcp comment 'RDP from LAN'

# VNC (LAN only)
ufw allow from "${LAN}" to any port 5901 proto tcp comment 'VNC from LAN'

# ===== ENABLE =====
ufw --force enable

# ===== STATUS =====
ufw status verbose numbered

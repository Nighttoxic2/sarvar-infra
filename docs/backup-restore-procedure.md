# Sarvar Backup Restore Procedure

**Tested:** Quarterly  
**Last Tested:** 2026-10-25  
**Next Test:** 2027-01-25

---

## Prerequisites

- Fresh Ubuntu Server 24.04 LTS installed
- Docker & Docker Compose installed
- Tailscale installed and authenticated
- rclone configured with `b2:immich-backups` remote
- Access to 1Password / secure vault for `.env` secrets
- SSH access to target machine

---

## Phase 1: Base System (15 min)

```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker

# 3. Install Docker Compose (plugin)
sudo apt install -y docker-compose-plugin

# 4. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sudo sh
sudo tailscale up --ssh

# 5. Install rclone
sudo apt install -y rclone
# Configure: rclone config (name: b2, type: b2, account/key from vault)

# 6. Create data directories
sudo mkdir -p /mnt/Data/{immich/upload,media,config,downloads,backups}
sudo chown -R $USER:$USER /mnt/Data
```

---

## Phase 2: Clone & Configure (10 min)

```bash
# 1. Clone infra repo
git clone https://github.com/amiruddin-mohd/sarvar-infra.git ~/sarvar-infra
cd ~/sarvar-infra

# 2. Restore .env from vault
# Get from 1Password: "Sarvar .env"
cp .env.example docker/.env
# Edit docker/.env with actual values

# 3. Pull hwaccel config
wget -q https://github.com/immich-app/immich/raw/main/docker/hwaccel.transcoding.yml -O docker/hwaccel.transcoding.yml
```

---

## Phase 3: Restore Database (20 min)

```bash
# 1. List available backups
rclone ls b2:immich-backups/

# 2. Download latest (or specific date)
rclone copy b2:immich-backups/immich-2026-10-25-0200.sql.gz /mnt/Data/immich/backups/

# 3. Start database only
cd ~/sarvar-infra/docker
docker compose up -d database redis

# 4. Wait for healthy
sleep 30
docker compose ps database

# 5. Restore
gunzip -c /mnt/Data/immich/backups/immich-2026-10-25-0200.sql.gz | docker exec -i immich_postgres psql -U postgres -d immich

# 6. Verify
docker exec immich_postgres psql -U postgres -d immich -c "SELECT COUNT(*) FROM asset;"
```

---

## Phase 4: Restore Uploads (Optional - 2-6 hours)

```bash
# Only if uploads were lost (not just DB)
# This downloads ~36GB from B2

rclone sync b2:immich-backups/uploads/ /mnt/Data/immich/upload/ \
    --progress --transfers 8 --checkers 16

# Verify structure
ls -la /mnt/Data/immich/upload/
# Should see: upload/, library/, thumbs/, encoded-video/
```

---

## Phase 5: Start All Services (10 min)

```bash
cd ~/sarvar-infra/docker
docker compose up -d

# Wait for all healthy
watch -n 5 'docker compose ps'

# Or check specific
docker compose ps --filter "status=running"
```

---

## Phase 6: Verify & Re-index (2-4 hours)

```bash
# 1. Check Immich API
curl -s http://LAN_IP:2283/api/server-info | jq

# 2. Trigger re-index if needed
docker exec immich_server npm run immich:metadata
docker exec immich_server npm run immich:thumbnails
docker exec immich_server npm run immich:faces
docker exec immich_server npm run immich:clip
docker exec immich_server npm run immich:video-transcode

# 3. Verify counts match
docker exec immich_postgres psql -U postgres -d immich -c "
  SELECT 
    (SELECT COUNT(*) FROM asset) as total_assets,
    (SELECT COUNT(DISTINCT assetId) FROM asset_metadata WHERE key='thumbnail') as with_thumbs,
    (SELECT COUNT(DISTINCT assetId) FROM asset_metadata WHERE key='clipEmbedding') as with_clip,
    (SELECT COUNT(*) FROM asset_face WHERE personGroupId IS NOT NULL) as faces_assigned;
"
```

---

## Phase 7: Restore Service Configs

```bash
# Configs are in git (private repo or 1Password)
# For each service, restore from ~/sarvar-infra/configs/<service>/

# Example: Nginx Proxy Manager
docker compose stop nginx-proxy-manager
rsync -av ~/sarvar-infra/configs/npm/ /mnt/Data/config/npm/
docker compose up -d nginx-proxy-manager

# Pi-hole
docker compose stop pihole
rsync -av ~/sarvar-infra/configs/pihole/ /mnt/Data/config/pihole/
docker compose up -d pihole

# Vaultwarden
docker compose stop vaultwarden
rsync -av ~/sarvar-infra/configs/vaultwarden/ /mnt/Data/config/vaultwarden/
docker compose up -d vaultwarden
```

---

## Phase 8: Network & Firewall

```bash
# 1. Apply UFW rules
sudo ~/sarvar-infra/hardening/ufw-rules.sh

# 2. Verify
sudo ufw status verbose

# 3. Test Tailscale
tailscale ping TAILSCALE_IP
```

---

## Phase 9: Monitoring & Validation

```bash
# 1. Run healthcheck
~/sarvar-infra/monitoring/healthcheck.sh

# 2. Check all services in browser
# - https://YOUR_DDNS_DOMAIN (NPM)
# - http://LAN_IP:2283 (Immich)
# - http://LAN_IP:8096 (Jellyfin)
# - http://LAN_IP:81 (NPM Admin)
# - http://LAN_IP:8081 (Pi-hole)

# 3. Verify backup job
~/sarvar-infra/backup/backup.sh
```

---

## Rollback Criteria

If any of these fail, **stop and investigate**:
- Database restore shows wrong asset count
- Immich API returns 5xx after 5 min
- Healthcheck shows >2 critical alerts
- Any service stuck in "restarting" state

---

## Post-Restore Checklist

- [ ] All containers healthy (`docker compose ps`)
- [ ] Asset counts match pre-restore
- [ ] Thumbnails generating (check `/thumbs`)
- [ ] CLIP search working
- [ ] Face recognition running
- [ ] Video transcoding via QuickSync
- [ ] NPM routing + SSL valid
- [ ] Pi-hole DNS resolving
- [ ] Tailscale access working
- [ ] Backup job completes successfully
- [ ] UFW rules applied
- [ ] Fail2ban running
- [ ] DDNS updated (if IP changed)

---

## Emergency Contacts

| Role | Contact |
|------|---------|
| Primary (Self) | Muhammad Amiruddin |
| ISP (Unifi/Time) | 1300-88-1221 |
| ASUS Router Admin | ROUTER_IP |
| Backblaze B2 Console | backblaze.com/b2 |

---

## Notes

- **Do not** restore uploads unless DB restore shows missing files
- **Do not** skip Phase 6 re-index — DB may be consistent but search index stale
- **Do** document actual RTO achieved for future planning

#!/bin/bash
# Sarvar Health Check & Alerting
# Runs every 5 min via cron: */5 * * * * /path/to/healthcheck.sh

set -euo pipefail

# ===== CONFIG =====
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"  # Discord/Slack/Telegram webhook
RESTART_THRESHOLD=10  # Alert if container restarted >10 times in window
DISK_THRESHOLD=85     # Alert if disk usage >85%
MEM_THRESHOLD=90      # Alert if memory usage >90%

# ===== FUNCTIONS =====
alert() {
    local msg="$1"
    local level="${2:-warning}"
    if [[ -n "${ALERT_WEBHOOK_URL}" ]]; then
        curl -s -X POST "${ALERT_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"[Sarvar ${level^^}] ${msg}\"}" >/dev/null
    fi
    logger -t sarvar-health "[${level^^}] ${msg}"
}

check_container() {
    local name="$1"
    local status
    status=$(docker inspect "${name}" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
    local restarts
    restarts=$(docker inspect "${name}" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    local health
    health=$(docker inspect "${name}" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

    if [[ "${status}" != "running" ]]; then
        alert "Container ${name} is ${status}" "critical"
        return 1
    fi

    if [[ "${restarts}" -gt "${RESTART_THRESHOLD}" ]]; then
        alert "Container ${name} has ${restarts} restarts (threshold: ${RESTART_THRESHOLD})" "warning"
    fi

    if [[ "${health}" == "unhealthy" ]]; then
        alert "Container ${name} health check: ${health}" "critical"
    fi
}

check_disk() {
    local usage
    usage=$(df /mnt/Data --output=pcent | tail -1 | tr -dc '0-9')
    if [[ "${usage}" -gt "${DISK_THRESHOLD}" ]]; then
        alert "Disk usage at ${usage}% (threshold: ${DISK_THRESHOLD}%)" "warning"
    fi
}

check_memory() {
    local usage
    usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    if [[ "${usage}" -gt "${MEM_THRESHOLD}" ]]; then
        alert "Memory usage at ${usage}% (threshold: ${MEM_THRESHOLD}%)" "warning"
    fi
}

check_failed_logins() {
    local failed
    failed=$(journalctl -u ssh --since "1 hour ago" | grep -c "Failed password" || true)
    if [[ "${failed}" -gt 20 ]]; then
        alert "SSH failed logins: ${failed} in last hour" "warning"
    fi
}

# ===== MAIN =====
main() {
    # Core containers
    for c in immich_server immich_postgres immich_redis immich_machine_learning \
             jellyfin prowlarr sonarr radarr lidarr bazarr qbittorrent \
             nginx-proxy-manager vaultwarden seerr n8n pihole watchtower; do
        check_container "${c}"
    done

    # System checks
    check_disk
    check_memory
    check_failed_logins

    # Log summary
    logger -t sarvar-health "Health check completed"
}

main "$@"

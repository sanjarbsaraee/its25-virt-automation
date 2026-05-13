#!/bin/bash
# Smoke test for iter 5 — monitoring stack, pgaudit, exporter.
# Runs from a laptop over SSH, same pattern as verify-iter1..4.
#
# Usage: bash scripts/verify-iter5.sh <ctrl> <web1> <web2> <db> <lb> <monitor>
# Example:
#   bash scripts/verify-iter5.sh 192.168.50.110 192.168.50.120 \
#        192.168.50.121 192.168.50.130 192.168.50.140 192.168.50.150

set -u

CTRL="${1:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
WEB1="${2:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
WEB2="${3:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
DB="${4:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
LB="${5:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
MONITOR="${6:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
USER="automation"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

# Wrapper that runs a remote command and hides ssh noise.
# Used by check() to test the exit code or grep the output.
run_ssh() {
  local host=$1
  local cmd=$2
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
      "$USER@$host" "$cmd" 2>/dev/null
}

# Helper that records PASS/FAIL based on whether the remote
# command matches the expected regex. Hint shown on failure.
check() {
  local name=$1
  local result=$2
  local expected=$3
  local hint=${4:-}
  if echo "$result" | grep -qE "$expected"; then
    printf " ${GREEN}[PASS]${NC} %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf " ${RED}[FAIL]${NC} %s\n" "$name"
    [ -n "$hint" ] && printf "         hint: %s\n" "$hint"
    FAIL=$((FAIL + 1))
  fi
}

heading() {
  printf "\n${YELLOW}=== %s ===${NC}\n" "$1"
}

printf "${YELLOW}====================================${NC}\n"
printf " Iter 5 verification\n"
printf " control=%s  web1=%s  web2=%s\n" "$CTRL" "$WEB1" "$WEB2"
printf " db=%s  lb=%s  monitor=%s\n" "$DB" "$LB" "$MONITOR"
printf "${YELLOW}====================================${NC}\n"

# UFW must be enabled on every VM. Without it the in-VM
# defense layer is missing and only Proxmox firewall protects.
heading "UFW status on every VM"
for pair in "control:$CTRL" "web-01:$WEB1" "web-02:$WEB2" "db-01:$DB" "lb-01:$LB" "monitor-01:$MONITOR"; do
  name="${pair%%:*}"
  ip="${pair##*:}"
  check "UFW active on $name" \
        "$(run_ssh "$ip" 'sudo ufw status')" \
        "Status: active" \
        "ssh in and run: sudo ufw status verbose"
done

# Four services must run on monitor-01 for the stack to work.
# systemctl is-active returns the literal word 'active' on success.
heading "Monitoring services on monitor-01"
for svc in prometheus prometheus-alertmanager prometheus-postgres-exporter grafana-server; do
  check "$svc is active" \
        "$(run_ssh "$MONITOR" "systemctl is-active $svc")" \
        "^active$" \
        "ssh to monitor-01 and run: journalctl -u $svc -n 50"
done

# ss -tuln lists listening sockets. systemctl might say active
# while the service silently binds to the wrong port.
check "prometheus listens on 9090" \
      "$(run_ssh "$MONITOR" 'ss -tuln')" ':9090'
check "grafana listens on 3000" \
      "$(run_ssh "$MONITOR" 'ss -tuln')" ':3000'
check "postgres_exporter listens on 9187" \
      "$(run_ssh "$MONITOR" 'ss -tuln')" ':9187'

# Prometheus exposes a health endpoint, the loaded rules list,
# and the postgres exporter's pg_up metric. Each tests a layer.
heading "Prometheus endpoints on monitor-01"
check "prometheus health endpoint" \
      "$(run_ssh "$MONITOR" 'curl -sf http://localhost:9090/-/healthy')" \
      'Healthy'
check "HighCpuUsage rule loaded" \
      "$(run_ssh "$MONITOR" 'curl -sf http://localhost:9090/api/v1/rules')" \
      'HighCpuUsage' \
      "alert_rules.yml deployed but Prometheus did not reload — restart it"
check "postgres_exporter publishes metrics" \
      "$(run_ssh "$MONITOR" 'curl -sf http://localhost:9187/metrics')" \
      'pg_up ' \
      "exporter cannot reach db-01 or auth failed"

# Every VM runs node_exporter on :9100. The metrics endpoint
# starts with a HELP comment line if the exporter is healthy.
heading "node_exporter on every VM"
for pair in "control:$CTRL" "web-01:$WEB1" "web-02:$WEB2" "db-01:$DB" "lb-01:$LB" "monitor-01:$MONITOR"; do
  name="${pair%%:*}"
  ip="${pair##*:}"
  check "node_exporter on $name" \
        "$(run_ssh "$ip" 'curl -sf http://localhost:9100/metrics | head -1')" \
        '^# HELP'
done

# End-to-end test: lb-01 proxies /grafana to monitor-01:3000.
# Grafana's /api/health returns JSON containing 'database'.
heading "Grafana via lb-01 (full proxy path)"
check "lb-01 proxies /grafana to monitor-01" \
      "$(run_ssh "$LB" 'curl -sf http://localhost/grafana/api/health')" \
      'database' \
      "nginx /grafana location block or Grafana not running"

# pgaudit and pg_stat_statements must be in shared_preload AND
# created as extensions in the app database. Both checks needed.
heading "pgaudit and pg_stat_statements on db-01"
check "pgaudit in shared_preload_libraries" \
      "$(run_ssh "$DB" 'sudo grep -E "^shared_preload_libraries" /etc/postgresql/16/main/postgresql.conf')" \
      'pgaudit'
check "pg_stat_statements in shared_preload_libraries" \
      "$(run_ssh "$DB" 'sudo grep -E "^shared_preload_libraries" /etc/postgresql/16/main/postgresql.conf')" \
      'pg_stat_statements'
check "pgaudit extension active in app db" \
      "$(run_ssh "$DB" "sudo -u postgres psql -d app -tAc \"SELECT 1 FROM pg_extension WHERE extname='pgaudit'\"")" \
      '^1$' \
      "CREATE EXTENSION pgaudit failed — check postgres restart timing"
check "pg_stat_statements extension active" \
      "$(run_ssh "$DB" "sudo -u postgres psql -d app -tAc \"SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements'\"")" \
      '^1$'
check "exporter user has pg_monitor role" \
      "$(run_ssh "$DB" "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_auth_members JOIN pg_roles m ON m.oid=roleid JOIN pg_roles e ON e.oid=member WHERE m.rolname='pg_monitor' AND e.rolname='exporter'\"")" \
      '^1$'

printf "\n${YELLOW}====================================${NC}\n"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}All %s/%s checks PASSED${NC}\n" "$PASS" "$TOTAL"
else
  printf "${RED}%s of %s checks FAILED${NC} (%s passed)\n" "$FAIL" "$TOTAL" "$PASS"
fi
printf "${YELLOW}====================================${NC}\n"

exit "$FAIL"
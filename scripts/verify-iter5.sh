#!/bin/bash
# Smoke test for iter 5 — monitoring stack, pgaudit, exporter, firewall.
# Run on control-node after ansible-playbook completes.
#
# Usage: bash tests/verify-iter5.sh

set -uo pipefail

# Run from the ansible directory so inventory paths resolve.
cd "$(dirname "$0")/../ansible" || { echo "cannot find ansible/ directory"; exit 1; }

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

# Helper that runs an ansible shell command against a group and prints
# PASS/FAIL based on the exit code. Hides the noise, shows the result.
run() {
  local name="$1"
  local target="$2"
  local cmd="$3"
  local hint="${4:-}"
  if ansible -i inventories/prod/proxmox.yml "$target" \
       -m shell -a "$cmd" --one-line > /tmp/verify-iter5.log 2>&1; then
    echo -e "${GREEN}[PASS]${NC} $name"
    PASS=$((PASS+1))
  else
    echo -e "${RED}[FAIL]${NC} $name"
    [ -n "$hint" ] && echo "        hint: $hint"
    FAIL=$((FAIL+1))
  fi
}

heading() {
  echo ""
  echo -e "${YELLOW}=== $1 ===${NC}"
}

# Each section groups related checks. If one section fails entirely,
# the cause is usually in the same role or playbook.

heading "UFW status on every VM"
# UFW must be enabled for the in-VM defense layer to work. The
# Proxmox firewall in front protects, but UFW is the second wall.
for host in control web db lb monitor; do
  run "UFW active on $host" "$host" \
      "sudo ufw status | grep -q 'Status: active'" \
      "ssh in and run: sudo ufw status verbose"
done

heading "Monitoring services on monitor-01"
run "prometheus is active" monitor \
    "systemctl is-active prometheus" \
    "ssh to monitor-01 and run: journalctl -u prometheus -n 50"
run "alertmanager is active" monitor \
    "systemctl is-active prometheus-alertmanager"
run "postgres_exporter is active" monitor \
    "systemctl is-active prometheus-postgres-exporter" \
    "check the DSN at /etc/default/prometheus-postgres-exporter"
run "grafana-server is active" monitor \
    "systemctl is-active grafana-server"

# Port-listening tells us the service bound correctly even if
# systemctl says active. Catches port-config mistakes.
run "prometheus listens on 9090" monitor "ss -tuln | grep -q ':9090'"
run "grafana listens on 3000" monitor "ss -tuln | grep -q ':3000'"
run "postgres_exporter listens on 9187" monitor "ss -tuln | grep -q ':9187'"

heading "Prometheus endpoints on monitor-01"
run "prometheus health endpoint" monitor \
    "curl -sf http://localhost:9090/-/healthy"
run "HighCpuUsage rule loaded" monitor \
    "curl -sf http://localhost:9090/api/v1/rules | grep -q HighCpuUsage" \
    "alert_rules.yml deployed but not picked up — check syntax"
run "postgres_exporter publishes metrics" monitor \
    "curl -sf http://localhost:9187/metrics | grep -q 'pg_up '" \
    "exporter cannot reach db-01 or auth failed"

heading "node_exporter on every VM"
for host in control web db lb monitor; do
  run "node_exporter on $host" "$host" \
      "curl -sf http://localhost:9100/metrics | head -1 | grep -q '^# HELP'"
done

heading "Grafana via lb-01 (full path)"
# Curls from lb-01 to its own localhost. Tests that nginx
# proxies /grafana to monitor-01:3000 and Grafana answers.
run "lb-01 proxies /grafana to monitor-01" lb \
    "curl -sf http://localhost/grafana/api/health | grep -q 'database'" \
    "nginx config issue or Grafana not running"

heading "pgaudit and pg_stat_statements on db-01"
run "pgaudit in shared_preload_libraries" db \
    "sudo grep -E 'shared_preload_libraries.*pgaudit' /etc/postgresql/16/main/postgresql.conf"
run "pg_stat_statements in shared_preload_libraries" db \
    "sudo grep -E 'shared_preload_libraries.*pg_stat_statements' /etc/postgresql/16/main/postgresql.conf"
run "pgaudit extension active in app db" db \
    "sudo -u postgres psql -d app -tAc \"SELECT 1 FROM pg_extension WHERE extname='pgaudit'\" | grep -q 1" \
    "CREATE EXTENSION pgaudit failed — check postgres restart timing"
run "pg_stat_statements extension active" db \
    "sudo -u postgres psql -d app -tAc \"SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements'\" | grep -q 1"
run "exporter user exists with pg_monitor role" db \
    "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_auth_members JOIN pg_roles m ON m.oid=roleid JOIN pg_roles e ON e.oid=member WHERE m.rolname='pg_monitor' AND e.rolname='exporter'\" | grep -q 1"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}All $PASS/$TOTAL checks PASSED${NC}"
  exit 0
else
  echo -e "${RED}$FAIL of $TOTAL checks FAILED${NC} ($PASS passed)"
  echo "Last command output saved to /tmp/verify-iter5.log"
  exit 1
fi
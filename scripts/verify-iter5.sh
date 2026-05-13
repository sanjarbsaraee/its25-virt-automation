#!/bin/bash
# Smoke test for iter 5 — monitoring stack, pgaudit, exporter.
# Runs from a laptop over SSH (no Ansible needed locally).
#
# Usage: bash scripts/verify-iter5.sh <ctrl> <web1> <web2> <db> <lb> <monitor>
# Example (sanjar-dev):
#   bash scripts/verify-iter5.sh 192.168.50.110 192.168.50.120 \
#        192.168.50.121 192.168.50.130 192.168.50.140 192.168.50.150
#
# Design notes:
#   * UFW limits SSH to 6 new connections per 30 seconds from
#     Tailscale subnet. Each host gets at most 1-2 SSH calls
#     here; monitor-01 has many checks so all are bundled into
#     ONE remote shell session and parsed locally.
#   * Endpoint checks use curl against the service's own URL.
#     A successful response proves both that the port is open
#     and that the service is healthy.
#   * Grafana is served from /grafana subpath and pretty-prints
#     its JSON across multiple lines, so we strip newlines so
#     the extract function sees a single labelled line.
#   * Postgres uses psql \dx for extensions and pg_auth_members
#     for built-in role membership (\du does not show pg_monitor).

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

# -q hides host-key warnings (otherwise they leak into stdout).
# BatchMode prevents interactive prompts.
SSH_OPTS=(-q -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# Run a remote command and return its stdout. PATH is set so that
# /usr/sbin tools (ss, sudo helpers) are reachable in the SSH
# non-interactive shell.
run_ssh() {
  local host=$1
  local cmd=$2
  ssh "${SSH_OPTS[@]}" "$USER@$host" \
      "PATH=/usr/sbin:/usr/bin:/sbin:/bin; $cmd" 2>/dev/null
}

# Record PASS/FAIL based on whether the result matches the regex.
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

# Pull a labelled value out of monitor-01's bundled output.
extract() {
  echo "$mon_data" | sed -n "s/^$1=//p"
}

printf "${YELLOW}====================================${NC}\n"
printf " Iter 5 verification\n"
printf " control=%s  web1=%s  web2=%s\n" "$CTRL" "$WEB1" "$WEB2"
printf " db=%s  lb=%s  monitor=%s\n" "$DB" "$LB" "$MONITOR"
printf "${YELLOW}====================================${NC}\n"

# One SSH call per non-monitor host: UFW + node_exporter.
heading "UFW status on every VM"
for pair in "control:$CTRL" "web-01:$WEB1" "web-02:$WEB2" "db-01:$DB" "lb-01:$LB"; do
  name="${pair%%:*}"
  ip="${pair##*:}"
  check "UFW active on $name" \
        "$(run_ssh "$ip" 'sudo ufw status')" \
        "Status: active" \
        "ssh in and run: sudo ufw status verbose"
done

# Bundle ALL monitor-01 checks into ONE SSH session. UFW rate-limit
# bites at 6 new SSH connections within 30s; this stays at 1.
# Multi-line outputs are flattened with tr so each labelled line
# stays parseable by the extract function below.
heading "Bundled probe of monitor-01"
mon_data=$(run_ssh "$MONITOR" '
  echo "UFW=$(sudo ufw status | head -1)"
  for svc in prometheus prometheus-alertmanager prometheus-postgres-exporter grafana-server; do
    echo "SVC_$svc=$(systemctl is-active $svc)"
  done
  echo "PROM_HEALTH=$(curl -sf http://localhost:9090/-/healthy)"
  echo "ALERT_HEALTH=$(curl -sf http://localhost:9093/-/healthy)"
  echo "GRAFANA_HEALTH=$(curl -sf http://localhost:3000/grafana/api/health | tr -d "\n")"
  echo "EXPORTER_FIRST=$(curl -sf http://localhost:9187/metrics | head -1)"
  echo "ALERT_RULES=$(curl -sf http://localhost:9090/api/v1/rules | tr -d "\n")"
  echo "PG_UP_LINE=$(curl -sf http://localhost:9187/metrics | grep ^pg_up)"
  echo "NODE_EXP_FIRST=$(curl -sf http://localhost:9100/metrics | head -1)"
')
check "UFW active on monitor-01" "$(extract UFW)" "Status: active"

heading "Monitoring services on monitor-01"
for svc in prometheus prometheus-alertmanager prometheus-postgres-exporter grafana-server; do
  check "$svc is active" \
        "$(extract "SVC_$svc")" \
        "^active$" \
        "ssh to monitor-01 and run: journalctl -u $svc -n 50"
done

heading "Service endpoints on monitor-01"
check "prometheus reachable on :9090" "$(extract PROM_HEALTH)" 'Healthy'
check "alertmanager reachable on :9093" "$(extract ALERT_HEALTH)" '.'
check "grafana reachable on :3000" "$(extract GRAFANA_HEALTH)" 'database'
check "postgres_exporter reachable on :9187" "$(extract EXPORTER_FIRST)" '^#'

heading "Prometheus internals"
check "HighCpuUsage rule loaded" \
      "$(extract ALERT_RULES)" \
      'HighCpuUsage' \
      "alert_rules.yml deployed but Prometheus did not reload"
check "postgres_exporter publishes pg_up metric" \
      "$(extract PG_UP_LINE)" \
      'pg_up ' \
      "exporter cannot reach db-01 or auth failed"

# node_exporter on each VM. Each non-monitor host gets one more
# SSH call here; monitor-01 was already covered in the bundle.
heading "node_exporter on every VM"
for pair in "control:$CTRL" "web-01:$WEB1" "web-02:$WEB2" "db-01:$DB" "lb-01:$LB"; do
  name="${pair%%:*}"
  ip="${pair##*:}"
  check "node_exporter on $name" \
        "$(run_ssh "$ip" 'curl -sf http://localhost:9100/metrics | head -1')" \
        '^#'
done
check "node_exporter on monitor-01" "$(extract NODE_EXP_FIRST)" '^#'

heading "Grafana via lb-01 (full proxy path)"
check "lb-01 proxies /grafana to monitor-01" \
      "$(run_ssh "$LB" 'curl -sf http://localhost/grafana/api/health')" \
      'database' \
      "nginx /grafana location block or Grafana not running"

heading "pgaudit and pg_stat_statements on db-01"
shared_preload=$(run_ssh "$DB" 'sudo grep -E "^shared_preload_libraries" /etc/postgresql/16/main/postgresql.conf')
check "pgaudit in shared_preload_libraries" "$shared_preload" 'pgaudit'
check "pg_stat_statements in shared_preload_libraries" "$shared_preload" 'pg_stat_statements'

extensions=$(run_ssh "$DB" 'sudo -u postgres psql -d app -tA -c "\dx"')
check "pgaudit extension active in app db" \
      "$extensions" 'pgaudit' "CREATE EXTENSION pgaudit failed"
check "pg_stat_statements extension active" "$extensions" 'pg_stat_statements'

# pg_auth_members joins exporter (member) with pg_monitor (role).
# \du does not show built-in role membership in PG 16.
exporter_grants=$(run_ssh "$DB" "sudo -u postgres psql -tAc \"SELECT m.rolname FROM pg_auth_members am JOIN pg_roles m ON m.oid = am.roleid JOIN pg_roles e ON e.oid = am.member WHERE e.rolname = 'exporter'\"")
check "exporter user has pg_monitor role" \
      "$exporter_grants" 'pg_monitor' \
      "GRANT pg_monitor TO exporter never ran"

printf "\n${YELLOW}====================================${NC}\n"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}All %s/%s checks PASSED${NC}\n" "$PASS" "$TOTAL"
else
  printf "${RED}%s of %s checks FAILED${NC} (%s passed)\n" "$FAIL" "$TOTAL" "$PASS"
fi
printf "${YELLOW}====================================${NC}\n"

exit "$FAIL"
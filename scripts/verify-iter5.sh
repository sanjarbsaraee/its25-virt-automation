#!/bin/bash
# Proves iter 5 monitoring and pgAudit work end-to-end.

set -u

CONTROL_IP="${1:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
WEB1_IP="${2:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
WEB2_IP="${3:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
DB_IP="${4:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
LB_IP="${5:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
MONITOR_IP="${6:?Usage: $0 <ctrl> <web1> <web2> <db> <lb> <monitor>}"
USER="automation"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

run_ssh() {
    local host=$1
    local cmd=$2
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "$USER@$host" "$cmd" 2>/dev/null
}

check() {
    local description=$1
    local result=$2
    local expected=$3
    if echo "$result" | grep -qE "$expected"; then
        printf " ${GREEN}✓${NC} %s\n" "$description"
        PASS=$((PASS + 1))
    else
        printf " ${RED}✗${NC} %s\n" "$description"
        printf "   Expected: %s\n" "$expected"
        printf "   Got:      %s\n" "$result"
        FAIL=$((FAIL + 1))
    fi
}

printf "${CYAN}==========================================${NC}\n"
printf " Iter 5 Verification\n"
printf " Control: ${YELLOW}%s${NC}  Web1: ${YELLOW}%s${NC}\n" "$CONTROL_IP" "$WEB1_IP"
printf " Web2: ${YELLOW}%s${NC}  DB: ${YELLOW}%s${NC}  LB: ${YELLOW}%s${NC}\n" "$WEB2_IP" "$DB_IP" "$LB_IP"
printf " Monitor: ${YELLOW}%s${NC}\n" "$MONITOR_IP"
printf "${CYAN}==========================================${NC}\n"

# --- UFW status on Monitor ---
printf "\n${CYAN}--- UFW status ---${NC}\n"
check "UFW active on $MONITOR_IP" \
    "$(run_ssh "$MONITOR_IP" 'sudo ufw status verbose')" \
    "Status: active"

# --- Node Exporter on all hosts ---
printf "\n${CYAN}--- Node Exporter ---${NC}\n"
for ip in "$CONTROL_IP" "$WEB1_IP" "$WEB2_IP" "$DB_IP" "$LB_IP" "$MONITOR_IP"; do
    check "Node Exporter listening on $ip:9100" \
        "$(run_ssh "$ip" 'ss -tuln | grep :9100')" \
        "LISTEN"
done

# --- Prometheus on Monitor ---
printf "\n${CYAN}--- Prometheus ---${NC}\n"
check "Prometheus listening on $MONITOR_IP:9090" \
    "$(run_ssh "$MONITOR_IP" 'ss -tuln | grep :9090')" \
    "LISTEN"

# --- Grafana on Monitor ---
printf "\n${CYAN}--- Grafana ---${NC}\n"
check "Grafana listening on $MONITOR_IP:3000" \
    "$(run_ssh "$MONITOR_IP" 'ss -tuln | grep :3000')" \
    "LISTEN"

# --- Grafana via LB ---
printf "\n${CYAN}--- Grafana via LB ---${NC}\n"
check "LB proxies /grafana" \
    "$(curl -s -o /dev/null -w "%{http_code}" http://$LB_IP/grafana/)" \
    "200|302"

# --- pgAudit on DB ---
printf "\n${CYAN}--- pgAudit ---${NC}\n"
check "pgAudit loaded in PostgreSQL" \
    "$(run_ssh "$DB_IP" "sudo -u postgres psql -t -c 'show shared_preload_libraries'")" \
    "pgaudit"

printf "\n${CYAN}==========================================${NC}\n"
if [ $FAIL -eq 0 ]; then
    printf "${GREEN}PASSED:${NC} %d checks\n" "$PASS"
else
    printf "${RED}FAILED:${NC} %d checks (%d passed)\n" "$FAIL" "$PASS"
fi
printf "${CYAN}==========================================${NC}\n"

exit "$FAIL"

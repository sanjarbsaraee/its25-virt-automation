#!/bin/bash
# Catches iter 2 regressions after a deploy. Covers
# Flask endpoints, PostgreSQL connectivity, TLS, and
# firewall rules across web-01 and db-01.
#
# Usage: ./scripts/verify-iter2.sh <web-ip> <db-ip>
# Example: ./scripts/verify-iter2.sh 192.168.50.120 192.168.50.130

set -u

WEB_IP="${1:?Usage: $0 <web-ip> <db-ip>}"
DB_IP="${2:?Usage: $0 <web-ip> <db-ip>}"
USER="automation"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

echo -e "${CYAN}==========================================${NC}"
echo -e " Iter 2 Verification"
echo -e " Web: ${YELLOW}$WEB_IP${NC}  DB: ${YELLOW}$DB_IP${NC}"
echo -e "${CYAN}==========================================${NC}"

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

    if echo "$result" | grep -q "$expected"; then
        echo -e " ${GREEN}✓${NC} $description"
        PASS=$((PASS + 1))
    else
        echo -e " ${RED}✗${NC} $description"
        echo "   Expected: $expected"
        echo "   Got: $result"
        FAIL=$((FAIL + 1))
    fi
}

# --- Connectivity ---
echo -e "\n${CYAN}--- Connectivity ---${NC}"
check "SSH to web-01" "$(run_ssh $WEB_IP 'whoami')" "$USER"
check "SSH to db-01" "$(run_ssh $DB_IP 'whoami')" "$USER"

# --- Flask Endpoints ---
# curl runs from the laptop, not over SSH.
echo -e "\n${CYAN}--- Flask Endpoints ---${NC}"
check "GET / returns HTML" \
    "$(curl -s http://$WEB_IP:8080/)" "ITS25 Capstone Demo"
check "GET /health returns ok" \
    "$(curl -s http://$WEB_IP:8080/health)" "ok"
check "GET /info returns JSON with db_reachable" \
    "$(curl -s http://$WEB_IP:8080/info)" "db_reachable"
check "Database is reachable from Flask" \
    "$(curl -s http://$WEB_IP:8080/info)" '"db_reachable": true'

# --- Flask Process ---
echo -e "\n${CYAN}--- Flask Process ---${NC}"
# ps -o user= prints the full username without truncation.
check "Gunicorn runs as $USER (not root)" \
    "$(run_ssh $WEB_IP 'ps -o user= -p $(pgrep gunicorn | head -1)')" "$USER"
check "flask_app service is active" \
    "$(run_ssh $WEB_IP 'systemctl is-active flask_app')" "active"

# --- PostgreSQL ---
echo -e "\n${CYAN}--- PostgreSQL ---${NC}"
check "PostgreSQL 16 is running" \
    "$(run_ssh $DB_IP 'systemctl is-active postgresql@16-main')" "active"
check "TLS cert exists" \
    "$(run_ssh $DB_IP 'test -f /etc/postgresql/16/main/server.crt && echo YES')" "YES"

# --- TLS Enforcement ---
# Reads the db password from the flask_app systemd service
# so the script does not need credentials as input.
echo -e "\n${CYAN}--- TLS Enforcement ---${NC}"
PG_PWD_CMD="sudo systemctl show flask_app -p Environment | grep -o 'DB_PASSWORD=[^ ]*' | cut -d= -f2"
check "TLS connection succeeds" \
    "$(run_ssh $WEB_IP "PGPASSWORD=\$($PG_PWD_CMD) psql \"host=$DB_IP user=app_rw dbname=app sslmode=require\" -c \"SELECT 1;\" 2>&1")" "1 row"
check "Non-TLS connection rejected" \
    "$(run_ssh $WEB_IP "PGPASSWORD=\$($PG_PWD_CMD) psql \"host=$DB_IP user=app_rw dbname=app sslmode=disable\" -c \"SELECT 1;\" 2>&1")" "FATAL"

# --- Firewall ---
echo -e "\n${CYAN}--- Firewall ---${NC}"
check "UFW active on db-01" \
    "$(run_ssh $DB_IP 'sudo ufw status' 2>/dev/null)" "active"
check "Port 5432 open from web-01" \
    "$(run_ssh $WEB_IP "nc -zv $DB_IP 5432 2>&1")" "open\|succeeded"

echo -e "\n${CYAN}==========================================${NC}"
if [ $FAIL -eq 0 ]; then
    printf "${GREEN}PASSED:${NC} %d checks\n" "$PASS"
else
    printf "${RED}FAILED:${NC} %d checks (%d passed)\n" "$FAIL" "$PASS"
fi
echo -e "${CYAN}==========================================${NC}"

exit "$FAIL"
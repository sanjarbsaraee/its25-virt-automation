#!/bin/bash
# Catches iter 3 regressions. Covers load balancing,
# round-robin distribution, failover, and server_tokens.
#
# Usage: ./scripts/verify-iter3.sh <lb-ip> <web1-ip> <web2-ip> <db-ip>
# Example: ./scripts/verify-iter3.sh 192.168.50.140 192.168.50.120 192.168.50.121 192.168.50.130

set -u

LB_IP="${1:?Usage: $0 <lb-ip> <web1-ip> <web2-ip> <db-ip>}"
WEB1_IP="${2:?Usage: $0 <lb-ip> <web1-ip> <web2-ip> <db-ip>}"
WEB2_IP="${3:?Usage: $0 <lb-ip> <web1-ip> <web2-ip> <db-ip>}"
DB_IP="${4:?Usage: $0 <lb-ip> <web1-ip> <web2-ip> <db-ip>}"
USER="automation"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

echo -e "${CYAN}==========================================${NC}"
echo -e " Iter 3 Verification"
echo -e " LB: ${YELLOW}$LB_IP${NC}  DB: ${YELLOW}$DB_IP${NC}"
echo -e " Web1: ${YELLOW}$WEB1_IP${NC}  Web2: ${YELLOW}$WEB2_IP${NC}"
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
check "SSH to lb-01" "$(run_ssh $LB_IP 'whoami')" "$USER"
check "SSH to web-02" "$(run_ssh $WEB2_IP 'whoami')" "$USER"

# --- LB Endpoints ---
echo -e "\n${CYAN}--- LB Endpoints ---${NC}"
check "GET / via LB returns HTML" \
    "$(curl -s http://$LB_IP/)" "ITS25 Capstone Demo"
check "GET /health via LB returns ok" \
    "$(curl -s http://$LB_IP/health)" "ok"
check "GET /info via LB returns JSON" \
    "$(curl -s http://$LB_IP/info)" "db_reachable"

# --- Round-robin ---
# Calls LB 6 times. Both backends should appear at least once.
echo -e "\n${CYAN}--- Round-robin ---${NC}"
HOSTS=""
for i in 1 2 3 4 5 6; do
    HOSTS="$HOSTS $(curl -s http://$LB_IP/info | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')"
done
check "web-01 responds via LB" "$HOSTS" "web-01"
check "web-02 responds via LB" "$HOSTS" "web-02"

# --- Failover ---
# Stops Flask on web-01. All requests should still succeed
# and report db_reachable: true (i.e. land on web-02).
echo -e "\n${CYAN}--- Failover ---${NC}"
run_ssh $WEB1_IP "sudo systemctl stop flask_app"
sleep 3
FAILOVER_RESULTS=""
for i in 1 2 3 4 5; do
    FAILOVER_RESULTS="$FAILOVER_RESULTS $(curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/info)"
done
check "All 5 requests return 200 with web-01 down" \
    "$FAILOVER_RESULTS" "200 200 200 200 200"
run_ssh $WEB1_IP "sudo systemctl start flask_app"
sleep 3

# --- Security ---
echo -e "\n${CYAN}--- Security ---${NC}"
check "Server header present" \
    "$(curl -sI http://$LB_IP/ | grep -i '^server:')" "nginx"
# server_tokens off makes nginx send "Server: nginx" with
# no version. Check that no digit appears in the header.
check "No version number in Server header" \
    "$(curl -sI http://$LB_IP/ | grep -i '^server:' | grep -c '[0-9]')" "^0$"

# --- Web-02 DB access ---
echo -e "\n${CYAN}--- Web-02 DB access ---${NC}"
check "web-02 can reach database" \
    "$(curl -s http://$WEB2_IP:8080/info)" "db_reachable[[:space:]]*:[[:space:]]*true"

echo -e "\n${CYAN}==========================================${NC}"
if [ $FAIL -eq 0 ]; then
    printf "${GREEN}PASSED:${NC} %d checks\n" "$PASS"
else
    printf "${RED}FAILED:${NC} %d checks (%d passed)\n" "$FAIL" "$PASS"
fi
echo -e "${CYAN}==========================================${NC}"

exit "$FAIL"
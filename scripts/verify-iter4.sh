#!/bin/bash
# Proves iter 4 firewall and SSH hardening work end-to-end.
# Without this, the only way to verify is manual SSH and
# guesswork, since firewall rules are invisible in the UI.
#
# Usage:   ./scripts/verify-iter4.sh <ctrl> <web1> <web2> <db> <lb>
# Example: ./scripts/verify-iter4.sh 192.168.50.110 192.168.50.120 \
#            192.168.50.121 192.168.50.130 192.168.50.140
 
set -u
 
CONTROL_IP="${1:?Usage: $0 <ctrl> <web1> <web2> <db> <lb>}"
WEB1_IP="${2:?Usage: $0 <ctrl> <web1> <web2> <db> <lb>}"
WEB2_IP="${3:?Usage: $0 <ctrl> <web1> <web2> <db> <lb>}"
DB_IP="${4:?Usage: $0 <ctrl> <web1> <web2> <db> <lb>}"
LB_IP="${5:?Usage: $0 <ctrl> <web1> <web2> <db> <lb>}"
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
 
# Passes if the output matches the expected pattern.
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
 
# Passes if the output does NOT match the pattern. Used
# for blocked traffic, where a match means the firewall
# failed to drop it.
check_negative() {
    local description=$1
    local result=$2
    local forbidden=$3
    if echo "$result" | grep -qE "$forbidden"; then
        printf " ${RED}✗${NC} %s\n" "$description"
        printf "   Should NOT match: %s\n" "$forbidden"
        printf "   Got:              %s\n" "$result"
        FAIL=$((FAIL + 1))
    else
        printf " ${GREEN}✓${NC} %s\n" "$description"
        PASS=$((PASS + 1))
    fi
}
 
printf "${CYAN}==========================================${NC}\n"
printf " Iter 4 Verification\n"
printf " Control: ${YELLOW}%s${NC}  Web1: ${YELLOW}%s${NC}\n" "$CONTROL_IP" "$WEB1_IP"
printf " Web2: ${YELLOW}%s${NC}  DB: ${YELLOW}%s${NC}  LB: ${YELLOW}%s${NC}\n" "$WEB2_IP" "$DB_IP" "$LB_IP"
printf "${CYAN}==========================================${NC}\n"
 
# --- UFW status on every VM ---
printf "\n${CYAN}--- UFW status ---${NC}\n"
for ip in "$CONTROL_IP" "$WEB1_IP" "$WEB2_IP" "$DB_IP" "$LB_IP"; do
    check "UFW active on $ip" \
        "$(run_ssh "$ip" 'sudo ufw status verbose')" \
        "Status: active"
    check "UFW default deny incoming on $ip" \
        "$(run_ssh "$ip" 'sudo ufw status verbose')" \
        "deny.*incoming"
done
 
# --- SSH hardening on every VM ---
# sshd -T prints the running config. If the role failed
# silently, these checks catch it.
printf "\n${CYAN}--- SSH hardening ---${NC}\n"
for ip in "$CONTROL_IP" "$WEB1_IP" "$WEB2_IP" "$DB_IP" "$LB_IP"; do
    check "Root login disabled on $ip" \
        "$(run_ssh "$ip" 'sudo sshd -T | grep ^permitrootlogin')" \
        "no"
    check "Password auth disabled on $ip" \
        "$(run_ssh "$ip" 'sudo sshd -T | grep ^passwordauthentication')" \
        "no"
done
 
# --- Allowed traffic actually works ---
printf "\n${CYAN}--- Allowed traffic ---${NC}\n"
check "lb-01 reaches Flask on web-01:8080" \
    "$(run_ssh "$LB_IP" "nc -zv -w 2 $WEB1_IP 8080 2>&1")" \
    "succeeded|open"
check "web-01 reaches Postgres on db-01:5432" \
    "$(run_ssh "$WEB1_IP" "nc -zv -w 2 $DB_IP 5432 2>&1")" \
    "succeeded|open"
 
# --- Blocked traffic actually fails ---
# If these pass, the firewall is not blocking what it
# should. That is a security regression.
printf "\n${CYAN}--- Blocked traffic ---${NC}\n"
check_negative "db-01 cannot reach Flask on web-01:8080" \
    "$(run_ssh "$DB_IP" "nc -zv -w 2 $WEB1_IP 8080 2>&1")" \
    "succeeded|open"
check_negative "lb-01 cannot reach Postgres on db-01:5432" \
    "$(run_ssh "$LB_IP" "nc -zv -w 2 $DB_IP 5432 2>&1")" \
    "succeeded|open"
 
printf "\n${CYAN}==========================================${NC}\n"
if [ $FAIL -eq 0 ]; then
    printf "${GREEN}PASSED:${NC} %d checks\n" "$PASS"
else
    printf "${RED}FAILED:${NC} %d checks (%d passed)\n" "$FAIL" "$PASS"
fi
printf "${CYAN}==========================================${NC}\n"
 
exit "$FAIL"
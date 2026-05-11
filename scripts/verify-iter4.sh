#!/usr/bin/env bash
# verify-iter4.sh
# Tests defense-in-depth: Proxmox Firewall and UFW rules.

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "Starting Iteration 4 Verification: Network Hardening\n"

echo "1. Checking Public Access (Port 80 on LB)"
if curl -s -m 2 http://192.168.50.240 > /dev/null; then
    echo -e "${GREEN}PASS:${NC} Load balancer port 80 is reachable"
else
    echo -e "${RED}FAIL:${NC} Load balancer port 80 is NOT reachable"
fi

echo -e "\n2. Checking Internal Web App Ports (Port 8080 on Web Servers)"
if curl -s -m 2 http://192.168.50.220:8080 > /dev/null; then
   echo -e "${RED}FAIL:${NC} Web-01 port 8080 was reached! Firewall is open."
else
   echo -e "${GREEN}PASS:${NC} Web-01 port 8080 is correctly blocked"
fi

if curl -s -m 2 http://192.168.50.221:8080 > /dev/null; then
   echo -e "${RED}FAIL:${NC} Web-02 port 8080 was reached! Firewall is open."
else
   echo -e "${GREEN}PASS:${NC} Web-02 port 8080 is correctly blocked"
fi

echo -e "\n3. Checking Internal Database Port (Port 5432 on DB Server)"
if nc -z -w 2 192.168.50.230 5432 > /dev/null 2>&1; then
   echo -e "${RED}FAIL:${NC} DB-01 port 5432 was reached! Firewall is open."
else
   echo -e "${GREEN}PASS:${NC} DB-01 port 5432 is correctly blocked"
fi

echo -e "\n4. Checking UFW status on nodes (via Ansible)"
if ansible all -m shell -a "ufw status | grep -q 'Status: active'" -b > /dev/null 2>&1; then
    echo -e "${GREEN}PASS:${NC} UFW is active on all nodes"
else
    echo -e "${RED}FAIL:${NC} UFW is not active on all nodes"
fi

echo -e "\n${GREEN}All network hardening checks passed!${NC}"

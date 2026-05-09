#!/bin/bash
# Verifies every VM meets the minimum requirements Ansible
# needs before it tries to configure anything.
#
# Usage: ./scripts/verify-node.sh <ip> [user]
# Default user: automation

set -u

NODE_IP="${1:?Usage: $0 <ip> [user]}"
USER="${2:-automation}"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

echo -e "${CYAN}==========================================${NC}"
echo -e " Node Verification — ${YELLOW}$NODE_IP${NC} (as ${YELLOW}$USER${NC})"
echo -e "${CYAN}==========================================${NC}"

# Supports running checks on this machine directly, not
# only over SSH to remote nodes.
run_ssh() {
    if [[ "$NODE_IP" == "localhost" || "$NODE_IP" == "127.0.0.1" ]]; then
        eval "$1" 2>/dev/null
    else
        ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$USER@$NODE_IP" "$1" 2>/dev/null
    fi
}

check() {
    local description=$1
    local command=$2
    local expected=$3
    local result
    result=$(run_ssh "$command")

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

# --- System Specs ---
# Catches mismatches between Terraform config and actual VM.
echo -e "\n${CYAN}--- System Specs ---${NC}"
OS=$(run_ssh "cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2")
CORES=$(run_ssh "nproc")
RAM=$(run_ssh "free -h | grep Mem | awk '{print \$2}'")
DISK=$(run_ssh "df -h / | tail -1 | awk '{print \$2}'")

echo -e " OS:      ${YELLOW}$OS${NC}"
echo -e " CPU:     ${YELLOW}$CORES Cores${NC}"
echo -e " RAM:     ${YELLOW}$RAM Total${NC}"
echo -e " DISK:    ${YELLOW}$DISK Root Partition${NC}"

# --- Core Connectivity ---
# Without these three, Ansible cannot reach or manage the node.
echo -e "\n${CYAN}--- Core Connectivity ---${NC}"
check "SSH Connectivity" "whoami" "$USER"
check "Sudo Privileges (NOPASSWD)" "sudo -n whoami" "root"
check "QEMU Guest Agent Running" "systemctl is-active qemu-guest-agent" "active"

# Repo presence distinguishes control-node from worker nodes.
IS_CONTROL=$(run_ssh "test -d /home/$USER/its25-virt-automation && echo YES || echo NO")

if [ "$IS_CONTROL" == "YES" ]; then
    echo -e "\n${CYAN}--- Control Node Checks ---${NC}"
    check "Ansible Installed" "ansible --version" "ansible"
    check "Git Installed" "git --version" "git"
    check "Project Repo Found" "ls /home/$USER/its25-virt-automation/README.md" "README.md"
    # ansible.cfg looks for installed packages relative to
    # where you run the command. cd puts us in the right spot.
    check "Ansible Collections" "cd /home/$USER/its25-virt-automation/ansible && ansible-galaxy collection list" "infisical"

    # --- Fleet Connectivity ---
    # Per-tier pings pinpoint which tier is unreachable.
    echo -e "\n${CYAN}--- Fleet Connectivity ---${NC}"
    check "Ansible Ping (Web Tier)" "cd /home/$USER/its25-virt-automation/ansible && ansible web -m ping" "SUCCESS"
    check "Ansible Ping (DB Tier)" "cd /home/$USER/its25-virt-automation/ansible && ansible db -m ping" "SUCCESS"
else
    echo -e "\n${CYAN}--- Generic Node Checks ---${NC}"
    check "SSH Service Active" "systemctl is-active ssh" "active"
    # ^ means "line starts with" so lines like
    # "# PermitRootLogin" are skipped.
    check "No Root Password Login" "sudo grep '^PermitRootLogin' /etc/ssh/sshd_config" "prohibit-password|no"
fi

echo -e "\n${CYAN}==========================================${NC}"
if [ $FAIL -eq 0 ]; then
    printf "${GREEN}PASSED:${NC} %d checks\n" "$PASS"
else
    printf "${RED}FAILED:${NC} %d checks (%d passed)\n" "$FAIL" "$PASS"
fi
echo -e "${CYAN}==========================================${NC}"

exit "$FAIL"
#!/bin/bash
# End-to-end check that iter 1 is functional. SSHs into the
# control-node and runs 11 checks: packages, repo, Galaxy
# collections, playbook idempotency.
#
# Usage:   ./scripts/verify-iter1.sh <control-node-ip>
# Example: ./scripts/verify-iter1.sh 192.168.50.110

set -u

CONTROL_IP="${1:?Usage: $0 <control-node-ip>}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

# Runs a command on the control-node over SSH, checks if
# the output contains the expected substring.
check() {
  local description=$1
  local command=$2
  local expected=$3

  local result
  result=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "admin@$CONTROL_IP" "$command" 2>/dev/null)

  if echo "$result" | grep -q "$expected"; then
    echo -e "${GREEN}✓${NC} $description"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}✗${NC} $description"
    echo "  Expected substring: $expected"
    echo "  Got: $result"
    FAIL=$((FAIL + 1))
  fi
}

echo "=========================================="
echo " Iter 1 verification — control-node $CONTROL_IP"
echo "=========================================="
echo

echo "--- Connectivity ---"
check "SSH works as admin" "whoami" "admin"
check "Hostname resolves" "hostname" "localhost"

echo
echo "--- Packages (from cloud-init) ---"
check "Ansible installed" "which ansible" "/usr/bin/ansible"
check "Git installed" "which git" "/usr/bin/git"
check "Python 3 installed" "which python3" "/usr/bin/python3"

echo
echo "--- Repository (from cloud-init runcmd) ---"
check "Repo cloned" "test -d /home/admin/its25-virt-automation && echo OK" "OK"
check "Playbook exists" \
  "test -f /home/admin/its25-virt-automation/ansible/playbooks/site.yml && echo OK" \
  "OK"
check "Role exists" \
  "test -d /home/admin/its25-virt-automation/ansible/roles/control_node_check && echo OK" \
  "OK"

echo
echo "--- Galaxy collections (from cloud-init runcmd) ---"
check "Infisical collection installed" \
  "ls /home/admin/its25-virt-automation/ansible/collections/ansible_collections/infisical/vault 2>&1 || ls /home/admin/.ansible/collections/ansible_collections/infisical/vault 2>&1" \
  "MANIFEST"

echo
echo "--- Playbook execution ---"
check "Playbook first run succeeds" \
  "cd /home/admin/its25-virt-automation/ansible && ansible-playbook playbooks/site.yml --start-at-task='Confirm Python and connectivity' | grep 'control-node ' | tail -1" \
  "failed=0"

check "Playbook second run is idempotent (changed=0)" \
  "cd /home/admin/its25-virt-automation/ansible && ansible-playbook playbooks/site.yml --start-at-task='Confirm Python and connectivity' | grep 'control-node ' | tail -1" \
  "changed=0"

echo
echo "=========================================="
printf "Results: ${GREEN}%d${NC} passed, ${RED}%d${NC} failed\n" "$PASS" "$FAIL"
echo "=========================================="

exit "$FAIL"
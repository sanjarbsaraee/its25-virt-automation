#!/bin/bash
# Proves iter 1 works end-to-end. Without this, the only
# way to verify a deploy is manual SSH and eyeballing.
#
# Usage:   ./scripts/verify-iter1.sh <control-node-ip>
# Example: ./scripts/verify-iter1.sh 192.168.50.110

set -u

CONTROL_IP="${1:?Usage: $0 <control-node-ip>}"
USER="automation"
REPO="/home/$USER/its25-virt-automation"
ANSIBLE="$REPO/ansible"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

# SSHs into the control-node, runs a command, checks
# if the output contains the expected substring.
check() {
  local description=$1
  local command=$2
  local expected=$3
  local result
  result=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "$USER@$CONTROL_IP" "$command" 2>/dev/null)

  if echo "$result" | grep -q "$expected"; then
    echo -e "${GREEN}✓${NC} $description"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}✗${NC} $description"
    echo "  Expected: $expected"
    echo "  Got:      $result"
    FAIL=$((FAIL + 1))
  fi
}

echo "=========================================="
echo " Iter 1 — control-node $CONTROL_IP"
echo "=========================================="

echo
echo "--- Connectivity ---"
check "SSH login"       "whoami"   "$USER"
check "Hostname set"    "hostname" "control-node"

echo
echo "--- Packages ---"
check "Ansible installed"  "which ansible"  "/usr/bin/ansible"
check "Git installed"      "which git"      "/usr/bin/git"
check "Python 3 installed" "which python3"  "/usr/bin/python3"

echo
echo "--- Repository ---"
check "Repo cloned"      "test -d $REPO && echo OK"                       "OK"
check "Playbook exists"  "test -f $ANSIBLE/playbooks/site.yml && echo OK"  "OK"
check "Role exists"      "test -d $ANSIBLE/roles/control_node_check && echo OK" "OK"

echo
echo "--- Galaxy ---"
check "Infisical collection" \
  "ls $ANSIBLE/collections/ansible_collections/infisical/vault 2>&1" \
  "MANIFEST"

echo
echo "--- Playbook ---"
# Runs the playbook twice. First checks it succeeds,
# second checks nothing changed (idempotency).
check "First run succeeds" \
  "cd $ANSIBLE && ansible-playbook playbooks/site.yml \
    --start-at-task='Confirm Python and connectivity' \
    | grep 'control-node' | tail -1" \
  "failed=0"

check "Second run idempotent" \
  "cd $ANSIBLE && ansible-playbook playbooks/site.yml \
    --start-at-task='Confirm Python and connectivity' \
    | grep 'control-node' | tail -1" \
  "changed=0"

echo
echo "=========================================="
printf "Results: ${GREEN}%d${NC} passed, ${RED}%d${NC} failed\n" "$PASS" "$FAIL"
echo "=========================================="

exit "$FAIL"
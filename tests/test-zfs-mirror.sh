#!/usr/bin/env bash
# test-zfs-mirror.sh — Test ZFS mirror: create → write → fail → replace → resilver → verify

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "ZFS Mirror (Failure + Resilver)"

# ── Cleanup any previous state ──
cleanup_zfs
cleanup_lvm
cleanup_raid

# ── 1. Create mirror pool ──
info "Creating ZFS mirror pool 'tank' with /dev/vdb + /dev/vdc..."
ssh_exec "sudo zpool create tank mirror /dev/vdb /dev/vdc"
assert_ok "Create ZFS mirror pool"

# ── 2. Verify pool ──
pool_status=$(ssh_exec "sudo zpool status tank")
assert_contains "$pool_status" "ONLINE" "Pool state is ONLINE"

# ── 3. Write data ──
ssh_exec "echo 'zfs-mirror-test-data' | sudo tee /tank/test.txt"
assert_ok "Write test file"

read_back=$(ssh_exec "cat /tank/test.txt")
assert_contains "$read_back" "zfs-mirror-test-data" "Read back test file content"

# ── 4. Offline /dev/vdc → verify DEGRADED ──
info "Simulating disk failure: offlining /dev/vdc..."
ssh_exec "sudo zpool offline tank /dev/vdc"
assert_ok "Offline /dev/vdc"

pool_status=$(ssh_exec "sudo zpool status tank")
assert_contains "$pool_status" "DEGRADED" "Pool is DEGRADED after offline"

# ── 5. Data still accessible ──
read_back=$(ssh_exec "cat /tank/test.txt")
assert_contains "$read_back" "zfs-mirror-test-data" "Data accessible while degraded"

# ── 6. Bring disk back online → resilver ──
info "Bringing /dev/vdc back online (simulating replacement)..."
ssh_exec "sudo zpool online tank /dev/vdc"
assert_ok "Online /dev/vdc (replacement)"

# Wait for resilver
info "Waiting for resilver to complete..."
retries=0
while (( retries < 30 )); do
    pool_status=$(ssh_exec "sudo zpool status tank" 2>/dev/null) || true
    if echo "$pool_status" | grep -q "state: ONLINE"; then
        break
    fi
    sleep 1
    retries=$(( retries + 1 ))
done

pool_status=$(ssh_exec "sudo zpool status tank")
assert_contains "$pool_status" "ONLINE" "Pool is ONLINE after resilver"
assert_not_contains "$pool_status" "DEGRADED" "Pool is no longer DEGRADED"

# ── 7. Verify data intact ──
read_back=$(ssh_exec "cat /tank/test.txt")
assert_contains "$read_back" "zfs-mirror-test-data" "Data intact after resilver"

# ── 8. Cleanup ──
info "Cleaning up..."
ssh_exec "sudo zpool destroy -f tank 2>/dev/null || true"
ssh_exec "sudo wipefs -a /dev/vdb /dev/vdc 2>/dev/null || true"
assert_ok "Cleanup ZFS mirror"

test_end
report_results

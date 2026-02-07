#!/usr/bin/env bash
# test-zfs-pool.sh — Test ZFS pool: mirror → datasets → snapshot → rollback → destroy

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "ZFS Pool (Mirror + Datasets + Snapshots)"

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
assert_contains "$pool_status" "mirror" "Pool has mirror vdev"

pool_list=$(ssh_exec "sudo zpool list -H -o name")
assert_contains "$pool_list" "tank" "Pool 'tank' appears in zpool list"

# ── 3. Create datasets ──
ssh_exec "sudo zfs create tank/data"
assert_ok "Create dataset tank/data"

ssh_exec "sudo zfs create tank/logs"
assert_ok "Create dataset tank/logs"

ds_list=$(ssh_exec "sudo zfs list -H -o name -r tank")
assert_contains "$ds_list" "tank/data" "Dataset tank/data exists"
assert_contains "$ds_list" "tank/logs" "Dataset tank/logs exists"

# ── 4. Set properties ──
ssh_exec "sudo zfs set quota=2G tank/data"
assert_ok "Set quota on tank/data"

ssh_exec "sudo zfs set compression=lz4 tank/logs"
assert_ok "Set compression on tank/logs"

quota_val=$(ssh_exec "sudo zfs get -H -o value quota tank/data")
assert_contains "$quota_val" "2G" "Quota is 2G on tank/data"

comp_val=$(ssh_exec "sudo zfs get -H -o value compression tank/logs")
assert_contains "$comp_val" "lz4" "Compression is lz4 on tank/logs"

# ── 5. Write data ──
ssh_exec "echo 'original-zfs-test-data' | sudo tee /tank/data/test.txt"
assert_ok "Write test file to tank/data"

read_back=$(ssh_exec "cat /tank/data/test.txt")
assert_contains "$read_back" "original-zfs-test-data" "Read back test file content"

# ── 6. Snapshot ──
ssh_exec "sudo zfs snapshot tank/data@snap1"
assert_ok "Create snapshot tank/data@snap1"

snap_list=$(ssh_exec "sudo zfs list -t snapshot -H -o name")
assert_contains "$snap_list" "tank/data@snap1" "Snapshot appears in list"

# ── 7. Modify data ──
ssh_exec "echo 'modified-data-after-snapshot' | sudo tee /tank/data/test.txt"
assert_ok "Modify test file"

read_back=$(ssh_exec "cat /tank/data/test.txt")
assert_contains "$read_back" "modified-data-after-snapshot" "File contains modified data"

# ── 8. Rollback ──
ssh_exec "sudo zfs rollback tank/data@snap1"
assert_ok "Rollback to snapshot"

read_back=$(ssh_exec "cat /tank/data/test.txt")
assert_contains "$read_back" "original-zfs-test-data" "Data restored to original after rollback"

# ── 9. Cleanup ──
info "Cleaning up..."
ssh_exec "sudo zpool destroy -f tank 2>/dev/null || true"
ssh_exec "sudo wipefs -a /dev/vdb /dev/vdc 2>/dev/null || true"
assert_ok "Cleanup ZFS pool"

test_end
report_results

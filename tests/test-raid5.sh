#!/usr/bin/env bash
# test-raid5.sh — Test RAID 5 (striping+parity): create → verify → fail → rebuild → destroy

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "RAID 5 (Striping+Parity)"

# ── Cleanup any previous state ──
cleanup_lvm
cleanup_raid

# ── 1. Create RAID 5 ──
info "Creating RAID 5 array with /dev/vdb + /dev/vdc + /dev/vdd..."
ssh_exec "sudo mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/vdb /dev/vdc /dev/vdd --metadata=1.2 --run"
assert_ok "Create RAID 5 array"

# Wait for initial sync to complete
info "Waiting for initial sync..."
ssh_exec "sudo mdadm --wait /dev/md0 2>/dev/null || true"

# ── 2. Verify level and state ──
mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "md0" "md0 appears in /proc/mdstat"
assert_contains "$mdstat" "raid5" "RAID level is raid5"

detail=$(ssh_exec "sudo mdadm --detail /dev/md0")
assert_contains "$detail" "raid5" "mdadm detail shows raid5"
assert_contains "$detail" "active" "Array state is active"

# ── 3. Create filesystem, mount, write/read ──
ssh_exec "sudo mkfs.ext4 -F /dev/md0"
assert_ok "Create ext4 filesystem"

ssh_exec "sudo mkdir -p /mnt/raid5 && sudo mount /dev/md0 /mnt/raid5"
assert_ok "Mount RAID 5 at /mnt/raid5"

ssh_exec "echo 'raid5-parity-test' | sudo tee /mnt/raid5/test.txt"
assert_ok "Write test file"

read_back=$(ssh_exec "cat /mnt/raid5/test.txt")
assert_contains "$read_back" "raid5-parity-test" "Read back test file content"

# ── 4. Fail /dev/vdd → verify degraded ──
info "Simulating disk failure on /dev/vdd..."
ssh_exec "sudo mdadm /dev/md0 --fail /dev/vdd"
assert_ok "Mark /dev/vdd as failed"

detail=$(ssh_exec "sudo mdadm --detail /dev/md0")
assert_contains "$detail" "faulty" "mdadm detail shows faulty disk"
assert_contains "$detail" "degraded" "Array shows degraded state"

# ── 5. Remove, wipe, re-add /dev/vdd → rebuild ──
ssh_exec "sudo mdadm /dev/md0 --remove /dev/vdd"
assert_ok "Remove /dev/vdd from array"

info "Wiping and re-adding /dev/vdd..."
ssh_exec "sudo dd if=/dev/zero of=/dev/vdd bs=1M count=10 2>/dev/null; sync"
ssh_exec "sudo mdadm /dev/md0 --add /dev/vdd"
assert_ok "Re-add /dev/vdd to array"

# Wait for rebuild
info "Waiting for rebuild to complete..."
sleep 5
ssh_exec "sudo mdadm --wait /dev/md0 2>/dev/null || true"

mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "UUU" "Array is healthy (UUU) after rebuild"

# ── 6. Verify data intact ──
read_back=$(ssh_exec "cat /mnt/raid5/test.txt")
assert_contains "$read_back" "raid5-parity-test" "Data intact after rebuild"

# ── 7. Cleanup ──
info "Cleaning up..."
ssh_exec "sudo umount /mnt/raid5 2>/dev/null || true"
ssh_exec "sudo mdadm --stop /dev/md0 2>/dev/null || true"
ssh_exec "sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd 2>/dev/null || true"
assert_ok "Cleanup RAID 5"

test_end
report_results

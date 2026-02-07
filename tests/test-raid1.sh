#!/usr/bin/env bash
# test-raid1.sh — Test RAID 1 (mirror): create → verify → fail → rebuild → destroy

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "RAID 1 (Mirror)"

# ── Cleanup any previous state ──
cleanup_lvm
cleanup_raid

# ── 1. Create RAID 1 ──
info "Creating RAID 1 array with /dev/vdb + /dev/vdc..."
ssh_exec "sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run"
assert_ok "Create RAID 1 array"

# ── 2. Verify level and state ──
mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "md0" "md0 appears in /proc/mdstat"
assert_contains "$mdstat" "raid1" "RAID level is raid1"

detail=$(ssh_exec "sudo mdadm --detail /dev/md0")
assert_contains "$detail" "raid1" "mdadm detail shows raid1"
assert_contains "$detail" "active" "Array state is active"

# ── 3. Create filesystem, mount, write/read ──
ssh_exec "sudo mkfs.ext4 -F /dev/md0"
assert_ok "Create ext4 filesystem"

ssh_exec "sudo mkdir -p /mnt/raid1 && sudo mount /dev/md0 /mnt/raid1"
assert_ok "Mount RAID 1 at /mnt/raid1"

ssh_exec "echo 'raid1-mirror-test' | sudo tee /mnt/raid1/test.txt"
assert_ok "Write test file"

read_back=$(ssh_exec "cat /mnt/raid1/test.txt")
assert_contains "$read_back" "raid1-mirror-test" "Read back test file content"

# ── 4. Fail /dev/vdc → verify degraded ──
info "Simulating disk failure on /dev/vdc..."
ssh_exec "sudo mdadm /dev/md0 --fail /dev/vdc"
assert_ok "Mark /dev/vdc as failed"

mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "U_|_U" "Array shows degraded state in mdstat"

detail=$(ssh_exec "sudo mdadm --detail /dev/md0")
assert_contains "$detail" "faulty" "mdadm detail shows faulty disk"

# ── 5. Remove /dev/vdc ──
ssh_exec "sudo mdadm /dev/md0 --remove /dev/vdc"
assert_ok "Remove /dev/vdc from array"

# ── 6. Wipe and re-add /dev/vdc → rebuild ──
info "Wiping and re-adding /dev/vdc..."
ssh_exec "sudo dd if=/dev/zero of=/dev/vdc bs=1M count=10 2>/dev/null; sync"
ssh_exec "sudo mdadm /dev/md0 --add /dev/vdc"
assert_ok "Re-add /dev/vdc to array"

# Wait for rebuild
info "Waiting for rebuild to complete..."
sleep 5
ssh_exec "sudo mdadm --wait /dev/md0 2>/dev/null || true"

mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "UU" "Array is healthy (UU) after rebuild"

# ── 7. Verify data still intact ──
read_back=$(ssh_exec "cat /mnt/raid1/test.txt")
assert_contains "$read_back" "raid1-mirror-test" "Data intact after rebuild"

# ── 8. Cleanup ──
info "Cleaning up..."
ssh_exec "sudo umount /mnt/raid1 2>/dev/null || true"
ssh_exec "sudo mdadm --stop /dev/md0 2>/dev/null || true"
ssh_exec "sudo mdadm --zero-superblock /dev/vdb /dev/vdc 2>/dev/null || true"
assert_ok "Cleanup RAID 1"

test_end
report_results

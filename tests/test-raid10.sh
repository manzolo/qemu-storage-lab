#!/usr/bin/env bash
# test-raid10.sh — Test RAID 10 (mirror+stripe): create → verify → fail → rebuild → destroy

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "RAID 10 (Mirror+Stripe)"

# ── Cleanup any previous state ──
cleanup_lvm
cleanup_raid

# ── 1. Create RAID 10 ──
info "Creating RAID 10 array with /dev/vdb + /dev/vdc + /dev/vdd + /dev/vde..."
ssh_exec "sudo mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/vdb /dev/vdc /dev/vdd /dev/vde --metadata=1.2 --run"
assert_ok "Create RAID 10 array"

# Wait for initial sync to complete
info "Waiting for initial sync..."
ssh_exec "sudo mdadm --wait /dev/md0 2>/dev/null || true"

# ── 2. Verify level and state ──
mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "md0" "md0 appears in /proc/mdstat"
assert_contains "$mdstat" "raid10" "RAID level is raid10"

detail=$(ssh_exec "sudo mdadm --detail /dev/md0")
assert_contains "$detail" "raid10" "mdadm detail shows raid10"
assert_contains "$detail" "active" "Array state is active"

# ── 3. Create filesystem, mount, write/read ──
ssh_exec "sudo mkfs.ext4 -F /dev/md0"
assert_ok "Create ext4 filesystem"

ssh_exec "sudo mkdir -p /mnt/raid10 && sudo mount /dev/md0 /mnt/raid10"
assert_ok "Mount RAID 10 at /mnt/raid10"

ssh_exec "echo 'raid10-mirror-stripe-test' | sudo tee /mnt/raid10/test.txt"
assert_ok "Write test file"

read_back=$(ssh_exec "cat /mnt/raid10/test.txt")
assert_contains "$read_back" "raid10-mirror-stripe-test" "Read back test file content"

# ── 4. Fail /dev/vde → verify degraded ──
info "Simulating disk failure on /dev/vde..."
ssh_exec "sudo mdadm /dev/md0 --fail /dev/vde"
assert_ok "Mark /dev/vde as failed"

detail=$(ssh_exec "sudo mdadm --detail /dev/md0")
assert_contains "$detail" "faulty" "mdadm detail shows faulty disk"
assert_contains "$detail" "degraded" "Array shows degraded state"

# ── 5. Remove, wipe, re-add /dev/vde → rebuild ──
ssh_exec "sudo mdadm /dev/md0 --remove /dev/vde"
assert_ok "Remove /dev/vde from array"

info "Wiping and re-adding /dev/vde..."
ssh_exec "sudo dd if=/dev/zero of=/dev/vde bs=1M count=10 2>/dev/null; sync"
ssh_exec "sudo mdadm /dev/md0 --add /dev/vde"
assert_ok "Re-add /dev/vde to array"

# Wait for rebuild
info "Waiting for rebuild to complete..."
sleep 5
ssh_exec "sudo mdadm --wait /dev/md0 2>/dev/null || true"

mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "UUUU" "Array is healthy (UUUU) after rebuild"

# ── 6. Verify data intact ──
read_back=$(ssh_exec "cat /mnt/raid10/test.txt")
assert_contains "$read_back" "raid10-mirror-stripe-test" "Data intact after rebuild"

# ── 7. Cleanup ──
info "Cleaning up..."
ssh_exec "sudo umount /mnt/raid10 2>/dev/null || true"
ssh_exec "sudo mdadm --stop /dev/md0 2>/dev/null || true"
ssh_exec "sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null || true"
assert_ok "Cleanup RAID 10"

test_end
report_results

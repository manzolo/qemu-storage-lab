#!/usr/bin/env bash
# test-raid0.sh — Test RAID 0 (stripe): create → verify → destroy

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "RAID 0 (Stripe)"

# ── Cleanup any previous state ──
cleanup_lvm
cleanup_raid

# ── 1. Create RAID 0 ──
info "Creating RAID 0 array with /dev/vdb + /dev/vdc..."
ssh_exec "sudo mdadm --create /dev/md0 --level=0 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run"
assert_ok "Create RAID 0 array"

# ── 2. Verify in /proc/mdstat ──
mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "md0" "md0 appears in /proc/mdstat"
assert_contains "$mdstat" "raid0" "RAID level is raid0"

# ── 3. Verify with mdadm --detail ──
detail=$(ssh_exec "sudo mdadm --detail /dev/md0")
assert_contains "$detail" "raid0" "mdadm detail shows raid0"
assert_contains "$detail" "active" "Array state is active"

# ── 4. Create filesystem, mount, write/read ──
ssh_exec "sudo mkfs.ext4 -F /dev/md0"
assert_ok "Create ext4 filesystem on RAID 0"

ssh_exec "sudo mkdir -p /mnt/raid0 && sudo mount /dev/md0 /mnt/raid0"
assert_ok "Mount RAID 0 at /mnt/raid0"

ssh_exec "echo 'raid0-test-data' | sudo tee /mnt/raid0/test.txt"
assert_ok "Write test file"

read_back=$(ssh_exec "cat /mnt/raid0/test.txt")
assert_contains "$read_back" "raid0-test-data" "Read back test file content"

# ── 5. Check combined capacity ──
df_out=$(ssh_exec "df -h /mnt/raid0")
assert_contains "$df_out" "/mnt/raid0" "df shows /mnt/raid0 mounted"

# ── 6. Cleanup ──
info "Cleaning up..."
ssh_exec "sudo umount /mnt/raid0 2>/dev/null || true"
ssh_exec "sudo mdadm --stop /dev/md0 2>/dev/null || true"
ssh_exec "sudo mdadm --zero-superblock /dev/vdb /dev/vdc 2>/dev/null || true"
assert_ok "Cleanup RAID 0"

test_end
report_results

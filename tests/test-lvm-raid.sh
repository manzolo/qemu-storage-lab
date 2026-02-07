#!/usr/bin/env bash
# test-lvm-raid.sh — Test LVM on RAID: RAID 1 → PV → VG → LV → mount → cleanup

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "LVM on RAID"

# ── Cleanup any previous state ──
cleanup_lvm
cleanup_raid

# ── 1. Create RAID 1 ──
info "Creating RAID 1 array with /dev/vdb + /dev/vdc..."
ssh_exec "sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run"
assert_ok "Create RAID 1 array"

mdstat=$(ssh_exec "cat /proc/mdstat")
assert_contains "$mdstat" "md0" "md0 appears in /proc/mdstat"

# ── 2. Create PV on RAID array ──
ssh_exec "sudo pvcreate -f /dev/md0"
assert_ok "Create PV on /dev/md0"

pvs_out=$(ssh_exec "sudo pvs")
assert_contains "$pvs_out" "/dev/md0" "pvs shows /dev/md0"

# ── 3. Create VG and LV ──
ssh_exec "sudo vgcreate raid_vg /dev/md0"
assert_ok "Create VG raid_vg"

ssh_exec "sudo lvcreate -L 2G -n secure_lv raid_vg"
assert_ok "Create 2G LV secure_lv"

lvs_out=$(ssh_exec "sudo lvs")
assert_contains "$lvs_out" "secure_lv" "lvs shows secure_lv"

# ── 4. Create filesystem, mount, write/read ──
ssh_exec "sudo mkfs.ext4 -F /dev/raid_vg/secure_lv"
assert_ok "Create ext4 filesystem on LV"

ssh_exec "sudo mkdir -p /mnt/raid-lvm && sudo mount /dev/raid_vg/secure_lv /mnt/raid-lvm"
assert_ok "Mount LV at /mnt/raid-lvm"

ssh_exec "echo 'lvm-raid-test' | sudo tee /mnt/raid-lvm/test.txt"
assert_ok "Write test file"

read_back=$(ssh_exec "cat /mnt/raid-lvm/test.txt")
assert_contains "$read_back" "lvm-raid-test" "Read back test file content"

# ── 5. Cleanup: LVM then RAID ──
info "Cleaning up LVM on RAID..."
ssh_exec "sudo umount /mnt/raid-lvm 2>/dev/null || true"

ssh_exec "sudo lvremove -f /dev/raid_vg/secure_lv"
assert_ok "Remove LV"

ssh_exec "sudo vgremove -f raid_vg"
assert_ok "Remove VG"

ssh_exec "sudo pvremove -f /dev/md0"
assert_ok "Remove PV"

ssh_exec "sudo mdadm --stop /dev/md0"
assert_ok "Stop RAID array"

ssh_exec "sudo mdadm --zero-superblock /dev/vdb /dev/vdc 2>/dev/null || true"
assert_ok "Clear RAID superblocks"

test_end
report_results

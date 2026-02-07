#!/usr/bin/env bash
# test-lvm-basic.sh — Test basic LVM: PV → VG → LV → mount → extend → cleanup

set -euo pipefail
source "$(dirname "$0")/test-common.sh"

setup_vm

test_start "LVM Basic"

# ── Cleanup any previous state ──
cleanup_lvm
cleanup_raid

# ── 1. Create Physical Volumes ──
info "Creating Physical Volumes on /dev/vdb and /dev/vdc..."
ssh_exec "sudo pvcreate -f /dev/vdb /dev/vdc"
assert_ok "Create PVs on vdb and vdc"

pvs_out=$(ssh_exec "sudo pvs")
assert_contains "$pvs_out" "/dev/vdb" "pvs shows /dev/vdb"
assert_contains "$pvs_out" "/dev/vdc" "pvs shows /dev/vdc"

# ── 2. Create Volume Group ──
ssh_exec "sudo vgcreate lab_vg /dev/vdb /dev/vdc"
assert_ok "Create VG lab_vg"

vgs_out=$(ssh_exec "sudo vgs")
assert_contains "$vgs_out" "lab_vg" "vgs shows lab_vg"

# ── 3. Create Logical Volume ──
ssh_exec "sudo lvcreate -L 2G -n data_lv lab_vg"
assert_ok "Create 2G LV data_lv"

lvs_out=$(ssh_exec "sudo lvs")
assert_contains "$lvs_out" "data_lv" "lvs shows data_lv"

# ── 4. Create filesystem, mount, write/read ──
ssh_exec "sudo mkfs.ext4 -F /dev/lab_vg/data_lv"
assert_ok "Create ext4 filesystem on LV"

ssh_exec "sudo mkdir -p /mnt/lvm-data && sudo mount /dev/lab_vg/data_lv /mnt/lvm-data"
assert_ok "Mount LV at /mnt/lvm-data"

ssh_exec "echo 'lvm-basic-test' | sudo tee /mnt/lvm-data/test.txt"
assert_ok "Write test file"

read_back=$(ssh_exec "cat /mnt/lvm-data/test.txt")
assert_contains "$read_back" "lvm-basic-test" "Read back test file content"

# ── 5. Extend LV and resize filesystem ──
info "Extending LV by 1G..."
ssh_exec "sudo lvextend -L +1G /dev/lab_vg/data_lv"
assert_ok "Extend LV by 1G"

ssh_exec "sudo resize2fs /dev/lab_vg/data_lv"
assert_ok "Resize filesystem to fill extended LV"

# Verify new size (should be ~3G now)
lvs_out=$(ssh_exec "sudo lvs --noheadings -o lv_size /dev/lab_vg/data_lv")
assert_contains "$lvs_out" "3" "LV size is now ~3G"

# ── 6. Cleanup ──
info "Cleaning up LVM..."
ssh_exec "sudo umount /mnt/lvm-data 2>/dev/null || true"
ssh_exec "sudo lvremove -f /dev/lab_vg/data_lv"
assert_ok "Remove LV"

ssh_exec "sudo vgremove -f lab_vg"
assert_ok "Remove VG"

ssh_exec "sudo pvremove -f /dev/vdb /dev/vdc"
assert_ok "Remove PVs"

test_end
report_results

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-lvm-on-raid.sh — LVM on RAID 1 (production pattern)
#  Interactive guided tutorial
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/demo-common.sh"

demo_lvm_on_raid() {
    demo_ensure_vm || return 0

    demo_header "LVM on RAID 1 — Production Pattern" \
        "RAID for redundancy + LVM for flexibility: the production architecture"

    # Clean environment
    demo_cleanup_start

    demo_note "Typical production server architecture:
  Physical disks -> RAID (redundancy) -> LVM (flexibility) -> Filesystem
Combines the best of both technologies."

    # Step 1: Inspect disks
    _next_step
    tutor_step "$STEP_COUNT" "Inspect available disks" \
        "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "We'll use vdb and vdc to create a RAID 1 (mirror)
and then use the array as the foundation for LVM." || return 0

    # === RAID LAYER ===
    echo ""
    echo -e "  ${BOLD}${CYAN}  ═══ Layer 1: RAID ═══${RESET}"
    echo ""

    # Step 2: Create RAID 1
    _next_step
    tutor_step "$STEP_COUNT" "Create RAID 1 array" \
        "sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run" \
        "First we create the redundancy layer: RAID 1 mirror.
This protects data from a single disk failure." || return 0

    # Step 3: Verify RAID
    _next_step
    tutor_step "$STEP_COUNT" "Verify RAID array" \
        "cat /proc/mdstat" \
        "The RAID 1 array is the foundation. Waiting for [UU]." \
        "\\[UU\\]" || return 0

    # Wait for sync
    local retries=0
    while (( retries < 30 )); do
        local status
        status=$(ssh_exec "cat /proc/mdstat" 2>/dev/null) || true
        if echo "$status" | grep -q '\[UU\]'; then
            break
        fi
        sleep 1
        retries=$(( retries + 1 ))
    done

    # === LVM LAYER ===
    echo ""
    echo -e "  ${BOLD}${CYAN}  ═══ Layer 2: LVM ═══${RESET}"
    echo ""
    demo_note "Now we create LVM ON TOP of RAID, not on the raw disks.
The PV will be /dev/md0, not /dev/vdb or /dev/vdc."

    # Step 4: Create PV on RAID
    _next_step
    tutor_step "$STEP_COUNT" "Create Physical Volume on RAID" \
        "sudo pvcreate /dev/md0" \
        "pvcreate on /dev/md0 (the RAID array), NOT on individual disks.
LVM will see the RAID as a single physical disk." || return 0

    # Step 5: Verify PV
    _next_step
    tutor_step "$STEP_COUNT" "Verify Physical Volume" \
        "sudo pvs" \
        "The PV is on /dev/md0. LVM doesn't know (and doesn't care)
that there are 2 mirrored disks underneath." || return 0

    # Step 6: Create VG
    _next_step
    tutor_step "$STEP_COUNT" "Create Volume Group" \
        "sudo vgcreate raid_vg /dev/md0" \
        "Create the Volume Group 'raid_vg' on the RAID PV.
All the RAID array's space is now in the LVM pool." || return 0

    # Step 7: Verify VG
    _next_step
    tutor_step "$STEP_COUNT" "Verify Volume Group" \
        "sudo vgs" \
        "The VG shows the available space from the RAID array." || return 0

    # Step 8: Create LV
    _next_step
    tutor_step "$STEP_COUNT" "Create a 2GB Logical Volume" \
        "sudo lvcreate -y -L 2G -n secure_lv raid_vg" \
        "Create a 2GB LV named 'secure_lv'.
Data on this LV is protected by the underlying RAID." || return 0

    # Step 9: Verify LV
    _next_step
    tutor_step "$STEP_COUNT" "Verify Logical Volume" \
        "sudo lvs" \
        "Our 2GB LV in the RAID-backed VG." || return 0

    # === FILESYSTEM LAYER ===
    echo ""
    echo -e "  ${BOLD}${CYAN}  ═══ Layer 3: Filesystem ═══${RESET}"
    echo ""

    # Step 10: Create filesystem
    _next_step
    tutor_step "$STEP_COUNT" "Create ext4 filesystem" \
        "sudo mkfs.ext4 /dev/raid_vg/secure_lv" \
        "Create the filesystem on the LV. This is the layer
that the user/application will interact with." || return 0

    # Step 11: Mount
    _next_step
    tutor_step "$STEP_COUNT" "Mount the filesystem" \
        "sudo mkdir -p /mnt/raid-lvm && sudo mount /dev/raid_vg/secure_lv /mnt/raid-lvm" \
        "Mount on /mnt/raid-lvm. The user sees a simple directory,
but underneath there's LVM on RAID 1." || return 0

    # Step 12: Write data
    _next_step
    tutor_step "$STEP_COUNT" "Write test data" \
        "echo 'Data protected by RAID + managed by LVM' | sudo tee /mnt/raid-lvm/test.txt" \
        "We write data. The full path is:
disk -> RAID mirror -> PV -> VG -> LV -> ext4 -> file" || return 0

    # Step 13: Verify and overview
    _next_step
    tutor_step "$STEP_COUNT" "Full architecture overview" \
        "echo '=== File ===' && cat /mnt/raid-lvm/test.txt && echo '=== Filesystem ===' && df -h /mnt/raid-lvm && echo '=== LVM ===' && sudo pvs && sudo vgs && sudo lvs && echo '=== RAID ===' && cat /proc/mdstat" \
        "Complete view of all layers, from file down to disks.
This is the typical production server architecture." || return 0

    demo_note "Complete architecture:
  /dev/vdb + /dev/vdc -> md0 (RAID 1) -> raid_vg -> secure_lv -> ext4
  Hardware redundancy + software flexibility = production ready!"

    # === CLEANUP ===
    echo ""
    echo -e "  ${BOLD}${CYAN}  ═══ Cleanup ═══${RESET}"
    echo ""
    demo_note "Cleanup must be done top-down:
filesystem -> LVM (LV, VG, PV) -> RAID -> disks"

    # Step 14: Umount
    _next_step
    tutor_step "$STEP_COUNT" "Unmount filesystem" \
        "sudo umount /mnt/raid-lvm" \
        "Unmount the filesystem." || return 0

    # Step 15: Remove LV
    _next_step
    tutor_step "$STEP_COUNT" "Remove Logical Volume" \
        "sudo lvremove -f /dev/raid_vg/secure_lv" \
        "Remove the Logical Volume." || return 0

    # Step 16: Remove VG
    _next_step
    tutor_step "$STEP_COUNT" "Remove Volume Group" \
        "sudo vgremove raid_vg" \
        "Remove the Volume Group." || return 0

    # Step 17: Remove PV
    _next_step
    tutor_step "$STEP_COUNT" "Remove Physical Volume" \
        "sudo pvremove /dev/md0" \
        "Remove the PV from the RAID device." || return 0

    # Step 18: Stop RAID
    _next_step
    tutor_step "$STEP_COUNT" "Stop RAID array" \
        "sudo mdadm --stop /dev/md0 && sudo mdadm --zero-superblock /dev/vdb /dev/vdc 2>/dev/null; echo 'RAID removed'" \
        "Stop the RAID array and clear metadata from the disks." || return 0

    # Step 19: Verify
    _next_step
    tutor_step "$STEP_COUNT" "Verify complete cleanup" \
        "sudo pvs 2>/dev/null; sudo vgs 2>/dev/null; sudo lvs 2>/dev/null; cat /proc/mdstat; echo 'All clean!'" \
        "No LVM or RAID objects should remain." || return 0

    # Summary
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}  ║  LVM on RAID demo completed successfully!           ║${RESET}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}What we learned:${RESET}"
    echo -e "  - Production architecture: RAID underneath + LVM on top"
    echo -e "  - The PV must be created on the RAID device, not individual disks"
    echo -e "  - LVM doesn't know RAID exists underneath (and doesn't need to)"
    echo -e "  - Cleanup must be done top-down"
    echo -e "  - Full stack: disks -> RAID -> PV -> VG -> LV -> filesystem"
    echo ""
    pause
}

# Allow direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_lvm_on_raid
fi

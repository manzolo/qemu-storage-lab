#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-lvm.sh — LVM Base: PV, VG, LV, resize, cleanup
#  Interactive guided tutorial
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/demo-common.sh"

demo_lvm() {
    demo_ensure_vm || return 0

    demo_header "LVM — Logical Volume Manager" \
        "Create Physical Volumes, Volume Group, Logical Volume, resize and cleanup"

    # Clean environment
    demo_cleanup_start

    # Step 1: Inspect disks
    _next_step
    tutor_step "$STEP_COUNT" "Inspect available disks" \
        "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Let's see the available disks. We'll use vdb and vdc as
Physical Volumes for LVM." || return 0

    # Step 2: Create Physical Volumes
    s=$(_next_step)
    demo_note "LVM has 3 layers of abstraction:
1. Physical Volume (PV) — physical disk marked for LVM
2. Volume Group (VG) — pool of aggregated PVs
3. Logical Volume (LV) — 'virtual partition' carved from the VG"
    tutor_step "$s" "Create Physical Volumes (PV)" \
        "sudo pvcreate /dev/vdb /dev/vdc" \
        "pvcreate marks the disks for use with LVM.
It writes LVM metadata at the beginning of each disk." || return 0

    # Step 3: Verify PV
    _next_step
    tutor_step "$STEP_COUNT" "Verify Physical Volumes" \
        "sudo pvs" \
        "pvs shows all Physical Volumes.
Note the size of each PV and that they don't belong to a VG yet." || return 0

    # Step 4: Create Volume Group
    _next_step
    tutor_step "$STEP_COUNT" "Create Volume Group" \
        "sudo vgcreate lab_vg /dev/vdb /dev/vdc" \
        "vgcreate combines the PVs into a single storage pool.
'lab_vg' is the name of our Volume Group." || return 0

    # Step 5: Verify VG
    s=$(_next_step)
    demo_note "The Volume Group aggregates the space of all PVs.
Total size is the sum of the PVs minus a small metadata overhead."
    tutor_step "$s" "Verify Volume Group" \
        "sudo vgs" \
        "vgs shows Volume Groups. Note the combined size
of both disks and the available free space." || return 0

    # Step 6: Create Logical Volume
    _next_step
    tutor_step "$STEP_COUNT" "Create a 2GB Logical Volume" \
        "sudo lvcreate -y -L 2G -n data_lv lab_vg" \
        "lvcreate creates a 2GB Logical Volume named 'data_lv'
inside the Volume Group 'lab_vg'." || return 0

    # Step 7: Verify LV
    _next_step
    tutor_step "$STEP_COUNT" "Verify Logical Volume" \
        "sudo lvs" \
        "lvs shows Logical Volumes. Our 2GB LV has been
created in the VG lab_vg." || return 0

    # Step 8: Create filesystem
    _next_step
    tutor_step "$STEP_COUNT" "Create ext4 filesystem on the LV" \
        "sudo mkfs.ext4 /dev/lab_vg/data_lv" \
        "Create the filesystem on the Logical Volume.
The path /dev/lab_vg/data_lv is a device mapper link." || return 0

    # Step 9: Mount
    _next_step
    tutor_step "$STEP_COUNT" "Mount the Logical Volume" \
        "sudo mkdir -p /mnt/lvm-data && sudo mount /dev/lab_vg/data_lv /mnt/lvm-data" \
        "Mount the LV on /mnt/lvm-data.
From here on it's used like a normal partition." || return 0

    # Step 10: Write data
    _next_step
    tutor_step "$STEP_COUNT" "Write test data" \
        "echo 'Hello from LVM!' | sudo tee /mnt/lvm-data/test.txt && df -h /mnt/lvm-data" \
        "Write a file and check the space.
The filesystem doesn't know it spans 2 physical disks." || return 0

    # Step 11: Full LVM overview
    s=$(_next_step)
    demo_note "The filesystem knows nothing about the physical disks underneath.
LVM completely abstracts the physical layout."
    tutor_step "$s" "Full LVM stack overview" \
        "sudo pvs && echo '--- Volume Groups ---' && sudo vgs && echo '--- Logical Volumes ---' && sudo lvs" \
        "Complete overview: PV, VG and LV.
Note how space flows from bottom to top." || return 0

    # === RESIZE ===
    echo ""
    echo -e "  ${BOLD}${CYAN}  ═══ Section: Live Resize ═══${RESET}"
    echo ""
    demo_note "One of LVM's key advantages: resize volumes without downtime!
With ext4 you can grow online (while mounted)."

    # Step 12: Free space in VG
    _next_step
    tutor_step "$STEP_COUNT" "Check free space in the VG" \
        "sudo vgs lab_vg" \
        "Let's check how much free space is left in the Volume Group.
We can extend the LV up to the total VG free space." || return 0

    # Step 13: Extend LV
    _next_step
    tutor_step "$STEP_COUNT" "Extend the Logical Volume by 1GB" \
        "sudo lvextend -L +1G /dev/lab_vg/data_lv" \
        "lvextend adds 1GB to the LV (from 2GB to 3GB).
But the filesystem doesn't know about the new space yet!" || return 0

    # Step 14: Verify LV grew
    _next_step
    tutor_step "$STEP_COUNT" "Verify: LV grew but filesystem didn't" \
        "echo '--- LV size ---' && sudo lvs lab_vg/data_lv && echo '--- FS size ---' && df -h /mnt/lvm-data" \
        "The LV is 3GB but the filesystem still shows ~2GB.
We need to resize the filesystem to use the added space." || return 0

    # Step 15: Resize filesystem
    s=$(_next_step)
    demo_note "resize2fs extends the ext4 filesystem online (while mounted).
No unmount needed! This only works for growing, not shrinking."
    tutor_step "$s" "Resize filesystem (online!)" \
        "sudo resize2fs /dev/lab_vg/data_lv" \
        "resize2fs extends the ext4 filesystem to fill all available
space in the LV. Works while the filesystem is mounted!" || return 0

    # Step 16: Verify resize
    _next_step
    tutor_step "$STEP_COUNT" "Verify resized filesystem" \
        "df -h /mnt/lvm-data" \
        "The filesystem should now show about 3GB.
The resize happened with zero downtime!" || return 0

    # Step 17: Verify data intact
    _next_step
    tutor_step "$STEP_COUNT" "Verify data is still intact after resize" \
        "cat /mnt/lvm-data/test.txt" \
        "Data written before the resize must still be there." \
        "Hello from LVM" || return 0

    # === CLEANUP ===
    echo ""
    echo -e "  ${BOLD}${CYAN}  ═══ Section: Cleanup ═══${RESET}"
    echo ""
    demo_note "LVM removal must be done in reverse order of creation:
umount -> lvremove -> vgremove -> pvremove"

    # Step 18: Umount
    _next_step
    tutor_step "$STEP_COUNT" "Unmount the filesystem" \
        "sudo umount /mnt/lvm-data" \
        "First we unmount the filesystem." || return 0

    # Step 19: Remove LV
    _next_step
    tutor_step "$STEP_COUNT" "Remove Logical Volume" \
        "sudo lvremove -f /dev/lab_vg/data_lv" \
        "lvremove deletes the Logical Volume.
-f (force) skips the confirmation prompt." || return 0

    # Step 20: Remove VG
    _next_step
    tutor_step "$STEP_COUNT" "Remove Volume Group" \
        "sudo vgremove lab_vg" \
        "vgremove deletes the Volume Group.
The PVs become available again." || return 0

    # Step 21: Remove PV
    _next_step
    tutor_step "$STEP_COUNT" "Remove Physical Volumes" \
        "sudo pvremove /dev/vdb /dev/vdc" \
        "pvremove clears the LVM metadata from the disks.
The disks return to raw state, ready for other uses." || return 0

    # Step 22: Verify cleanup
    _next_step
    tutor_step "$STEP_COUNT" "Verify complete cleanup" \
        "sudo pvs 2>/dev/null; sudo vgs 2>/dev/null; sudo lvs 2>/dev/null; echo 'All clean!'" \
        "No LVM objects should remain." || return 0

    # Summary
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}  ║  LVM demo completed successfully!                   ║${RESET}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}What we learned:${RESET}"
    echo -e "  - LVM abstracts physical disks into flexible logical volumes"
    echo -e "  - Stack: PV (disk) -> VG (pool) -> LV (volume)"
    echo -e "  - LVs can be resized live (grow online with ext4)"
    echo -e "  - Cleanup must be done in reverse order"
    echo -e "  - The filesystem is unaware of the physical layout"
    echo ""
    pause
}

# Allow direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_lvm
fi

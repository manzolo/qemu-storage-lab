#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-raid5.sh — RAID 5 Parity: create, fail, rebuild
#  Interactive guided tutorial
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/demo-common.sh"

demo_raid5() {
    demo_ensure_vm || return 0

    demo_header "RAID 5 — Parity" \
        "Create an array with distributed parity, simulate failure and rebuild"

    # Clean environment
    demo_cleanup_start

    # Step 1: Inspect disks
    _next_step
    tutor_step "$STEP_COUNT" "Inspect available disks" \
        "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Let's see the available disks. RAID 5 requires at least 3 disks.
We'll use vdb, vdc and vdd." || return 0

    # Step 2: Create RAID 5 array
    s=$(_next_step)
    demo_note "RAID 5 distributes data AND parity across all disks.
Usable capacity = (N-1) disks. With 3 x 5GB disks: ~10GB usable.
Tolerates the failure of 1 disk out of N."
    tutor_step "$s" "Create RAID 5 array with 3 disks" \
        "sudo mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/vdb /dev/vdc /dev/vdd --metadata=1.2 --run" \
        "We create a RAID 5 array with vdb, vdc, vdd.
--level=5 means striping with distributed parity." || return 0

    # Step 3: Verify array
    _next_step
    tutor_step "$STEP_COUNT" "Verify array status" \
        "cat /proc/mdstat" \
        "Check that the array is active. You may see the initial sync.
[UUU] means all 3 disks are Up." \
        "raid5" || return 0

    # Wait for initial sync
    echo -e "  ${DIM}Waiting for initial sync...${RESET}"
    local retries=0
    while (( retries < 60 )); do
        local status
        status=$(ssh_exec "cat /proc/mdstat" 2>/dev/null) || true
        if echo "$status" | grep -q '\[UUU\]'; then
            echo -e "  ${GREEN}✓ Sync complete${RESET}"
            break
        fi
        sleep 1
        retries=$(( retries + 1 ))
    done

    # Step 4: Array details
    _next_step
    tutor_step "$STEP_COUNT" "RAID 5 array details" \
        "sudo mdadm --detail /dev/md0" \
        "Note the array size: about 2x a single disk's size.
With 3 disks, 1 disk equivalent is used for parity." \
        "raid5" || return 0

    # Step 5: Create filesystem
    _next_step
    tutor_step "$STEP_COUNT" "Create ext4 filesystem" \
        "sudo mkfs.ext4 -F /dev/md0" \
        "We create an ext4 filesystem on the RAID 5 array.
The array appears as a single device /dev/md0." || return 0

    # Step 6: Mount
    _next_step
    tutor_step "$STEP_COUNT" "Mount the filesystem" \
        "sudo mkdir -p /mnt/raid5 && sudo mount /dev/md0 /mnt/raid5" \
        "Mount the array on /mnt/raid5." || return 0

    # Step 7: Write data
    _next_step
    tutor_step "$STEP_COUNT" "Write test data" \
        "echo 'data protected by RAID 5 parity' | sudo tee /mnt/raid5/test.txt" \
        "We write test data. RAID 5 will distribute the data and parity
across all 3 disks." || return 0

    # Step 8: Verify data and space
    s=$(_next_step)
    demo_note "Data is distributed (striped) across all disks with parity.
Each stripe has a parity block on a different disk (rotation)."
    tutor_step "$s" "Verify data and available space" \
        "cat /mnt/raid5/test.txt && echo '---' && df -h /mnt/raid5" \
        "Verify the data is written and note the size:
it should be about twice a single disk's size." \
        "data protected" || return 0

    # Step 9: Simulate failure
    s=$(_next_step)
    echo ""
    echo -e "  ${RED}${BOLD}  ▼▼▼  DISK FAILURE SIMULATION  ▼▼▼${RESET}"
    echo ""
    demo_note "In RAID 5 we can lose 1 disk out of N without losing data.
Missing data is reconstructed from parity on the fly."
    tutor_step "$s" "Simulate disk vdd failure" \
        "sudo mdadm /dev/md0 --fail /dev/vdd" \
        "We simulate the failure of vdd. The array will continue working
in degraded mode, reconstructing data from parity." || return 0

    # Step 10: Verify degraded
    _next_step
    tutor_step "$STEP_COUNT" "Verify degraded state" \
        "cat /proc/mdstat" \
        "The array should show [UU_] — 2 disks Up, 1 failed.
The array is degraded but operational." \
        "\\[UU_\\]" || return 0

    demo_note "WARNING: In degraded state, if a second disk fails
ALL data is lost! Replace the failed disk as soon as possible."

    # Step 11: Verify data still OK
    _next_step
    tutor_step "$STEP_COUNT" "Verify data is still accessible" \
        "cat /mnt/raid5/test.txt" \
        "Data is still accessible thanks to distributed parity.
The controller reconstructs the missing disk's blocks on the fly." \
        "data protected" || return 0

    # Step 12: Remove failed disk
    _next_step
    tutor_step "$STEP_COUNT" "Remove failed disk" \
        "sudo mdadm /dev/md0 --remove /dev/vdd" \
        "Remove the failed disk from the array." || return 0

    # Step 13: Simulate new disk
    _next_step
    tutor_step "$STEP_COUNT" "Simulate new disk (zero out)" \
        "sudo dd if=/dev/zero of=/dev/vdd bs=1M count=10 2>&1" \
        "Simulate a new disk by zeroing the first few MB." || return 0

    # Step 14: Add disk
    _next_step
    tutor_step "$STEP_COUNT" "Add new disk to array" \
        "sudo mdadm /dev/md0 --add /dev/vdd" \
        "The rebuild will start automatically. With RAID 5 the rebuild
is slower because it needs to recalculate parity." || return 0

    # Step 15: Watch rebuild
    s=$(_next_step)
    demo_note "RAID 5 rebuild requires reading from ALL remaining disks
to reconstruct data + parity for the new disk."
    tutor_step "$s" "Watch rebuild" \
        "cat /proc/mdstat" \
        "If the rebuild is in progress you'll see a progress bar.
When finished: [UUU] — all disks Up." || return 0

    # Wait for rebuild
    echo -e "  ${DIM}Waiting for rebuild to complete...${RESET}"
    retries=0
    while (( retries < 60 )); do
        local status
        status=$(ssh_exec "cat /proc/mdstat" 2>/dev/null) || true
        if echo "$status" | grep -q '\[UUU\]'; then
            echo -e "  ${GREEN}✓ Rebuild complete — array healthy [UUU]${RESET}"
            break
        fi
        sleep 1
        retries=$(( retries + 1 ))
    done

    # Step 16: Verify integrity
    _next_step
    tutor_step "$STEP_COUNT" "Verify data integrity after rebuild" \
        "cat /mnt/raid5/test.txt" \
        "Data must be identical to what we wrote initially." \
        "data protected" || return 0

    # Step 17: Cleanup
    _next_step
    tutor_step "$STEP_COUNT" "Cleanup — unmount and destroy array" \
        "sudo umount /mnt/raid5 && sudo mdadm --stop /dev/md0 && sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd 2>/dev/null; echo 'Cleanup complete'" \
        "Clean up: unmount, stop the array and clear metadata." || return 0

    # Summary
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}  ║  RAID 5 demo completed successfully!                ║${RESET}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}What we learned:${RESET}"
    echo -e "  - RAID 5 uses distributed parity across N disks"
    echo -e "  - Usable capacity: (N-1) disks"
    echo -e "  - Tolerates the failure of 1 disk"
    echo -e "  - Rebuild is more intensive than RAID 1"
    echo -e "  - In degraded state, a second failure = total data loss"
    echo ""
    pause
}

# Allow direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_raid5
fi

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-raid10.sh — RAID 10 Mirror+Stripe: create, fail, rebuild
#  Interactive guided tutorial
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/demo-common.sh"

demo_raid10() {
    demo_ensure_vm || return 0

    demo_header "RAID 10 — Mirror+Stripe" \
        "Combines mirror (RAID 1) and stripe (RAID 0) for performance and redundancy"

    # Clean environment
    demo_cleanup_start

    local s

    # Step 1: Inspect disks
    s=$(_next_step)
    tutor_step "$s" "Inspect available disks" \
        "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "RAID 10 requires at least 4 disks.
We'll use vdb, vdc, vdd and vde." || return 0

    # Step 2: Create RAID 10 array
    s=$(_next_step)
    demo_note "RAID 10 creates mirror pairs (RAID 1), then stripes across them (RAID 0).
With 4 disks: 2 mirror pairs, striped together.
Usable capacity = N/2 disks. Tolerates 1 failure per mirror pair."
    tutor_step "$s" "Create RAID 10 array with 4 disks" \
        "sudo mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/vdb /dev/vdc /dev/vdd /dev/vde --metadata=1.2 --run" \
        "We create a RAID 10 array with all 4 disks.
--level=10 means mirror+stripe." || return 0

    # Step 3: Verify array
    s=$(_next_step)
    tutor_step "$s" "Verify array status" \
        "cat /proc/mdstat" \
        "Check that the array is active with [UUUU] — 4 disks Up.
Note the size: half the total sum of all disks." \
        "raid10" || return 0

    # Wait for initial sync
    echo -e "  ${DIM}Waiting for initial sync...${RESET}"
    local retries=0
    while (( retries < 60 )); do
        local status
        status=$(ssh_exec "cat /proc/mdstat" 2>/dev/null) || true
        if echo "$status" | grep -q '\[UUUU\]'; then
            echo -e "  ${GREEN}✓ Sync complete${RESET}"
            break
        fi
        sleep 1
        retries=$(( retries + 1 ))
    done

    # Step 4: Array details
    s=$(_next_step)
    tutor_step "$s" "RAID 10 array details" \
        "sudo mdadm --detail /dev/md0" \
        "Note the structure: 4 active disks, near layout.
Capacity is about half the total sum." \
        "raid10" || return 0

    # Step 5: Create filesystem
    s=$(_next_step)
    tutor_step "$s" "Create ext4 filesystem" \
        "sudo mkfs.ext4 -F /dev/md0" \
        "Create the filesystem on the RAID 10 array." || return 0

    # Step 6: Mount
    s=$(_next_step)
    tutor_step "$s" "Mount the filesystem" \
        "sudo mkdir -p /mnt/raid10 && sudo mount /dev/md0 /mnt/raid10" \
        "Mount the array on /mnt/raid10." || return 0

    # Step 7: Write data
    s=$(_next_step)
    tutor_step "$s" "Write test data" \
        "echo 'data on RAID 10 mirror+stripe' | sudo tee /mnt/raid10/test.txt" \
        "Data is written to both mirror pairs (stripe)
and duplicated within each pair (mirror)." || return 0

    # Step 8: Verify data and space
    s=$(_next_step)
    demo_note "RAID 10 offers the best read/write performance among redundant RAID levels.
Reads can come from any copy, writes go to all copies."
    tutor_step "$s" "Verify data and space" \
        "cat /mnt/raid10/test.txt && echo '---' && df -h /mnt/raid10" \
        "Capacity is about half the sum of all 4 disks." \
        "data on RAID 10" || return 0

    # Step 9: Simulate failure
    s=$(_next_step)
    echo ""
    echo -e "  ${RED}${BOLD}  ▼▼▼  DISK FAILURE SIMULATION  ▼▼▼${RESET}"
    echo ""
    demo_note "RAID 10 can tolerate 1 disk failure per mirror pair.
Worst case (2 failures in the same pair) = data loss."
    tutor_step "$s" "Simulate disk vde failure" \
        "sudo mdadm /dev/md0 --fail /dev/vde" \
        "We simulate the failure of vde. The array will continue working
because the mirror partner has a copy of the data." || return 0

    # Step 10: Verify degraded
    s=$(_next_step)
    tutor_step "$s" "Verify degraded state" \
        "cat /proc/mdstat" \
        "The array shows one fewer disk but is still operational.
The failed disk's mirror pair serves data from the partner." \
        "\\[UUU_\\]" || return 0

    # Step 11: Verify data still OK
    s=$(_next_step)
    tutor_step "$s" "Verify data is still accessible" \
        "cat /mnt/raid10/test.txt" \
        "Data is intact thanks to the mirror pair." \
        "data on RAID 10" || return 0

    # Step 12: Remove failed disk
    s=$(_next_step)
    tutor_step "$s" "Remove failed disk" \
        "sudo mdadm /dev/md0 --remove /dev/vde" \
        "Remove the failed disk from the array." || return 0

    # Step 13: Simulate new disk
    s=$(_next_step)
    tutor_step "$s" "Simulate new disk (zero out)" \
        "sudo dd if=/dev/zero of=/dev/vde bs=1M count=10 2>&1" \
        "Simulate a new disk by zeroing the first few MB." || return 0

    # Step 14: Add disk
    s=$(_next_step)
    tutor_step "$s" "Add new disk to array" \
        "sudo mdadm /dev/md0 --add /dev/vde" \
        "The rebuild will start automatically.
The mirror copies data from the healthy partner disk." || return 0

    # Step 15: Watch rebuild
    s=$(_next_step)
    demo_note "RAID 10 rebuild is faster than RAID 5 because it only copies
from the mirror partner, without recalculating parity."
    tutor_step "$s" "Watch rebuild" \
        "cat /proc/mdstat" \
        "When the rebuild finishes: [UUUU] — all disks Up." || return 0

    # Wait for rebuild
    echo -e "  ${DIM}Waiting for rebuild to complete...${RESET}"
    retries=0
    while (( retries < 60 )); do
        local status
        status=$(ssh_exec "cat /proc/mdstat" 2>/dev/null) || true
        if echo "$status" | grep -q '\[UUUU\]'; then
            echo -e "  ${GREEN}✓ Rebuild complete — array healthy [UUUU]${RESET}"
            break
        fi
        sleep 1
        retries=$(( retries + 1 ))
    done

    # Step 16: Verify integrity
    s=$(_next_step)
    tutor_step "$s" "Verify data integrity after rebuild" \
        "cat /mnt/raid10/test.txt" \
        "Data must be identical to what we wrote initially." \
        "data on RAID 10" || return 0

    # Step 17: Cleanup
    s=$(_next_step)
    tutor_step "$s" "Cleanup — unmount and destroy array" \
        "sudo umount /mnt/raid10 && sudo mdadm --stop /dev/md0 && sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null; echo 'Cleanup complete'" \
        "Clean up: unmount, stop the array and clear metadata." || return 0

    # Summary
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}  ║  RAID 10 demo completed successfully!               ║${RESET}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}What we learned:${RESET}"
    echo -e "  - RAID 10 combines mirror (redundancy) + stripe (performance)"
    echo -e "  - Requires at least 4 disks, usable capacity = N/2"
    echo -e "  - Tolerates 1 failure per mirror pair"
    echo -e "  - Fast rebuild: copies only from the mirror partner"
    echo -e "  - Ideal for high-performance workloads with redundancy"
    echo ""
    pause
}

# Allow direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_raid10
fi

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-raid1.sh — RAID 1 Mirror: create, fail, rebuild
#  Interactive guided tutorial
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/demo-common.sh"

demo_raid1() {
    demo_ensure_vm || return 0

    demo_header "RAID 1 — Mirror" \
        "Create a mirror, write data, simulate failure, rebuild, verify integrity"

    # Clean environment
    demo_cleanup_start

    # Step 1: Inspect disks
    _next_step
    tutor_step "$STEP_COUNT" "Inspect available disks" \
        "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Let's see which disks are available in the VM.
vdb and vdc are the disks we'll use for RAID 1." || return 0

    # Step 2: Create RAID 1 array
    s=$(_next_step)
    demo_note "RAID 1 creates an identical copy (mirror) of data on both disks.
If one disk fails, the other has a complete copy of all data."
    tutor_step "$s" "Create RAID 1 array" \
        "sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run" \
        "We create a RAID 1 array (/dev/md0) using vdb and vdc.
--level=1 means mirror, --raid-devices=2 is the number of disks." || return 0

    # Step 3: Verify array
    _next_step
    tutor_step "$STEP_COUNT" "Verify array status" \
        "cat /proc/mdstat" \
        "/proc/mdstat shows the status of all RAID arrays in the kernel.
Look for [UU] which means both disks are Up (active)." \
        "\\[UU\\]" || return 0

    # Step 4: Array details
    _next_step
    tutor_step "$STEP_COUNT" "RAID array details" \
        "sudo mdadm --detail /dev/md0" \
        "mdadm --detail shows detailed information about the array:
RAID level, state, number of disks, size, etc." \
        "raid1" || return 0

    # Step 5: Create filesystem
    _next_step
    tutor_step "$STEP_COUNT" "Create ext4 filesystem" \
        "sudo mkfs.ext4 -F /dev/md0" \
        "We create an ext4 filesystem on the RAID array.
The array appears as a single disk /dev/md0." || return 0

    # Step 6: Mount
    _next_step
    tutor_step "$STEP_COUNT" "Mount the filesystem" \
        "sudo mkdir -p /mnt/raid1 && sudo mount /dev/md0 /mnt/raid1" \
        "We mount the RAID array on /mnt/raid1.
From here on we can use it like a normal directory." || return 0

    # Step 7: Write data
    _next_step
    tutor_step "$STEP_COUNT" "Write test data" \
        "echo 'important data on RAID 1 mirror' | sudo tee /mnt/raid1/test.txt" \
        "We write a test file. This data will be automatically
copied to both disks by the RAID controller." || return 0

    # Step 8: Verify data
    s=$(_next_step)
    demo_note "This data exists on both disks (vdb and vdc).
If either one fails, we won't lose anything."
    tutor_step "$s" "Verify written data" \
        "cat /mnt/raid1/test.txt" \
        "Read the file to confirm the data was written." \
        "important data" || return 0

    # Step 9: Simulate failure
    s=$(_next_step)
    echo ""
    echo -e "  ${RED}${BOLD}  ▼▼▼  DISK FAILURE SIMULATION  ▼▼▼${RESET}"
    echo ""
    demo_note "On a real server, the disk would physically break.
Here we simulate the failure with mdadm --fail."
    tutor_step "$s" "Simulate disk vdc failure" \
        "sudo mdadm /dev/md0 --fail /dev/vdc" \
        "We mark /dev/vdc as failed in the array.
RAID 1 will continue working with the healthy disk only." || return 0

    # Step 10: Verify degraded
    _next_step
    tutor_step "$STEP_COUNT" "Verify degraded state" \
        "cat /proc/mdstat" \
        "The array should now show [U_] — one disk Up, one missing.
The array is degraded but still functional!" \
        "\\[U_\\]" || return 0

    demo_note "The array still works! Data is readable from the healthy disk (vdb).
This is the advantage of RAID 1: fault tolerance."

    # Step 11: Verify data still OK
    _next_step
    tutor_step "$STEP_COUNT" "Verify data is still accessible" \
        "cat /mnt/raid1/test.txt" \
        "Even with a failed disk, our data is still accessible.
RAID serves data from the working disk." \
        "important data" || return 0

    # Step 12: Remove failed disk
    _next_step
    tutor_step "$STEP_COUNT" "Remove failed disk from array" \
        "sudo mdadm /dev/md0 --remove /dev/vdc" \
        "We remove the failed disk from the array.
On a real server, you would now physically remove the disk." || return 0

    # Step 13: Simulate new disk
    s=$(_next_step)
    demo_note "On a real server, you would physically replace the disk.
Here we simulate a new disk by zeroing the first few MB."
    tutor_step "$s" "Simulate new disk (zero out)" \
        "sudo dd if=/dev/zero of=/dev/vdc bs=1M count=10 2>&1" \
        "We zero the first 10MB of vdc to simulate a new disk.
This removes any residual RAID metadata." || return 0

    # Step 14: Add disk
    _next_step
    tutor_step "$STEP_COUNT" "Add new disk to array" \
        "sudo mdadm /dev/md0 --add /dev/vdc" \
        "We add the 'new' disk to the array.
The rebuild (reconstruction) will start automatically." || return 0

    # Step 15: Watch rebuild
    s=$(_next_step)
    demo_note "The rebuild copies all data from the healthy disk to the new one.
On large disks this can take hours. Here it will be instant."
    tutor_step "$s" "Watch rebuild progress" \
        "cat /proc/mdstat" \
        "If the rebuild is still in progress you'll see a progress bar.
When finished, it will return to [UU] — both disks Up." || return 0

    # Wait for rebuild if needed
    echo -e "  ${DIM}Waiting for rebuild to complete...${RESET}"
    local retries=0
    while (( retries < 30 )); do
        local status
        status=$(ssh_exec "cat /proc/mdstat" 2>/dev/null) || true
        if echo "$status" | grep -q '\[UU\]'; then
            echo -e "  ${GREEN}✓ Rebuild complete — array healthy [UU]${RESET}"
            break
        fi
        sleep 1
        retries=$(( retries + 1 ))
    done

    # Step 16: Verify integrity
    _next_step
    tutor_step "$STEP_COUNT" "Verify data integrity after rebuild" \
        "cat /mnt/raid1/test.txt" \
        "After the rebuild, we verify the data is still intact.
The file must be identical to what we wrote initially." \
        "important data" || return 0

    # Step 17: Cleanup
    _next_step
    tutor_step "$STEP_COUNT" "Cleanup — unmount and destroy array" \
        "sudo umount /mnt/raid1 && sudo mdadm --stop /dev/md0 && sudo mdadm --zero-superblock /dev/vdb /dev/vdc 2>/dev/null; echo 'Cleanup complete'" \
        "Clean up everything: unmount the filesystem, stop the array
and clear RAID metadata from the disks." || return 0

    # Summary
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}  ║  RAID 1 demo completed successfully!                ║${RESET}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}What we learned:${RESET}"
    echo -e "  - RAID 1 creates a mirror copy across 2 disks"
    echo -e "  - If one disk fails, data remains accessible"
    echo -e "  - Rebuild automatically restores redundancy"
    echo -e "  - Usable capacity is that of a single disk"
    echo ""
    pause
}

# Allow direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_raid1
fi

#!/usr/bin/env bash
# raid-labs.sh — mdadm RAID labs (create, status, fail, rebuild)

# Guard against double-sourcing
[[ -n "${_RAID_LABS_LOADED:-}" ]] && return 0
_RAID_LABS_LOADED=1

# ── Source dependencies ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ssh-utils.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vm-manager.sh"

# ── Helper: ensure VM + SSH are ready ──
_raid_ensure_vm() {
    if ! vm_is_running; then
        error "VM is not running. Start it from the VM Management menu."
        return 1
    fi
    if ! ssh_check; then
        error "VM is running but SSH is not reachable."
        return 1
    fi
}

# ── RAID 1 Lab (mirror) ──
raid_lab_raid1() {
    _raid_ensure_vm || return 1

    section "Lab: Create RAID 1 (Mirror) with /dev/vdb + /dev/vdc"

    cat << 'EOF'
  RAID 1 creates an exact copy (mirror) of data on two disks.
  If one disk fails, the other has a complete copy of all data.

  What we'll do:
  1. Check available disks
  2. Create a RAID 1 array (/dev/md0) using /dev/vdb and /dev/vdc
  3. Create a filesystem and mount it
  4. Verify the array is working
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: Let's see what disks are available in the VM"

    ssh_exec_show "sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run" \
        "Step 2: Create RAID 1 array /dev/md0 with vdb and vdc"

    ssh_exec_show "cat /proc/mdstat" \
        "Step 3: Check /proc/mdstat — the kernel's view of RAID arrays"

    ssh_exec_show "sudo mdadm --detail /dev/md0" \
        "Step 4: Detailed RAID array information"

    ssh_exec_show "sudo mkfs.ext4 -F /dev/md0" \
        "Step 5: Create ext4 filesystem on the RAID array"

    ssh_exec_show "sudo mkdir -p /mnt/raid1 && sudo mount /dev/md0 /mnt/raid1" \
        "Step 6: Mount the RAID array"

    ssh_exec_show "echo 'Hello from RAID 1!' | sudo tee /mnt/raid1/test.txt && ls -la /mnt/raid1/" \
        "Step 7: Write a test file to verify the array works"

    ssh_exec_show "df -h /mnt/raid1" \
        "Step 8: Check space — notice it's the size of ONE disk (mirrored)"

    success "RAID 1 array created and mounted at /mnt/raid1!"
    echo -e "${CYAN}  The data on /dev/vdb and /dev/vdc is now identical.${RESET}"
    echo -e "${CYAN}  You can simulate a failure from the RAID Labs menu.${RESET}"
    pause
}

# ── RAID 0 Lab (stripe) ──
raid_lab_raid0() {
    _raid_ensure_vm || return 1

    section "Lab: Create RAID 0 (Stripe) with /dev/vdb + /dev/vdc"

    cat << 'EOF'
  RAID 0 stripes data across disks for maximum performance.
  WARNING: No redundancy! If ANY disk fails, ALL data is lost.

  What we'll do:
  1. Create a RAID 0 array (/dev/md0) using /dev/vdb and /dev/vdc
  2. Create a filesystem and mount it
  3. Observe that capacity = sum of all disks
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: Available disks"

    ssh_exec_show "sudo mdadm --create /dev/md0 --level=0 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run" \
        "Step 2: Create RAID 0 array"

    ssh_exec_show "cat /proc/mdstat" \
        "Step 3: Check /proc/mdstat — notice the array size is 2x a single disk"

    ssh_exec_show "sudo mdadm --detail /dev/md0" \
        "Step 4: Array details"

    ssh_exec_show "sudo mkfs.ext4 -F /dev/md0" \
        "Step 5: Create filesystem"

    ssh_exec_show "sudo mkdir -p /mnt/raid0 && sudo mount /dev/md0 /mnt/raid0" \
        "Step 6: Mount the array"

    ssh_exec_show "df -h /mnt/raid0" \
        "Step 7: Check capacity — it's the COMBINED size of both disks"

    success "RAID 0 array created at /mnt/raid0!"
    echo -e "${YELLOW}  Remember: RAID 0 has NO redundancy. Don't use it for important data!${RESET}"
    pause
}

# ── RAID 5 Lab (striping + parity) ──
raid_lab_raid5() {
    _raid_ensure_vm || return 1

    section "Lab: Create RAID 5 (Striping+Parity) with /dev/vdb + /dev/vdc + /dev/vdd"

    cat << 'EOF'
  RAID 5 stripes data across disks with distributed parity.
  Can survive ONE disk failure. Needs minimum 3 disks.

  What we'll do:
  1. Check available disks
  2. Create a RAID 5 array (/dev/md0) using /dev/vdb, /dev/vdc, /dev/vdd
  3. Create a filesystem and mount it
  4. Verify the array is working

  Usable capacity = (N-1) × disk size = 2 × disk size
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: Let's see what disks are available in the VM"

    ssh_exec_show "sudo mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/vdb /dev/vdc /dev/vdd --metadata=1.2 --run" \
        "Step 2: Create RAID 5 array /dev/md0 with vdb, vdc, and vdd"

    ssh_exec_show "cat /proc/mdstat" \
        "Step 3: Check /proc/mdstat — the kernel's view of RAID arrays"

    ssh_exec_show "sudo mdadm --detail /dev/md0" \
        "Step 4: Detailed RAID array information"

    ssh_exec_show "sudo mkfs.ext4 -F /dev/md0" \
        "Step 5: Create ext4 filesystem on the RAID array"

    ssh_exec_show "sudo mkdir -p /mnt/raid5 && sudo mount /dev/md0 /mnt/raid5" \
        "Step 6: Mount the RAID array"

    ssh_exec_show "echo 'Hello from RAID 5!' | sudo tee /mnt/raid5/test.txt && ls -la /mnt/raid5/" \
        "Step 7: Write a test file to verify the array works"

    ssh_exec_show "df -h /mnt/raid5" \
        "Step 8: Check space — capacity is (N-1) × disk size (one disk for parity)"

    success "RAID 5 array created and mounted at /mnt/raid5!"
    echo -e "${CYAN}  Data is striped with parity across /dev/vdb, /dev/vdc, /dev/vdd.${RESET}"
    echo -e "${CYAN}  The array can survive the failure of any ONE disk.${RESET}"
    pause
}

# ── RAID 10 Lab (mirror + stripe) ──
raid_lab_raid10() {
    _raid_ensure_vm || return 1

    section "Lab: Create RAID 10 (Mirror+Stripe) with 4 disks"

    cat << 'EOF'
  RAID 10 combines mirroring and striping: data is mirrored first,
  then striped across mirror pairs. Needs minimum 4 disks.

  Layout:
    [vdb + vdc] = mirror pair 1
    [vdd + vde] = mirror pair 2
    Stripe across both pairs → speed + redundancy
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: We need all 4 data disks"

    ssh_exec_show "sudo mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/vdb /dev/vdc /dev/vdd /dev/vde --metadata=1.2 --run" \
        "Step 2: Create RAID 10 array with all 4 disks"

    ssh_exec_show "cat /proc/mdstat" \
        "Step 3: /proc/mdstat"

    ssh_exec_show "sudo mdadm --detail /dev/md0" \
        "Step 4: Array details — capacity is 50% of total (mirrored)"

    ssh_exec_show "sudo mkfs.ext4 -F /dev/md0" \
        "Step 5: Create filesystem"

    ssh_exec_show "sudo mkdir -p /mnt/raid10 && sudo mount /dev/md0 /mnt/raid10" \
        "Step 6: Mount"

    ssh_exec_show "df -h /mnt/raid10" \
        "Step 7: Usable space = ~50% of total disk capacity"

    success "RAID 10 array created at /mnt/raid10!"
    echo -e "${CYAN}  This is the best choice for databases: fast AND redundant.${RESET}"
    pause
}

# ── RAID Status ──
raid_lab_status() {
    _raid_ensure_vm || return 1

    section "RAID Array Status"

    ssh_exec_show "cat /proc/mdstat" \
        "/proc/mdstat — Quick overview of all RAID arrays"

    echo -e "${CYAN}Reading the output:${RESET}"
    echo "  'UU'  = both disks Up (healthy)"
    echo "  'U_'  = one disk Up, one missing (degraded)"
    echo "  '[>.]' = rebuild/sync in progress"
    echo ""

    # Show detail for each active md device
    local md_devs
    md_devs=$(ssh_exec "ls /dev/md* 2>/dev/null || true" | tr '\n' ' ')
    for md in $md_devs; do
        # Skip md/ directory entry
        [[ "$md" == "/dev/md" ]] && continue
        [[ "$md" == "/dev/md/" ]] && continue
        ssh_exec_show "sudo mdadm --detail $md 2>/dev/null || true" \
            "Detailed status of $md"
    done

    pause
}

# ── Simulate Disk Failure ──
raid_lab_fail_disk() {
    _raid_ensure_vm || return 1

    section "Lab: Simulate Disk Failure"

    cat << 'EOF'
  We'll tell mdadm to mark a disk as "failed" — simulating a real
  disk failure. The array should continue working in degraded mode.
EOF
    echo ""

    ssh_exec_show "cat /proc/mdstat" \
        "Current RAID status before failure simulation"

    echo ""
    echo -e "${BOLD}Which disk to fail?${RESET}"
    echo "  1) /dev/vdb"
    echo "  2) /dev/vdc"
    echo "  3) /dev/vdd"
    echo "  4) /dev/vde"
    echo ""
    echo -n "  Choice [1-4]: "
    read -r choice

    local disk
    case "$choice" in
        1) disk="/dev/vdb" ;;
        2) disk="/dev/vdc" ;;
        3) disk="/dev/vdd" ;;
        4) disk="/dev/vde" ;;
        *) error "Invalid choice."; return 1 ;;
    esac

    ssh_exec_show "sudo mdadm /dev/md0 --fail $disk" \
        "Marking $disk as FAILED in /dev/md0"

    ssh_exec_show "cat /proc/mdstat" \
        "RAID status after failure — notice the degraded state"

    ssh_exec_show "sudo mdadm --detail /dev/md0" \
        "Detailed view — look for 'faulty' status"

    echo -e "${YELLOW}  The array is now DEGRADED but still functional!${RESET}"
    echo -e "${CYAN}  Data is still accessible. Next step: remove the failed disk.${RESET}"
    pause
}

# ── Remove Failed Disk ──
raid_lab_remove_disk() {
    _raid_ensure_vm || return 1

    section "Lab: Remove Failed Disk from Array"

    cat << 'EOF'
  After a disk fails, you must remove it before adding a replacement.
  In a real server, this is when you'd physically pull out the bad drive.
EOF
    echo ""

    echo -e "${BOLD}Which disk to remove?${RESET}"
    echo "  1) /dev/vdb"
    echo "  2) /dev/vdc"
    echo "  3) /dev/vdd"
    echo "  4) /dev/vde"
    echo ""
    echo -n "  Choice [1-4]: "
    read -r choice

    local disk
    case "$choice" in
        1) disk="/dev/vdb" ;;
        2) disk="/dev/vdc" ;;
        3) disk="/dev/vdd" ;;
        4) disk="/dev/vde" ;;
        *) error "Invalid choice."; return 1 ;;
    esac

    ssh_exec_show "sudo mdadm /dev/md0 --remove $disk" \
        "Removing $disk from /dev/md0"

    ssh_exec_show "cat /proc/mdstat" \
        "RAID status — disk has been removed"

    ssh_exec_show "sudo mdadm --detail /dev/md0" \
        "Detailed status after removal"

    echo -e "${CYAN}  Disk removed. In a real server, you'd now swap the physical drive.${RESET}"
    echo -e "${CYAN}  Then add the new disk to the array to start rebuild.${RESET}"
    pause
}

# ── Replace & Rebuild ──
raid_lab_replace_disk() {
    _raid_ensure_vm || return 1

    section "Lab: Replace Disk & Rebuild Array"

    cat << 'EOF'
  In a real scenario, you'd:
  1. Physically replace the failed drive
  2. Add the new drive to the array
  3. Wait for rebuild (data is re-synchronized)

  We simulate the physical replacement by recreating the qcow2 on the host.
EOF
    echo ""

    echo -e "${BOLD}Which disk number to replace?${RESET}"
    echo "  1) /dev/vdb (data-01)"
    echo "  2) /dev/vdc (data-02)"
    echo "  3) /dev/vdd (data-03)"
    echo "  4) /dev/vde (data-04)"
    echo ""
    echo -n "  Choice [1-4]: "
    read -r choice

    local disk disk_letter
    case "$choice" in
        1) disk="/dev/vdb"; disk_letter="b" ;;
        2) disk="/dev/vdc"; disk_letter="c" ;;
        3) disk="/dev/vdd"; disk_letter="d" ;;
        4) disk="/dev/vde"; disk_letter="e" ;;
        *) error "Invalid choice."; return 1 ;;
    esac

    info "Note: In our VM setup, the qcow2 file is already in place."
    info "We'll remove the faulty disk, zero it, and re-add it."
    echo ""

    ssh_exec_show "sudo mdadm /dev/md0 --remove $disk 2>/dev/null || true" \
        "Removing $disk from /dev/md0 (if still present as faulty)"

    ssh_exec_show "sudo dd if=/dev/zero of=$disk bs=1M count=10 2>/dev/null; sync" \
        "Wiping the first 10MB of $disk (simulating new blank drive)"

    ssh_exec_show "sudo mdadm /dev/md0 --add $disk" \
        "Adding $disk back to /dev/md0 — rebuild starts automatically"

    ssh_exec_show "cat /proc/mdstat" \
        "Watch the rebuild progress (look for [>..] recovery indicator)"

    echo -e "${CYAN}  The array is now rebuilding. For small disks this is nearly instant.${RESET}"
    echo -e "${CYAN}  In production with large disks, rebuilds can take hours.${RESET}"

    # Wait a moment and show final status
    sleep 2
    ssh_exec_show "cat /proc/mdstat" \
        "Final status — rebuild should be complete for our small disks"

    ssh_exec_show "sudo mdadm --detail /dev/md0" \
        "Detailed view — all disks should show 'active sync'"

    success "Disk replaced and array rebuilt!"
    pause
}

# ── Destroy RAID Arrays ──
raid_lab_destroy() {
    _raid_ensure_vm || return 1

    section "Destroy All RAID Arrays"

    if ! confirm "This will stop all RAID arrays and wipe RAID metadata. Continue?"; then
        info "Cancelled."
        return 0
    fi

    # Unmount everything under /mnt/raid*
    ssh_exec_show "sudo umount /mnt/raid* 2>/dev/null; echo 'Unmounted.'" \
        "Step 1: Unmount any RAID filesystems"

    # Stop all md arrays
    local md_devs
    md_devs=$(ssh_exec "ls /dev/md* 2>/dev/null | grep -v /dev/md/" | tr '\n' ' ')
    for md in $md_devs; do
        [[ -z "$md" ]] && continue
        ssh_exec_show "sudo mdadm --stop $md 2>/dev/null || true" \
            "Stopping $md"
    done

    # Zero superblocks on all data disks
    ssh_exec_show "sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null; echo 'Superblocks cleared.'" \
        "Step 2: Clear RAID superblocks from all data disks"

    ssh_exec_show "cat /proc/mdstat" \
        "Verify — no more RAID arrays"

    success "All RAID arrays destroyed and disks cleaned."
    pause
}

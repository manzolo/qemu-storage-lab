#!/usr/bin/env bash
# lvm-labs.sh — LVM labs (PV, VG, LV, resize, on RAID)

# Guard against double-sourcing
[[ -n "${_LVM_LABS_LOADED:-}" ]] && return 0
_LVM_LABS_LOADED=1

# ── Source dependencies ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ssh-utils.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vm-manager.sh"

# ── Helper: ensure VM + SSH are ready ──
_lvm_ensure_vm() {
    if ! vm_is_running; then
        error "VM is not running. Start it from the VM Management menu."
        pause
        return 1
    fi
    if ! ssh_check; then
        error "VM is running but SSH is not reachable."
        pause
        return 1
    fi
}

# ── Basic LVM Lab ──
lvm_lab_basic() {
    _lvm_ensure_vm || return 0

    section "Lab: Basic LVM — PV → VG → LV"

    cat << 'EOF'
  We'll create the full LVM stack from scratch:
  1. Physical Volumes (PV) — mark raw disks for LVM use
  2. Volume Group (VG)     — pool PVs together
  3. Logical Volume (LV)   — carve out a virtual partition
  4. Filesystem + mount    — make it usable

  Using /dev/vdb and /dev/vdc as our raw disks.
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: Available disks"

    ssh_exec_show "sudo pvcreate /dev/vdb /dev/vdc" \
        "Step 2: Create Physical Volumes (PV) on vdb and vdc"

    ssh_exec_show "sudo pvs" \
        "Verify PVs — pvs shows all Physical Volumes"

    ssh_exec_show "sudo vgcreate lab_vg /dev/vdb /dev/vdc" \
        "Step 3: Create Volume Group 'lab_vg' combining both PVs"

    ssh_exec_show "sudo vgs" \
        "Verify VG — notice the combined size of both disks"

    ssh_exec_show "sudo lvcreate -L 2G -n data_lv lab_vg" \
        "Step 4: Create a 2GB Logical Volume named 'data_lv'"

    ssh_exec_show "sudo lvs" \
        "Verify LV — our 2GB logical volume in lab_vg"

    ssh_exec_show "sudo mkfs.ext4 /dev/lab_vg/data_lv" \
        "Step 5: Create ext4 filesystem on the LV"

    ssh_exec_show "sudo mkdir -p /mnt/lvm-data && sudo mount /dev/lab_vg/data_lv /mnt/lvm-data" \
        "Step 6: Mount the LV"

    ssh_exec_show "echo 'Hello from LVM!' | sudo tee /mnt/lvm-data/test.txt && df -h /mnt/lvm-data" \
        "Step 7: Write test data and check space"

    ssh_exec_show "sudo pvs && echo '---' && sudo vgs && echo '---' && sudo lvs" \
        "Full LVM overview — PV, VG, and LV status"

    success "Basic LVM setup complete! LV mounted at /mnt/lvm-data"
    echo -e "${CYAN}  Key insight: The filesystem doesn't know it spans 2 physical disks.${RESET}"
    echo -e "${CYAN}  LVM abstracts the physical layout from the filesystem.${RESET}"
    pause
}

# ── LVM Resize Lab ──
lvm_lab_resize() {
    _lvm_ensure_vm || return 0

    section "Lab: Resize a Logical Volume (Live!)"

    cat << 'EOF'
  One of LVM's best features: resize volumes without downtime.
  We'll grow our existing LV and extend the filesystem.

  With ext4, you can grow the filesystem while it's mounted!
EOF
    echo ""

    ssh_exec_show "df -h /mnt/lvm-data 2>/dev/null && sudo lvs lab_vg/data_lv 2>/dev/null" \
        "Step 1: Current size of the LV and filesystem"

    ssh_exec_show "sudo vgs lab_vg" \
        "Step 2: Check free space in the Volume Group"

    ssh_exec_show "sudo lvextend -L +1G /dev/lab_vg/data_lv" \
        "Step 3: Extend the LV by 1GB (from 2GB to 3GB)"

    ssh_exec_show "sudo lvs lab_vg/data_lv" \
        "LV is now 3GB, but the filesystem still thinks it's 2GB..."

    ssh_exec_show "df -h /mnt/lvm-data" \
        "See? Filesystem still shows ~2GB"

    ssh_exec_show "sudo resize2fs /dev/lab_vg/data_lv" \
        "Step 4: Resize the filesystem to fill the LV (works online for ext4!)"

    ssh_exec_show "df -h /mnt/lvm-data" \
        "Now the filesystem sees all 3GB — done while mounted!"

    success "LV resized from 2GB to 3GB — live, no downtime!"
    echo ""
    echo -e "${CYAN}  In production, this is invaluable:${RESET}"
    echo -e "${CYAN}    - Database growing? Extend the LV live.${RESET}"
    echo -e "${CYAN}    - Need more space? Add a PV to the VG, then extend.${RESET}"
    pause
}

# ── LVM on RAID Lab ──
lvm_lab_on_raid() {
    _lvm_ensure_vm || return 0

    section "Lab: LVM on top of RAID"

    cat << 'EOF'
  Best practice architecture: RAID underneath for redundancy,
  LVM on top for flexibility.

  We'll:
  1. Create a RAID 1 array from /dev/vdb + /dev/vdc
  2. Use the RAID array as a PV for LVM
  3. Create VG and LV on the RAID
  4. Mount and test

  This gives us BOTH disk failure protection AND flexible volume management.
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: Available disks"

    ssh_exec_show "sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run" \
        "Step 2: Create RAID 1 array"

    ssh_exec_show "cat /proc/mdstat" \
        "RAID array is ready"

    ssh_exec_show "sudo pvcreate /dev/md0" \
        "Step 3: Create PV on the RAID array (not on raw disks)"

    ssh_exec_show "sudo vgcreate raid_vg /dev/md0" \
        "Step 4: Create VG on the RAID-backed PV"

    ssh_exec_show "sudo lvcreate -L 2G -n secure_lv raid_vg" \
        "Step 5: Create a 2GB LV"

    ssh_exec_show "sudo mkfs.ext4 /dev/raid_vg/secure_lv" \
        "Step 6: Create filesystem"

    ssh_exec_show "sudo mkdir -p /mnt/raid-lvm && sudo mount /dev/raid_vg/secure_lv /mnt/raid-lvm" \
        "Step 7: Mount"

    ssh_exec_show "echo 'Protected by RAID + managed by LVM' | sudo tee /mnt/raid-lvm/test.txt" \
        "Step 8: Write test data"

    ssh_exec_show "df -h /mnt/raid-lvm && echo '---' && sudo pvs && echo '---' && sudo vgs && echo '---' && sudo lvs" \
        "Final overview: filesystem, PV, VG, LV — all on top of RAID"

    success "LVM on RAID setup complete!"
    echo ""
    echo -e "${CYAN}  Architecture:  /dev/vdb + /dev/vdc → md0 (RAID 1) → raid_vg → secure_lv → ext4${RESET}"
    echo -e "${CYAN}  This is how production servers are typically configured.${RESET}"
    pause
}

# ── LVM Cleanup ──
lvm_lab_cleanup() {
    _lvm_ensure_vm || return 0

    section "Clean Up All LVM Configuration"

    if ! confirm "This will unmount, remove all LVs, VGs, and PVs. Continue?"; then
        info "Cancelled."
        return 0
    fi

    # Unmount
    ssh_exec_show "sudo umount /mnt/lvm-data 2>/dev/null; sudo umount /mnt/raid-lvm 2>/dev/null; echo 'Unmounted.'" \
        "Step 1: Unmount LVM filesystems"

    # Discover and remove LVs
    local lvs_output
    lvs_output=$(ssh_exec "sudo lvs --noheadings -o lv_name,vg_name 2>/dev/null" || true)
    if [[ -n "$lvs_output" ]]; then
        while IFS= read -r line; do
            local lv_name vg_name
            lv_name=$(echo "$line" | awk '{print $1}')
            vg_name=$(echo "$line" | awk '{print $2}')
            [[ -z "$lv_name" || -z "$vg_name" ]] && continue
            ssh_exec_show "sudo lvremove -f /dev/${vg_name}/${lv_name}" \
                "Removing LV: ${lv_name} from VG: ${vg_name}"
        done <<< "$lvs_output"
    fi

    # Remove VGs
    local vgs_output
    vgs_output=$(ssh_exec "sudo vgs --noheadings -o vg_name 2>/dev/null" || true)
    if [[ -n "$vgs_output" ]]; then
        while IFS= read -r line; do
            local vg_name
            vg_name=$(echo "$line" | awk '{print $1}')
            [[ -z "$vg_name" ]] && continue
            ssh_exec_show "sudo vgremove -f ${vg_name}" \
                "Removing VG: ${vg_name}"
        done <<< "$vgs_output"
    fi

    # Remove PVs
    ssh_exec_show "sudo pvremove /dev/md0 /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null; echo 'PVs removed.'" \
        "Step 2: Remove all Physical Volumes"

    # Stop RAID if active (from LVM-on-RAID lab)
    ssh_exec_show "sudo mdadm --stop /dev/md0 2>/dev/null; echo 'RAID stopped (if any).'" \
        "Step 3: Stop RAID arrays (if created during LVM-on-RAID lab)"

    ssh_exec_show "sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null; echo 'Done.'" \
        "Step 4: Clear RAID superblocks"

    ssh_exec_show "sudo pvs 2>/dev/null; sudo vgs 2>/dev/null; sudo lvs 2>/dev/null; echo 'All clear.'" \
        "Verify: no LVM objects remain"

    success "All LVM (and underlying RAID) cleaned up."
    pause
}

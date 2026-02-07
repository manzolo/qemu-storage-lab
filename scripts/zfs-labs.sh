#!/usr/bin/env bash
# zfs-labs.sh — ZFS labs (pool, mirror, raidz, datasets, snapshots, replace)

# Guard against double-sourcing
[[ -n "${_ZFS_LABS_LOADED:-}" ]] && return 0
_ZFS_LABS_LOADED=1

# ── Source dependencies ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ssh-utils.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vm-manager.sh"

# ── Helper: ensure VM + SSH are ready ──
_zfs_ensure_vm() {
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

# ── ZFS Mirror Lab ──
zfs_lab_mirror() {
    _zfs_ensure_vm || return 0

    section "Lab: Create ZFS Mirror Pool with /dev/vdb + /dev/vdc"

    cat << 'EOF'
  A ZFS mirror is equivalent to RAID 1: data is copied identically
  to both disks. ZFS adds checksumming and self-healing on top.

  What we'll do:
  1. Create a mirror pool "tank" with /dev/vdb and /dev/vdc
  2. Write data and verify
  3. Check pool status
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: Available disks in the VM"

    ssh_exec_show "sudo zpool create tank mirror /dev/vdb /dev/vdc" \
        "Step 2: Create mirror pool 'tank' with vdb and vdc"

    ssh_exec_show "sudo zpool status tank" \
        "Step 3: Pool status — both disks should show ONLINE"

    ssh_exec_show "sudo zpool list tank" \
        "Step 4: Pool capacity — usable space is one disk (mirrored)"

    ssh_exec_show "echo 'Hello from ZFS mirror!' | sudo tee /tank/test.txt && ls -la /tank/" \
        "Step 5: Write a test file — ZFS auto-mounts at /tank"

    ssh_exec_show "cat /tank/test.txt" \
        "Step 6: Read back the test file"

    ssh_exec_show "sudo zpool status -v tank" \
        "Step 7: Verbose status — notice the checksum columns (0 errors = healthy)"

    success "ZFS mirror pool 'tank' created and mounted at /tank!"
    echo -e "${CYAN}  Data is mirrored across /dev/vdb and /dev/vdc.${RESET}"
    echo -e "${CYAN}  ZFS checksums every block — silent corruption is detected automatically.${RESET}"
    pause
}

# ── ZFS RAIDZ Lab ──
zfs_lab_raidz() {
    _zfs_ensure_vm || return 0

    section "Lab: Create ZFS RAIDZ Pool with /dev/vdb + /dev/vdc + /dev/vdd"

    cat << 'EOF'
  RAIDZ is ZFS's equivalent of RAID 5: data is striped with one
  parity block distributed across all disks. Survives 1 disk failure.

  What we'll do:
  1. Create a raidz pool "datapool" with 3 disks
  2. Write data and verify
  3. Check capacity (N-1 disks usable)
EOF
    echo ""

    ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Step 1: Available disks"

    ssh_exec_show "sudo zpool create datapool raidz /dev/vdb /dev/vdc /dev/vdd" \
        "Step 2: Create RAIDZ pool 'datapool' with 3 disks"

    ssh_exec_show "sudo zpool status datapool" \
        "Step 3: Pool status — all 3 disks should be ONLINE"

    ssh_exec_show "sudo zpool list datapool" \
        "Step 4: Pool capacity — usable space is (N-1) disks"

    ssh_exec_show "echo 'Hello from ZFS RAIDZ!' | sudo tee /datapool/test.txt && ls -la /datapool/" \
        "Step 5: Write a test file"

    ssh_exec_show "cat /datapool/test.txt" \
        "Step 6: Verify data"

    ssh_exec_show "sudo zpool status -v datapool" \
        "Step 7: Verbose status with checksum verification"

    success "ZFS RAIDZ pool 'datapool' created and mounted at /datapool!"
    echo -e "${CYAN}  Data is striped with parity across vdb, vdc, vdd.${RESET}"
    echo -e "${CYAN}  The pool can survive the failure of any ONE disk.${RESET}"
    pause
}

# ── ZFS Datasets Lab ──
zfs_lab_datasets() {
    _zfs_ensure_vm || return 0

    section "Lab: ZFS Datasets — Lightweight Filesystems"

    cat << 'EOF'
  ZFS datasets are like directories with superpowers: each has its own
  properties (quota, compression, mountpoint), snapshots, and is
  created instantly with no pre-allocation.

  What we'll do:
  1. Create a mirror pool (if not exists)
  2. Create datasets: tank/data and tank/logs
  3. Set properties (quota, compression)
  4. Verify the hierarchy
EOF
    echo ""

    # Create pool if needed
    local pool_exists
    pool_exists=$(ssh_exec "sudo zpool list -H -o name 2>/dev/null | grep -c '^tank$' || true" 2>/dev/null)
    if [[ "$pool_exists" == "0" ]]; then
        ssh_exec_show "sudo zpool create tank mirror /dev/vdb /dev/vdc" \
            "Step 1: Create mirror pool 'tank' (needed for datasets)"
    else
        info "Pool 'tank' already exists — reusing it."
    fi

    ssh_exec_show "sudo zfs create tank/data" \
        "Step 2: Create dataset tank/data — auto-mounted at /tank/data"

    ssh_exec_show "sudo zfs create tank/logs" \
        "Step 3: Create dataset tank/logs — auto-mounted at /tank/logs"

    ssh_exec_show "sudo zfs list -r tank" \
        "Step 4: List all datasets — notice the hierarchy"

    ssh_exec_show "sudo zfs set quota=2G tank/data" \
        "Step 5: Set a 2GB quota on tank/data"

    ssh_exec_show "sudo zfs set compression=lz4 tank/logs" \
        "Step 6: Enable LZ4 compression on tank/logs"

    ssh_exec_show "sudo zfs get quota,compression,mountpoint tank/data tank/logs" \
        "Step 7: Verify properties on both datasets"

    ssh_exec_show "echo 'app data' | sudo tee /tank/data/app.txt && echo 'log entry' | sudo tee /tank/logs/app.log && ls -la /tank/data/ /tank/logs/" \
        "Step 8: Write files to each dataset"

    success "ZFS datasets created with independent properties!"
    echo -e "${CYAN}  tank/data has a 2GB quota. tank/logs has LZ4 compression.${RESET}"
    echo -e "${CYAN}  Each dataset can be snapshotted and managed independently.${RESET}"
    pause
}

# ── ZFS Snapshots Lab ──
zfs_lab_snapshots() {
    _zfs_ensure_vm || return 0

    section "Lab: ZFS Snapshots & Rollback"

    cat << 'EOF'
  ZFS snapshots capture the exact state of a dataset at a point in time.
  They are instant (Copy-On-Write) and consume no extra space initially.
  Rollback restores the dataset to the snapshot state.

  What we'll do:
  1. Create a pool and write data
  2. Take a snapshot
  3. Modify the data
  4. Rollback to the snapshot
  5. Verify the original data is restored
EOF
    echo ""

    # Create pool if needed
    local pool_exists
    pool_exists=$(ssh_exec "sudo zpool list -H -o name 2>/dev/null | grep -c '^tank$' || true" 2>/dev/null)
    if [[ "$pool_exists" == "0" ]]; then
        ssh_exec_show "sudo zpool create tank mirror /dev/vdb /dev/vdc" \
            "Step 1: Create mirror pool 'tank'"
    else
        info "Pool 'tank' already exists — reusing it."
    fi

    # Create dataset if needed
    local ds_exists
    ds_exists=$(ssh_exec "sudo zfs list -H -o name 2>/dev/null | grep -c '^tank/data$' || true" 2>/dev/null)
    if [[ "$ds_exists" == "0" ]]; then
        ssh_exec_show "sudo zfs create tank/data" \
            "Step 2: Create dataset tank/data"
    else
        info "Dataset 'tank/data' already exists — reusing it."
    fi

    ssh_exec_show "echo 'original important data version 1' | sudo tee /tank/data/important.txt" \
        "Step 3: Write original data"

    ssh_exec_show "cat /tank/data/important.txt" \
        "Step 4: Verify the original data"

    ssh_exec_show "sudo zfs snapshot tank/data@before-change" \
        "Step 5: Take snapshot 'tank/data@before-change' — instant!"

    ssh_exec_show "sudo zfs list -t snapshot" \
        "Step 6: List snapshots — notice zero space used (COW)"

    ssh_exec_show "echo 'MODIFIED data — oops wrong change!' | sudo tee /tank/data/important.txt" \
        "Step 7: Modify the file (simulate a bad change)"

    ssh_exec_show "cat /tank/data/important.txt" \
        "Step 8: Confirm the file was changed"

    ssh_exec_show "sudo zfs rollback tank/data@before-change" \
        "Step 9: Rollback to snapshot — instant undo!"

    ssh_exec_show "cat /tank/data/important.txt" \
        "Step 10: Verify — original data is restored!"

    ssh_exec_show "sudo zfs list -t snapshot" \
        "Step 11: Snapshot still exists after rollback"

    success "ZFS snapshot and rollback completed!"
    echo -e "${CYAN}  Snapshots are instant thanks to Copy-On-Write.${RESET}"
    echo -e "${CYAN}  Rollback restores the exact state — perfect for 'undo' before upgrades.${RESET}"
    pause
}

# ── ZFS Disk Replace Lab ──
zfs_lab_replace() {
    _zfs_ensure_vm || return 0

    section "Lab: ZFS Disk Replacement & Resilver"

    cat << 'EOF'
  When a disk fails in a ZFS mirror, the pool becomes DEGRADED but
  remains fully functional. You can replace the disk and ZFS will
  "resilver" (rebuild) the data automatically.

  What we'll do:
  1. Create a mirror pool and write data
  2. Offline a disk (simulate failure)
  3. Verify the pool is DEGRADED but data is OK
  4. Replace the disk and wait for resilver
  5. Verify everything is healthy again
EOF
    echo ""

    ssh_exec_show "sudo zpool create tank mirror /dev/vdb /dev/vdc" \
        "Step 1: Create mirror pool 'tank' with vdb + vdc"

    ssh_exec_show "echo 'critical data must survive' | sudo tee /tank/critical.txt" \
        "Step 2: Write critical data"

    ssh_exec_show "sudo zpool status tank" \
        "Step 3: Healthy pool status before failure"

    echo ""
    echo -e "  ${RED}${BOLD}  ▼▼▼  DISK FAILURE SIMULATION  ▼▼▼${RESET}"
    echo ""

    ssh_exec_show "sudo zpool offline tank /dev/vdc" \
        "Step 4: Offline /dev/vdc — simulating disk failure"

    ssh_exec_show "sudo zpool status tank" \
        "Step 5: Pool is now DEGRADED — notice vdc is OFFLINE"

    ssh_exec_show "cat /tank/critical.txt" \
        "Step 6: Data is still accessible from the healthy disk!"

    echo ""
    echo -e "  ${GREEN}${BOLD}  ▲▲▲  DISK REPLACEMENT  ▲▲▲${RESET}"
    echo ""

    ssh_exec_show "sudo zpool online tank /dev/vdc" \
        "Step 7: Bring disk back online (simulating replacement)"

    # Wait for resilver
    echo -e "  ${DIM}Waiting for resilver to complete...${RESET}"
    local retries=0
    while (( retries < 30 )); do
        local status
        status=$(ssh_exec "sudo zpool status tank" 2>/dev/null) || true
        if echo "$status" | grep -q "state: ONLINE"; then
            echo -e "  ${GREEN}✓ Resilver complete — pool is ONLINE${RESET}"
            break
        fi
        sleep 1
        retries=$(( retries + 1 ))
    done

    ssh_exec_show "sudo zpool status tank" \
        "Step 8: Final pool status — all disks ONLINE"

    ssh_exec_show "cat /tank/critical.txt" \
        "Step 9: Verify data integrity — data survived the failure!"

    success "ZFS disk replacement and resilver completed!"
    echo -e "${CYAN}  ZFS checksums ensure the resilvered data is bit-perfect.${RESET}"
    echo -e "${CYAN}  Unlike mdadm, ZFS only resilvers used blocks — much faster.${RESET}"
    pause
}

# ── ZFS Status ──
zfs_lab_status() {
    _zfs_ensure_vm || return 0

    section "ZFS Status"

    ssh_exec_show "sudo zpool list 2>/dev/null || echo 'No ZFS pools found.'" \
        "ZFS pool list — overview of all pools"

    ssh_exec_show "sudo zpool status 2>/dev/null || echo 'No ZFS pools found.'" \
        "ZFS pool status — detailed health of all pools"

    ssh_exec_show "sudo zfs list 2>/dev/null || echo 'No ZFS datasets found.'" \
        "ZFS dataset list — all datasets and their properties"

    ssh_exec_show "sudo zfs list -t snapshot 2>/dev/null || echo 'No snapshots found.'" \
        "ZFS snapshots — all point-in-time captures"

    pause
}

# ── ZFS Destroy ──
zfs_lab_destroy() {
    _zfs_ensure_vm || return 0

    section "Destroy All ZFS Pools"

    if ! confirm "This will destroy all ZFS pools and wipe disk labels. Continue?"; then
        info "Cancelled."
        return 0
    fi

    # List and destroy all pools
    local pools
    pools=$(ssh_exec "sudo zpool list -H -o name 2>/dev/null || true" 2>/dev/null || true)
    if [[ -n "$pools" ]]; then
        while IFS= read -r pool; do
            [[ -z "$pool" ]] && continue
            ssh_exec_show "sudo zpool destroy -f ${pool}" \
                "Destroying pool '${pool}'"
        done <<< "$pools"
    else
        info "No ZFS pools found."
    fi

    ssh_exec_show "sudo wipefs -a /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null; echo 'Disk labels cleared.'" \
        "Clearing disk labels from all data disks"

    ssh_exec_show "sudo zpool list 2>/dev/null || echo 'No ZFS pools — all clean.'" \
        "Verify — no more ZFS pools"

    success "All ZFS pools destroyed and disks cleaned."
    pause
}

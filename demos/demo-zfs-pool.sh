#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-zfs-pool.sh — ZFS Pool: datasets, snapshots, rollback
#  Interactive guided tutorial
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/demo-common.sh"

demo_zfs_pool() {
    demo_ensure_vm || return 0

    demo_header "ZFS Pool — Datasets & Snapshots" \
        "Create a pool, datasets, snapshots, modify data, rollback, verify"

    # Clean environment
    demo_cleanup_start

    # Step 1: Inspect disks
    _next_step
    tutor_step "$STEP_COUNT" "Inspect available disks" \
        "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "Let's see which disks are available in the VM.
We'll use vdb and vdc for a ZFS mirror pool." || return 0

    # Step 2: Create mirror pool
    _next_step
    demo_note "ZFS combines RAID, volume management, and the filesystem in one tool.
A mirror pool is the ZFS equivalent of RAID 1 — identical copies on both disks."
    tutor_step "$STEP_COUNT" "Create ZFS mirror pool" \
        "sudo zpool create tank mirror /dev/vdb /dev/vdc" \
        "We create a mirror pool called 'tank' with two disks.
ZFS automatically creates and mounts a filesystem at /tank." || return 0

    # Step 3: Verify pool
    _next_step
    tutor_step "$STEP_COUNT" "Verify pool status" \
        "sudo zpool status tank" \
        "zpool status shows the health of the pool and all its disks.
Both disks should show ONLINE." \
        "ONLINE" || return 0

    # Step 4: Pool capacity
    _next_step
    tutor_step "$STEP_COUNT" "Check pool capacity" \
        "sudo zpool list tank" \
        "zpool list shows size, used space, and free space.
Like RAID 1, usable capacity equals one disk (mirrored)." || return 0

    # Step 5: Create datasets
    _next_step
    demo_note "Datasets are lightweight filesystems inside a pool.
Each has its own properties, quotas, and snapshots — created instantly."
    tutor_step "$STEP_COUNT" "Create dataset tank/data" \
        "sudo zfs create tank/data" \
        "We create a dataset 'tank/data' — auto-mounted at /tank/data.
No need for mkfs or mount — ZFS handles everything." || return 0

    # Step 6: Create second dataset
    _next_step
    tutor_step "$STEP_COUNT" "Create dataset tank/logs" \
        "sudo zfs create tank/logs" \
        "A second dataset for logs. Each dataset is independent:
different quotas, compression, snapshots." || return 0

    # Step 7: List datasets
    _next_step
    tutor_step "$STEP_COUNT" "List all datasets" \
        "sudo zfs list -r tank" \
        "zfs list shows all datasets in the pool hierarchy.
Notice how they share the pool's space dynamically." || return 0

    # Step 8: Set properties
    _next_step
    tutor_step "$STEP_COUNT" "Set quota and compression" \
        "sudo zfs set quota=2G tank/data && sudo zfs set compression=lz4 tank/logs" \
        "We set a 2GB quota on tank/data and enable LZ4 compression on tank/logs.
Properties are per-dataset — no need to resize partitions." || return 0

    # Step 9: Verify properties
    _next_step
    tutor_step "$STEP_COUNT" "Verify dataset properties" \
        "sudo zfs get quota,compression,mountpoint tank/data tank/logs" \
        "zfs get shows current properties for each dataset.
Notice each has independent settings." || return 0

    # Step 10: Write data
    _next_step
    tutor_step "$STEP_COUNT" "Write data to datasets" \
        "echo 'original important data v1' | sudo tee /tank/data/important.txt && echo 'log entry 1' | sudo tee /tank/logs/app.log" \
        "We write files to each dataset. This data is mirrored
across both disks by the pool." || return 0

    # Step 11: Create snapshot
    _next_step
    demo_note "ZFS snapshots use Copy-On-Write (COW): they are instant and
initially consume zero extra space. Only changed blocks use space."
    tutor_step "$STEP_COUNT" "Take a snapshot" \
        "sudo zfs snapshot tank/data@before-change" \
        "We capture the current state of tank/data as a snapshot.
The @before-change suffix is the snapshot name." || return 0

    # Step 12: List snapshots
    _next_step
    tutor_step "$STEP_COUNT" "List snapshots" \
        "sudo zfs list -t snapshot" \
        "Notice the USED column is 0 — the snapshot is free until
data changes (Copy-On-Write preserves changed blocks)." || return 0

    # Step 13: Modify data
    _next_step
    tutor_step "$STEP_COUNT" "Modify the file (simulate bad change)" \
        "echo 'MODIFIED data — oops wrong change!' | sudo tee /tank/data/important.txt" \
        "We overwrite the file with bad data.
In real life, this could be a failed upgrade or accidental deletion." || return 0

    # Step 14: Verify change
    _next_step
    tutor_step "$STEP_COUNT" "Confirm the file was changed" \
        "cat /tank/data/important.txt" \
        "The file now contains the modified (wrong) data." \
        "MODIFIED" || return 0

    # Step 15: Rollback
    _next_step
    demo_note "Rollback is instant — ZFS simply switches back to the snapshot's
block pointers. No copying, no waiting."
    tutor_step "$STEP_COUNT" "Rollback to snapshot" \
        "sudo zfs rollback tank/data@before-change" \
        "We roll back tank/data to the @before-change snapshot.
This undoes ALL changes made after the snapshot." || return 0

    # Step 16: Verify rollback
    _next_step
    tutor_step "$STEP_COUNT" "Verify original data is restored" \
        "cat /tank/data/important.txt" \
        "The file should contain the original data again.
Rollback successfully undid the bad change!" \
        "original important data v1" || return 0

    # Step 17: Logs dataset untouched
    _next_step
    tutor_step "$STEP_COUNT" "Verify logs dataset is untouched" \
        "cat /tank/logs/app.log" \
        "The logs dataset was not affected by the rollback.
Each dataset is independent — snapshots are per-dataset." \
        "log entry 1" || return 0

    # Step 18: Final overview
    _next_step
    tutor_step "$STEP_COUNT" "Final overview" \
        "sudo zpool status tank && echo '---' && sudo zfs list -r tank && echo '---' && sudo zfs list -t snapshot" \
        "A complete overview: pool health, datasets, and snapshots.
This is everything you need to manage ZFS storage." || return 0

    # Step 19: Cleanup
    _next_step
    tutor_step "$STEP_COUNT" "Cleanup — destroy the pool" \
        "sudo zpool destroy -f tank && sudo wipefs -a /dev/vdb /dev/vdc 2>/dev/null; echo 'Cleanup complete'" \
        "Destroy the pool and wipe disk labels.
All datasets, snapshots, and data are removed instantly." || return 0

    # Summary
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}  ║  ZFS Pool demo completed successfully!               ║${RESET}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}What we learned:${RESET}"
    echo -e "  - ZFS combines RAID + volume management + filesystem"
    echo -e "  - Datasets are lightweight, instant, and independent"
    echo -e "  - Snapshots are instant thanks to Copy-On-Write"
    echo -e "  - Rollback restores data to the exact snapshot state"
    echo -e "  - Just two commands: zpool (pools) and zfs (datasets)"
    echo ""
    pause
}

# Allow direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_zfs_pool
fi

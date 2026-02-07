#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-zfs-raid.sh — ZFS Mirror: failure simulation & resilver
#  Interactive guided tutorial
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/demo-common.sh"

demo_zfs_raid() {
    demo_ensure_vm || return 0

    demo_header "ZFS Mirror — Failure & Resilver" \
        "Create a mirror, write data, simulate failure, replace disk, verify"

    # Clean environment
    demo_cleanup_start

    # Step 1: Inspect disks
    _next_step
    tutor_step "$STEP_COUNT" "Inspect available disks" \
        "lsblk -o NAME,SIZE,SERIAL,TYPE" \
        "We'll use vdb and vdc for a ZFS mirror pool.
A mirror keeps identical copies on both disks." || return 0

    # Step 2: Create mirror pool
    _next_step
    demo_note "A ZFS mirror is similar to mdadm RAID 1, but with added benefits:
every block has a checksum, and ZFS can self-heal corrupted data."
    tutor_step "$STEP_COUNT" "Create ZFS mirror pool" \
        "sudo zpool create tank mirror /dev/vdb /dev/vdc" \
        "We create pool 'tank' as a mirror of vdb and vdc.
ZFS auto-creates and mounts a filesystem at /tank." || return 0

    # Step 3: Pool status
    _next_step
    tutor_step "$STEP_COUNT" "Verify pool health" \
        "sudo zpool status tank" \
        "Both disks should show ONLINE under the mirror vdev.
The pool state should be ONLINE (healthy)." \
        "ONLINE" || return 0

    # Step 4: Write critical data
    _next_step
    tutor_step "$STEP_COUNT" "Write critical data" \
        "echo 'critical data that must survive disk failure' | sudo tee /tank/critical.txt && sudo dd if=/dev/urandom of=/tank/testblock bs=1M count=10 2>&1" \
        "We write a text file and a 10MB binary file.
This data is mirrored on both disks automatically." || return 0

    # Step 5: Compute checksum
    _next_step
    tutor_step "$STEP_COUNT" "Compute data checksum" \
        "md5sum /tank/critical.txt /tank/testblock" \
        "We record checksums so we can verify data integrity
after the failure and resilver." || return 0

    # Step 6: Pool status before failure
    _next_step
    tutor_step "$STEP_COUNT" "Pool status before failure" \
        "sudo zpool status -v tank" \
        "Verbose status shows checksum error counts (should be all 0).
ZFS checksums every block on every read." || return 0

    # Step 7: Simulate failure
    _next_step
    echo ""
    echo -e "  ${RED}${BOLD}  ▼▼▼  DISK FAILURE SIMULATION  ▼▼▼${RESET}"
    echo ""
    demo_note "On a real server, a disk would physically die.
We simulate this by marking the disk as OFFLINE in ZFS."
    tutor_step "$STEP_COUNT" "Offline /dev/vdc (simulate failure)" \
        "sudo zpool offline tank /dev/vdc" \
        "We take /dev/vdc offline — simulating a disk failure.
The pool will become DEGRADED but continue working." || return 0

    # Step 8: Verify degraded
    _next_step
    tutor_step "$STEP_COUNT" "Verify DEGRADED state" \
        "sudo zpool status tank" \
        "The pool should show state: DEGRADED.
vdc should show OFFLINE. The mirror is running on vdb alone." \
        "DEGRADED" || return 0

    # Step 9: Data still accessible
    _next_step
    demo_note "Even with one disk offline, the mirror continues serving data.
This is the whole point of redundancy!"
    tutor_step "$STEP_COUNT" "Verify data is still accessible" \
        "cat /tank/critical.txt" \
        "The file is still readable from the healthy disk (vdb).
No data loss even though half the mirror is gone!" \
        "critical data" || return 0

    # Step 10: Verify checksum
    _next_step
    tutor_step "$STEP_COUNT" "Verify data integrity (checksums)" \
        "md5sum /tank/critical.txt /tank/testblock" \
        "Checksums should match what we recorded earlier.
ZFS guarantees data integrity even during degraded operation." || return 0

    # Step 11: Replace disk
    _next_step
    echo ""
    echo -e "  ${GREEN}${BOLD}  ▲▲▲  DISK REPLACEMENT  ▲▲▲${RESET}"
    echo ""
    demo_note "On a real server, you would physically replace the failed disk.
Here we bring it back online to simulate a replacement."
    tutor_step "$STEP_COUNT" "Bring disk back online (replacement)" \
        "sudo zpool online tank /dev/vdc" \
        "We bring vdc back online — simulating a disk replacement.
ZFS will automatically start resilvering (rebuilding)." || return 0

    # Step 12: Watch resilver
    _next_step
    tutor_step "$STEP_COUNT" "Check resilver progress" \
        "sudo zpool status tank" \
        "If resilver is still running, you'll see a progress bar.
Unlike mdadm, ZFS only resilvers used blocks — much faster." || return 0

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

    # Step 13: Verify healthy
    _next_step
    tutor_step "$STEP_COUNT" "Verify pool is healthy again" \
        "sudo zpool status tank" \
        "The pool should be back to state: ONLINE.
Both disks should show ONLINE — full redundancy restored." \
        "ONLINE" || return 0

    # Step 14: Verify data intact
    _next_step
    tutor_step "$STEP_COUNT" "Verify data survived the failure" \
        "cat /tank/critical.txt" \
        "The file must be identical to what we wrote before the failure.
ZFS checksums guarantee no silent corruption during resilver." \
        "critical data" || return 0

    # Step 15: Final checksum
    _next_step
    tutor_step "$STEP_COUNT" "Final checksum verification" \
        "md5sum /tank/critical.txt /tank/testblock" \
        "Checksums should match the originals exactly.
Data survived failure + resilver with full integrity." || return 0

    # Step 16: Scrub
    _next_step
    demo_note "A scrub reads every block in the pool and verifies checksums.
In production, run scrubs weekly to detect silent corruption early."
    tutor_step "$STEP_COUNT" "Run a scrub" \
        "sudo zpool scrub tank && sleep 3 && sudo zpool status tank" \
        "zpool scrub checks every block against its checksum.
If corruption is found in a mirror, ZFS auto-repairs it." || return 0

    # Step 17: Cleanup
    _next_step
    tutor_step "$STEP_COUNT" "Cleanup — destroy the pool" \
        "sudo zpool destroy -f tank && sudo wipefs -a /dev/vdb /dev/vdc 2>/dev/null; echo 'Cleanup complete'" \
        "Destroy the pool and clear disk labels.
All data is removed." || return 0

    # Summary
    echo ""
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}  ║  ZFS Mirror demo completed successfully!             ║${RESET}"
    echo -e "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}What we learned:${RESET}"
    echo -e "  - ZFS mirror provides redundancy like RAID 1"
    echo -e "  - Added benefit: checksums on every block"
    echo -e "  - Self-healing: ZFS can repair corrupted data from the mirror"
    echo -e "  - Resilver only copies used blocks (faster than mdadm rebuild)"
    echo -e "  - Scrub detects silent corruption before it causes problems"
    echo ""
    pause
}

# Allow direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_zfs_raid
fi

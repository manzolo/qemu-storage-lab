#!/usr/bin/env bash
# theory.sh — Educational content: RAID theory, LVM theory, diagrams

# Guard against double-sourcing
[[ -n "${_THEORY_LOADED:-}" ]] && return 0
_THEORY_LOADED=1

# ── Source config ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"

# ── RAID Theory ──
theory_raid() {
    section "RAID Theory — Redundant Array of Independent Disks"

    cat << 'EOF'
  RAID combines multiple physical disks into a single logical unit
  for performance, redundancy, or both.

  ┌─────────────────────────────────────────────────────────────┐
  │  RAID 0 — Striping (no redundancy)                          │
  ├─────────────────────────────────────────────────────────────┤
  │                                                             │
  │    Disk 1        Disk 2                                     │
  │  ┌────────┐    ┌────────┐                                   │
  │  │ Block 1│    │ Block 2│    Data is split across disks     │
  │  │ Block 3│    │ Block 4│    ✓ 2x read/write speed          │
  │  │ Block 5│    │ Block 6│    ✗ ANY disk failure = ALL lost  │
  │  └────────┘    └────────┘    Capacity: N × disk_size        │
  │                                                             │
  │  Use: Temporary data, caches, scratch space                 │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  RAID 1 — Mirroring                                         │
  ├─────────────────────────────────────────────────────────────┤
  │                                                             │
  │     Disk 1        Disk 2                                    │
  │  ┌─────────┐    ┌─────────┐                                 │
  │  │ Block 1 │    │ Block 1 │    Identical copies on each disk│
  │  │ Block 2 │    │ Block 2 │    ✓ Survives 1 disk failure    │
  │  │ Block 3 │    │ Block 3 │    ✗ 50% capacity overhead      │
  │  └─────────┘    └─────────┘    Capacity: 1 × disk_size      │
  │                                                             │
  │  Use: OS drives, critical data, database logs               │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  RAID 5 — Striping with Distributed Parity                  │
  ├─────────────────────────────────────────────────────────────┤
  │                                                             │
  │    Disk 1        Disk 2        Disk 3                       │
  │  ┌────────┐    ┌────────┐    ┌────────┐                     │
  │  │ Data A │    │ Data B │    │ Parity │  Parity rotates     │
  │  │ Data D │    │ Parity │    │ Data E │  across all disks   │
  │  │ Parity │    │ Data G │    │ Data H │                     │
  │  └────────┘    └────────┘    └────────┘                     │
  │                                                             │
  │  ✓ Survives 1 disk failure    Min: 3 disks                  │
  │  ✓ Good balance of speed/redundancy                         │
  │  Capacity: (N-1) × disk_size                                │
  │  Use: General-purpose file/app servers                      │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  RAID 10 — Mirrored Stripes (RAID 1+0)                      │
  ├─────────────────────────────────────────────────────────────┤
  │                                                             │
  │   Mirror 1           Mirror 2                               │
  │  ┌──────┬──────┐   ┌──────┬──────┐                          │
  │  │Disk 1│Disk 2│   │Disk 3│Disk 4│   First mirror, then     │
  │  │ A  A │ A  A │   │ B  B │ B  B │   stripe across          │
  │  │ C  C │ C  C │   │ D  D │ D  D │   mirror pairs           │
  │  └──────┴──────┘   └──────┴──────┘                          │
  │                                                             │
  │  ✓ Survives 1 failure per mirror pair    Min: 4 disks       │
  │  ✓ Best performance of redundant levels                     │
  │  ✗ 50% capacity overhead                                    │
  │  Capacity: (N/2) × disk_size                                │
  │  Use: Databases, high-performance workloads                 │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  Comparison Table                                           │
  ├──────────┬─────────┬────────────┬──────────┬────────────────┤
  │  Level   │Min Disks│ Redundancy │ Capacity │ Performance    │
  ├──────────┼─────────┼────────────┼──────────┼────────────────┤
  │  RAID 0  │    2    │    None    │   N×D    │ Excellent      │
  │  RAID 1  │    2    │   1 disk   │   1×D    │ Good read      │
  │  RAID 5  │    3    │   1 disk   │ (N-1)×D  │ Good           │
  │  RAID 10 │    4    │ 1 per pair │ (N/2)×D  │ Excellent      │
  └──────────┴─────────┴────────────┴──────────┴────────────────┘
  D = size of one disk, N = number of disks
EOF

    pause
}

# ── LVM Theory ──
theory_lvm() {
    section "LVM Theory — Logical Volume Manager"

    cat << 'EOF'
  LVM adds a layer of abstraction between physical disks and filesystems.
  It allows flexible disk management: resize, snapshot, span across disks.

  ┌─────────────────────────────────────────────────────────────────┐
  │                     LVM Architecture                            │
  ├─────────────────────────────────────────────────────────────────┤
  │                                                                 │
  │  Physical Disks/Partitions                                      │
  │  ┌──────┐  ┌──────┐  ┌──────┐                                   │
  │  │/dev/ │  │/dev/ │  │/dev/ │                                   │
  │  │ vdb  │  │ vdc  │  │ vdd  │    ← Real hardware                │
  │  └──┬───┘  └──┬───┘  └──┬───┘                                   │
  │     │         │         │                                       │
  │     ▼         ▼         ▼                                       │
  │  ┌──────┐  ┌──────┐  ┌──────┐                                   │
  │  │  PV  │  │  PV  │  │  PV  │    ← Physical Volumes             │
  │  │      │  │      │  │      │      (pvcreate /dev/vdX)          │
  │  └──┬───┘  └──┬───┘  └──┬───┘                                   │
  │     │         │         │                                       │
  │     └─────────┼─────────┘                                       │
  │               ▼                                                 │
  │  ┌────────────────────────┐                                     │
  │  │     Volume Group (VG)  │       ← Pool of storage             │
  │  │      "my_vg"           │         (vgcreate my_vg PV PV...)   │
  │  │  ┌─────────────────┐   │                                     │
  │  │  │  Free Extents   │   │        Divided into fixed-size      │
  │  │  │  ████████░░░░░░ │   │        Physical Extents (PE)        │
  │  │  └─────────────────┘   │       (default 4MB each)            │
  │  └───────┬────────┬───────┘                                     │
  │          │        │                                             │
  │          ▼        ▼                                             │
  │  ┌───────────┐  ┌───────────┐                                   │
  │  │    LV     │  │    LV     │     ← Logical Volumes             │
  │  │  "data"   │  │  "logs"   │       (lvcreate -L 2G ...)        │
  │  └─────┬─────┘  └─────┬─────┘                                   │
  │        │              │                                         │
  │        ▼              ▼                                         │
  │  ┌───────────┐  ┌───────────┐                                   │
  │  │    ext4   │  │    xfs    │     ← Filesystems                 │
  │  │  /data    │  │  /logs    │       (mkfs + mount)              │
  │  └───────────┘  └───────────┘                                   │
  └─────────────────────────────────────────────────────────────────┘

  Key Concepts:
  ─────────────
  PV (Physical Volume)   The raw disk or partition prepared for LVM.
                         Command: pvcreate /dev/vdb

  VG (Volume Group)      A pool combining one or more PVs.
                         Command: vgcreate my_vg /dev/vdb /dev/vdc

  LV (Logical Volume)    A virtual partition carved from a VG.
                         Command: lvcreate -L 2G -n data my_vg

  Key Advantages:
  ───────────────
  ✓  Resize volumes live (grow/shrink without unmounting for ext4 grow)
  ✓  Span across multiple physical disks
  ✓  Snapshots for backups
  ✓  Thin provisioning (over-commit storage)
  ✓  Move data between disks transparently (pvmove)
EOF

    pause
}

# ── Combined RAID + LVM Theory ──
theory_combined() {
    section "Combining RAID + LVM"

    cat << 'EOF'
  Best practice: RAID underneath, LVM on top.
  RAID provides redundancy; LVM provides flexibility.

  ┌────────────────────────────────────────────────────────┐
  │            The Storage Stack                           │
  ├────────────────────────────────────────────────────────┤
  │                                                        │
  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                │
  │  │ vdb  │  │ vdc  │  │ vdd  │  │ vde  │  Physical      │
  │  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘  Disks         │
  │     └────┬────┘         └────┬────┘                    │
  │          ▼                   ▼                         │
  │    ┌──────────┐        ┌──────────┐                    │
  │    │  md0     │        │  md1     │   RAID Arrays      │
  │    │ (RAID 1) │        │ (RAID 1) │   (redundancy)     │
  │    └────┬─────┘        └────┬─────┘                    │
  │         └───────┬───────────┘                          │
  │                 ▼                                      │
  │    ┌──────────────────────┐                            │
  │    │  Volume Group "vg0"  │        LVM VG              │
  │    │  (PV: md0 + md1)    │        (flexibility)        │
  │    └──────┬───────┬───────┘                            │
  │           ▼       ▼                                    │
  │    ┌─────────┐ ┌─────────┐                             │
  │    │   LV    │ │   LV    │         Logical Volumes     │
  │    │ "data"  │ │ "logs"  │         (virtual partitions)│
  │    └────┬────┘ └────┬────┘                             │
  │         ▼           ▼                                  │
  │    ┌─────────┐ ┌─────────┐                             │
  │    │  ext4   │ │  xfs    │         Filesystems         │
  │    └─────────┘ └─────────┘                             │
  └────────────────────────────────────────────────────────┘

  Why this order?
  ───────────────
  1. RAID first: protects against disk failure at the lowest level
  2. LVM on top: gives you resize, snapshots, flexibility
  3. Never put RAID on top of LVM — you'd lose redundancy guarantees
EOF

    pause
}

# ── Disk naming conventions ──
theory_disk_naming() {
    section "Linux Disk Naming Conventions"

    cat << 'EOF'
  ┌─────────────────────────────────────────────────────────────┐
  │  Device Naming                                              │
  ├─────────────────────────────────────────────────────────────┤
  │                                                             │
  │  /dev/sdX    — SCSI/SATA disks (sda, sdb, sdc, ...)         │
  │  /dev/vdX    — VirtIO disks (vda, vdb, vdc, ...)            │
  │  /dev/nvmeXnY — NVMe drives                                 │
  │  /dev/mdX    — Software RAID arrays (md0, md1, ...)         │
  │                                                             │
  │  In this lab (VirtIO):                                      │
  │  ─────────────────────                                      │
  │  /dev/vda  → OS disk (Ubuntu system)                        │
  │  /dev/vdb  → Data disk 1  (serial: DISK-DATA01)             │
  │  /dev/vdc  → Data disk 2  (serial: DISK-DATA02)             │
  │  /dev/vdd  → Data disk 3  (serial: DISK-DATA03)             │
  │  /dev/vde  → Data disk 4  (serial: DISK-DATA04)             │
  │                                                             │
  │  Useful commands:                                           │
  │    lsblk                         — List block devices       │
  │    lsblk -o NAME,SIZE,SERIAL     — Show with serial numbers │
  │    cat /proc/mdstat              — RAID array status        │
  │    pvs / vgs / lvs               — LVM status               │
  └─────────────────────────────────────────────────────────────┘
EOF

    pause
}

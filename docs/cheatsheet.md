# Storage Cheat Sheet — mdadm RAID, LVM & ZFS

Quick reference for all the commands used in this lab.

---

## mdadm — RAID Management

### Create Arrays

```bash
# RAID 0 (stripe) — 2+ disks, no redundancy, max speed
mdadm --create /dev/md0 --level=0 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run

# RAID 1 (mirror) — 2 disks, survives 1 failure
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run

# RAID 5 (stripe+parity) — 3+ disks, survives 1 failure
mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/vdb /dev/vdc /dev/vdd --metadata=1.2 --run

# RAID 10 (mirror+stripe) — 4+ disks, survives 1 per mirror pair
mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/vdb /dev/vdc /dev/vdd /dev/vde --metadata=1.2 --run
```

### Monitor & Status

```bash
# Quick status (kernel view)
cat /proc/mdstat

# Detailed array info
mdadm --detail /dev/md0

# Examine a disk's RAID metadata
mdadm --examine /dev/vdb
```

### Disk Failure & Recovery

```bash
# Mark a disk as failed
mdadm /dev/md0 --fail /dev/vdc

# Remove failed disk from array
mdadm /dev/md0 --remove /dev/vdc

# Add replacement disk (rebuild starts automatically)
mdadm /dev/md0 --add /dev/vdc

# Wait for rebuild to complete
mdadm --wait /dev/md0
```

### Destroy

```bash
# Stop an array
mdadm --stop /dev/md0

# Clear RAID metadata from disks
mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd /dev/vde
```

### Persist Configuration

```bash
# Save config (survives reboot)
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u
```

---

## LVM — Logical Volume Manager

### Physical Volumes (PV)

```bash
# Create PVs on raw disks (or RAID arrays)
pvcreate /dev/vdb /dev/vdc
pvcreate /dev/md0              # PV on RAID array

# List PVs
pvs
pvdisplay /dev/vdb

# Remove PV
pvremove /dev/vdb
```

### Volume Groups (VG)

```bash
# Create VG from one or more PVs
vgcreate my_vg /dev/vdb /dev/vdc

# List VGs
vgs
vgdisplay my_vg

# Extend VG with another PV
vgextend my_vg /dev/vdd

# Remove VG
vgremove my_vg
```

### Logical Volumes (LV)

```bash
# Create LV with fixed size
lvcreate -L 2G -n data_lv my_vg

# Create LV using all free space
lvcreate -l 100%FREE -n data_lv my_vg

# List LVs
lvs
lvdisplay /dev/my_vg/data_lv

# Extend LV
lvextend -L +1G /dev/my_vg/data_lv      # add 1G
lvextend -l +100%FREE /dev/my_vg/data_lv # use all remaining space

# Remove LV
lvremove /dev/my_vg/data_lv
```

---

## ZFS — Combined Volume Manager + Filesystem

### Create Pools

```bash
# Mirror pool (like RAID 1) — 2 disks, survives 1 failure
zpool create tank mirror /dev/vdb /dev/vdc

# RAIDZ pool (like RAID 5) — 3+ disks, survives 1 failure
zpool create datapool raidz /dev/vdb /dev/vdc /dev/vdd

# RAIDZ2 pool (like RAID 6) — 4+ disks, survives 2 failures
zpool create datapool raidz2 /dev/vdb /dev/vdc /dev/vdd /dev/vde

# Stripe pool (like RAID 0) — no redundancy
zpool create fast /dev/vdb /dev/vdc
```

### Pool Status & Management

```bash
# List all pools
zpool list

# Detailed pool health
zpool status
zpool status tank

# Verbose status with checksum errors
zpool status -v tank

# Run integrity scrub (verify all checksums)
zpool scrub tank

# Pool I/O statistics
zpool iostat tank 1
```

### Datasets

```bash
# Create dataset (auto-mounted at /tank/data)
zfs create tank/data
zfs create tank/logs

# List all datasets
zfs list
zfs list -r tank                 # recursive

# Set properties
zfs set quota=2G tank/data       # limit space usage
zfs set compression=lz4 tank/logs # enable compression
zfs set mountpoint=/mydata tank/data  # custom mount point

# View properties
zfs get quota,compression,mountpoint tank/data
zfs get all tank/data

# Destroy dataset
zfs destroy tank/data
```

### Snapshots & Rollback

```bash
# Create snapshot (instant, zero-cost)
zfs snapshot tank/data@before-upgrade
zfs snapshot -r tank@backup      # recursive (all child datasets)

# List snapshots
zfs list -t snapshot
zfs list -t snapshot -r tank     # recursive

# Rollback to snapshot (instant)
zfs rollback tank/data@before-upgrade

# Destroy snapshot
zfs destroy tank/data@before-upgrade
```

### Disk Failure & Recovery

```bash
# Offline a disk (simulate failure)
zpool offline tank /dev/vdc

# Bring disk back online
zpool online tank /dev/vdc

# Replace a disk with a new one
zpool replace tank /dev/vdc /dev/vdd

# Check resilver/rebuild status
zpool status tank
```

### Destroy

```bash
# Destroy a pool (removes everything)
zpool destroy tank
zpool destroy -f tank            # force

# Clear disk labels
wipefs -a /dev/vdb /dev/vdc
```

---

## Filesystem Operations

```bash
# Create filesystem
mkfs.ext4 /dev/md0                      # on RAID array
mkfs.ext4 /dev/my_vg/data_lv            # on LV

# Mount
mkdir -p /mnt/data
mount /dev/md0 /mnt/data

# Resize ext4 filesystem (after lvextend, works online)
resize2fs /dev/my_vg/data_lv

# Check usage
df -h /mnt/data

# Unmount
umount /mnt/data
```

---

## Disk Inspection

```bash
# List block devices
lsblk
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,SERIAL

# Disk usage
df -h

# Partition table
fdisk -l /dev/vdb

# Identify filesystem
blkid /dev/md0
```

---

## Common Patterns

### Full RAID 1 Setup

```bash
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run
mkfs.ext4 /dev/md0
mkdir -p /mnt/raid1
mount /dev/md0 /mnt/raid1
```

### Full LVM Setup

```bash
pvcreate /dev/vdb /dev/vdc
vgcreate data_vg /dev/vdb /dev/vdc
lvcreate -L 5G -n app_lv data_vg
mkfs.ext4 /dev/data_vg/app_lv
mkdir -p /mnt/app
mount /dev/data_vg/app_lv /mnt/app
```

### LVM on RAID (Production Pattern)

```bash
# 1. Create RAID
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/vdb /dev/vdc --metadata=1.2 --run

# 2. LVM on top
pvcreate /dev/md0
vgcreate secure_vg /dev/md0
lvcreate -L 2G -n db_lv secure_vg
mkfs.ext4 /dev/secure_vg/db_lv
mount /dev/secure_vg/db_lv /mnt/database
```

### Full ZFS Setup (Mirror + Datasets + Snapshot)

```bash
# 1. Create mirror pool
zpool create tank mirror /dev/vdb /dev/vdc

# 2. Create datasets
zfs create tank/data
zfs create tank/logs
zfs set quota=5G tank/data
zfs set compression=lz4 tank/logs

# 3. Use it (auto-mounted)
echo "hello" > /tank/data/file.txt

# 4. Snapshot before risky change
zfs snapshot tank/data@safe-point

# 5. Oops, rollback
zfs rollback tank/data@safe-point
```

### Full Cleanup (reverse order)

```bash
# Unmount
umount /mnt/data

# Remove LVM (if used)
lvremove -f /dev/my_vg/data_lv
vgremove -f my_vg
pvremove /dev/md0

# Stop RAID
mdadm --stop /dev/md0
mdadm --zero-superblock /dev/vdb /dev/vdc

# Destroy ZFS (if used)
zpool destroy -f tank
wipefs -a /dev/vdb /dev/vdc /dev/vdd /dev/vde
```

---

## RAID Level Comparison

| Level | Min Disks | Capacity | Redundancy | Read Speed | Write Speed | Use Case |
|-------|-----------|----------|------------|------------|-------------|----------|
| 0 | 2 | N × disk | None | Fast | Fast | Temp data, scratch |
| 1 | 2 | 1 × disk | 1 failure | Fast | Normal | OS, boot drives |
| 5 | 3 | (N-1) × disk | 1 failure | Fast | Slower | File servers, NAS |
| 10 | 4 | N/2 × disk | 1 per pair | Fastest | Fast | Databases |

---

## ZFS Pool Type Comparison

| Type | Min Disks | Capacity | Redundancy | Equivalent | Use Case |
|------|-----------|----------|------------|------------|----------|
| stripe | 1 | N × disk | None | RAID 0 | Temp data |
| mirror | 2 | 1 × disk | 1+ failure | RAID 1 | OS, databases |
| raidz | 3 | (N-1) × disk | 1 failure | RAID 5 | File servers, NAS |
| raidz2 | 4 | (N-2) × disk | 2 failures | RAID 6 | Critical data |

---

## mdadm+LVM vs ZFS

| Feature | mdadm + LVM + ext4 | ZFS |
|---------|--------------------|----|
| RAID | mdadm | Built-in (mirror/raidz) |
| Volume management | LVM | Built-in (pools/datasets) |
| Filesystem | ext4/xfs | Built-in |
| Snapshots | LVM snapshots | Native COW (instant) |
| Data checksums | No | Yes (every block) |
| Self-healing | No | Yes (with redundancy) |
| Commands | mdadm + pv/vg/lv + mkfs | zpool + zfs |
| RAM usage | Low | Higher (ARC cache) |

---

## Reading /proc/mdstat

```
md0 : active raid1 vdc[1] vdb[0]
      5237760 blocks super 1.2 [2/2] [UU]
```

- `[2/2]` → 2 expected devices, 2 active
- `[UU]` → both disks Up (healthy)
- `[U_]` → one disk Up, one missing (degraded)
- `[>...]` → rebuild/sync in progress
- `(F)` after a device → marked as faulty

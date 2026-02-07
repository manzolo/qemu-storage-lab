# QEMU Storage Lab

An interactive, hands-on lab for learning **mdadm RAID** and **LVM** using QEMU/KVM virtual machines.
Everything runs inside a disposable VM — your host system is never touched.

## Features

- **RAID Labs** — Create, inspect, break and rebuild RAID 0, 1, 5, 10 arrays
- **LVM Labs** — Physical Volumes, Volume Groups, Logical Volumes, live resize
- **LVM on RAID** — Production-style architecture: RAID for redundancy + LVM for flexibility
- **Guided Demos** — Interactive step-by-step tutorials: run each command with Enter, skip with `s`, quit with `q`
- **Theory sections** — Built-in explanations of every concept
- **Automated test suite** — Non-interactive tests for every scenario, CI-ready

## Quick Start

```bash
git clone https://github.com/manzolo/qemu-storage-lab.git
cd qemu-storage-lab
./storage-lab.sh
```

The interactive menu will guide you through setup (download Ubuntu cloud image, create disks, boot VM) and all labs.

### Prerequisites

| Package | Ubuntu/Debian |
|---------|---------------|
| QEMU | `sudo apt install qemu-system-x86 qemu-utils` |
| SSH + sshpass | `sudo apt install openssh-client sshpass` |
| Cloud-init tools | `sudo apt install cloud-image-utils` |

## Architecture

```
Host (your machine)
 └─ QEMU/KVM VM (Ubuntu 24.04 cloud image)
     ├─ /dev/vda  — OS disk (10G)
     ├─ /dev/vdb  — Data disk 1 (5G)
     ├─ /dev/vdc  — Data disk 2 (5G)
     ├─ /dev/vdd  — Data disk 3 (5G)
     └─ /dev/vde  — Data disk 4 (5G)
```

All data disks are disposable qcow2 images. You can destroy and recreate them at any time.

## Interactive Menu

```
  ╔══════════════════════════════════════════════════════╗
  ║           QEMU STORAGE LAB                           ║
  ║       Learn RAID & LVM hands-on                      ║
  ╚══════════════════════════════════════════════════════╝

  1) Setup & Installation
  2) Disk Management
  3) VM Management
  4) RAID Labs (mdadm)
  5) LVM Labs
  6) Theory & Documentation
  7) Guided Demos (Interactive Tutorials)
  8) Full Reset (destroy everything)
  0) Exit
```

### RAID Labs

| Lab | Disks | Description |
|-----|-------|-------------|
| RAID 0 | 2 | Striping — max performance, no redundancy |
| RAID 1 | 2 | Mirroring — exact copy on both disks |
| RAID 5 | 3 | Striping + distributed parity — survives 1 disk failure |
| RAID 10 | 4 | Mirror + stripe — best for databases |

Each lab includes: create array, format, mount, write/read data, simulate failure, rebuild, verify data integrity.

### LVM Labs

| Lab | Description |
|-----|-------------|
| Basic LVM | PV → VG → LV → filesystem → mount |
| Resize | Live extend LV + resize2fs (no downtime) |
| LVM on RAID | RAID 1 → PV → VG → LV (production pattern) |

### Guided Demos

Interactive, step-by-step tutorials that explain each command before running it. The user controls execution: press **Enter** to run, **s** to skip, **q** to quit.

| Demo | Description |
|------|-------------|
| RAID 1 | Mirror: create → write data → simulate failure → rebuild → verify integrity |
| RAID 5 | Parity: create → write data → simulate failure → rebuild → verify integrity |
| RAID 10 | Mirror+Stripe: create → write data → simulate failure → rebuild → verify integrity |
| LVM | PV → VG → LV → filesystem → live resize → reverse cleanup |
| LVM on RAID | Production pattern: RAID 1 → PV → VG → LV → full stack overview → cleanup |

Each demo starts with an automatic cleanup, includes educational notes between steps, and verifies expected results.

## Cheat Sheet

See [docs/cheatsheet.md](docs/cheatsheet.md) for a quick reference of all mdadm and LVM commands.

## Test Suite

Automated, non-interactive tests for CI and local verification.

```bash
# Full run (creates VM, runs all tests, tears down)
./tests/run-all-tests.sh

# Skip VM setup (VM already running)
./tests/run-all-tests.sh --skip-setup

# Run a single test
./tests/test-raid5.sh --skip-setup

# Keep VM alive after tests
./tests/run-all-tests.sh --skip-vm-teardown
```

### Test Coverage

| Test | What it verifies |
|------|-----------------|
| `test-raid0.sh` | Create → verify level → write/read → cleanup |
| `test-raid1.sh` | Create → write → fail disk → rebuild → verify data intact |
| `test-raid5.sh` | Create → write → fail disk → rebuild → verify data intact |
| `test-raid10.sh` | Create → write → fail disk → rebuild → verify data intact |
| `test-lvm-basic.sh` | PV → VG → LV → mount → write → extend → resize → cleanup |
| `test-lvm-raid.sh` | RAID 1 → PV → VG → LV → mount → write → full cleanup |

### CI (GitHub Actions)

Tests run automatically on push and pull request. The workflow installs QEMU, enables KVM, caches the cloud image, and runs the full suite.

See [`.github/workflows/test-raid.yml`](.github/workflows/test-raid.yml).

## Project Structure

```
qemu-storage-lab/
├── storage-lab.sh              # Main entry point (interactive menu)
├── lab.conf                    # Optional: override defaults (VM_RAM, ports, etc.)
├── demos/
│   ├── demo-common.sh          # Shared interactive demo framework
│   ├── demo-raid1.sh           # RAID 1 guided tutorial
│   ├── demo-raid5.sh           # RAID 5 guided tutorial
│   ├── demo-raid10.sh          # RAID 10 guided tutorial
│   ├── demo-lvm.sh             # LVM guided tutorial
│   └── demo-lvm-on-raid.sh     # LVM on RAID guided tutorial
├── scripts/
│   ├── config.sh               # Configuration, colors, logging utilities
│   ├── disk-manager.sh         # Create/delete/list qcow2 disk images
│   ├── vm-manager.sh           # Start/stop/status QEMU VM
│   ├── ssh-utils.sh            # SSH connection helpers
│   ├── raid-labs.sh            # RAID 0, 1, 5, 10 labs
│   ├── lvm-labs.sh             # LVM labs (basic, resize, on RAID)
│   └── theory.sh               # Theory & documentation sections
├── tests/
│   ├── test-common.sh          # Shared test framework
│   ├── test-raid0.sh           # RAID 0 tests
│   ├── test-raid1.sh           # RAID 1 tests
│   ├── test-raid5.sh           # RAID 5 tests
│   ├── test-raid10.sh          # RAID 10 tests
│   ├── test-lvm-basic.sh       # Basic LVM tests
│   ├── test-lvm-raid.sh        # LVM on RAID tests
│   └── run-all-tests.sh        # Test runner
├── disks/                      # Generated disk images (gitignored)
├── cloud-init/                 # Generated cloud-init files
├── logs/                       # Session logs
└── .github/workflows/
    └── test-raid.yml           # CI workflow
```

## Configuration

Create a `lab.conf` file to override defaults:

```bash
VM_RAM=2048            # VM memory in MB (default: 1024)
VM_CPUS=2             # VM CPUs (default: 1)
VM_SSH_PORT=2222      # SSH port forwarding (default: 2222)
DATA_DISK_COUNT=4     # Number of data disks (default: 4)
DATA_DISK_SIZE=5G     # Size of each data disk (default: 5G)
VM_USER=lab           # VM username (default: lab)
VM_PASS=lab           # VM password (default: lab)
```

## License

MIT

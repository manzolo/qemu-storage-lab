QEMU STORAGE LAB — Quick-Start Guide
=====================================

Learn mdadm RAID and LVM hands-on using a QEMU virtual machine.
Safe: never touches your host disks.

REQUIREMENTS
------------
- Linux host (tested on Ubuntu/Debian)
- 4GB+ RAM (1GB allocated to VM)
- ~15GB free disk space
- Packages: qemu-system-x86 qemu-utils openssh-client sshpass cloud-image-utils

Install dependencies (Debian/Ubuntu):

  sudo apt install qemu-system-x86 qemu-utils openssh-client sshpass cloud-image-utils

QUICK START
-----------
1. Run the lab:

     ./storage-lab.sh

2. Select "1) Setup & Installation"
   - Downloads Ubuntu 24.04 cloud image (~600MB, one-time)
   - Creates OS disk, data disks, and cloud-init seed
   - Boots the VM and waits for SSH

3. Try a RAID lab:
   - Select "4) RAID Labs" → "2) Create RAID 1"
   - Follow along as the script explains each step

4. Try LVM:
   - Select "5) LVM Labs" → "2) Basic LVM"

5. When done:
   - "3) VM Management" → "2) Stop VM"
   - Or "7) Full Reset" to clean everything up

PROJECT STRUCTURE
-----------------
  storage-lab.sh        Main entry point (menus)
  lab.conf              Configuration (RAM, CPUs, disk sizes, etc.)
  scripts/
    config.sh           Shared config, colors, logging
    disk-manager.sh     Create/delete/list disk images
    vm-manager.sh       Start/stop/status QEMU VM
    ssh-utils.sh        SSH connection helpers
    raid-labs.sh        RAID labs (create, fail, rebuild)
    lvm-labs.sh         LVM labs (PV, VG, LV, resize)
    theory.sh           Educational content with diagrams
  disks/                Disk images (auto-created, gitignored)
  cloud-init/           Cloud-init user-data/meta-data
  logs/                 Session logs (gitignored)

CONFIGURATION
-------------
Edit lab.conf to adjust:
  VM_RAM          RAM in MB (default: 1024)
  VM_CPUS         CPU cores (default: 1)
  VM_SSH_PORT     Host port for SSH (default: 2222)
  DATA_DISK_COUNT Number of data disks (default: 4)
  DATA_DISK_SIZE  Size of each data disk (default: 5G)
  OS_DISK_SIZE    OS disk size (default: 10G)
  VM_USER/VM_PASS Guest credentials (default: lab/lab)

MANUAL SSH ACCESS
-----------------
While the VM is running, you can connect directly:

  sshpass -p lab ssh -o StrictHostKeyChecking=no -p 2222 lab@localhost

TROUBLESHOOTING
---------------
- "SSH timed out": The VM may need more time on first boot (cloud-init
  installs packages). Try stopping and starting the VM again.

- "qemu-system-x86_64 not found": Install qemu-system-x86:
    sudo apt install qemu-system-x86

- "KVM not available": The lab falls back to TCG (software emulation).
  It will be slower but works. To enable KVM:
    sudo apt install qemu-kvm
    sudo usermod -aG kvm $USER
    (log out and back in)

- "Port 2222 in use": Change VM_SSH_PORT in lab.conf.

- Disk space issues: Reduce DATA_DISK_SIZE or DATA_DISK_COUNT in lab.conf.

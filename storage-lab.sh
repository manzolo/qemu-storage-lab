#!/usr/bin/env bash
# storage-lab.sh — Main entry point for the QEMU RAID/LVM Storage Lab
#
# Usage: ./storage-lab.sh
#
# An interactive CLI lab for learning mdadm RAID and LVM
# using QEMU/KVM virtual machines. Safe — never touches host disks.

set -euo pipefail

# ── Parse flags ──
for arg in "$@"; do
    case "$arg" in
        --debug) export VM_DEBUG=1 ;;
    esac
done

# ── Source all modules ──
# Note: config.sh overwrites SCRIPT_DIR, so we use PROJECT_DIR here.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/scripts/config.sh"
source "$PROJECT_DIR/scripts/disk-manager.sh"
source "$PROJECT_DIR/scripts/vm-manager.sh"
source "$PROJECT_DIR/scripts/ssh-utils.sh"
source "$PROJECT_DIR/scripts/theory.sh"
source "$PROJECT_DIR/scripts/raid-labs.sh"
source "$PROJECT_DIR/scripts/lvm-labs.sh"
source "$PROJECT_DIR/demos/demo-common.sh"
source "$PROJECT_DIR/demos/demo-raid1.sh"
source "$PROJECT_DIR/demos/demo-raid5.sh"
source "$PROJECT_DIR/demos/demo-raid10.sh"
source "$PROJECT_DIR/demos/demo-lvm.sh"
source "$PROJECT_DIR/demos/demo-lvm-on-raid.sh"

# ── Check for leftover VM ──
if vm_is_running; then
    warn "A VM is still running from a previous session (PID: $(<"$PID_FILE"))."
    if confirm "Stop it before continuing?"; then
        vm_stop
    else
        info "Keeping existing VM running."
    fi
fi

# ── Banner ──
show_banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'EOF'
  ╔══════════════════════════════════════════════════════╗
  ║           QEMU STORAGE LAB                           ║
  ║       Learn RAID & LVM hands-on                      ║
  ╚══════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

# ── Main Menu ──
menu_main() {
    while true; do
        clear
        show_banner
        echo -e "${BOLD}  Main Menu${RESET}"
        hr
        echo "  1) Setup & Installation"
        echo "  2) Disk Management"
        echo "  3) VM Management"
        echo "  4) RAID Labs (mdadm)"
        echo "  5) LVM Labs"
        echo "  6) Theory & Documentation"
        echo "  7) Guided Demos (Interactive Tutorials)"
        echo "  8) Full Reset (destroy everything)"
        echo "  0) Exit"
        hr
        echo ""
        echo -n "  Choose [0-8]: "
        read -r choice

        case "$choice" in
            1) menu_setup ;;
            2) menu_disks ;;
            3) menu_vm ;;
            4) menu_raid ;;
            5) menu_lvm ;;
            6) menu_theory ;;
            7) menu_demos ;;
            8) full_reset ;;
            0) echo ""; info "Goodbye!"; exit 0 ;;
            *) warn "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ── Setup & Installation ──
menu_setup() {
    section "Setup & Installation"

    # Step 1: Dependencies
    check_dependencies || { pause; return; }

    # Step 2: Download cloud image
    disk_download_cloud_image || { pause; return; }

    # Step 3: Create OS disk
    disk_create_os || { pause; return; }

    # Step 4: Cloud-init seed
    disk_create_cloud_init || { pause; return; }

    # Step 5: Data disks
    disk_create_data || { pause; return; }

    # Step 6: Show inventory
    disk_list

    # Step 7: Start VM
    echo ""
    if confirm "Start the VM now?"; then
        vm_start || { pause; return; }

        # Step 8: Verify packages
        section "Verifying Guest Packages"
        ssh_exec_show "dpkg -l | grep -E 'mdadm|lvm2|xfsprogs' | awk '{print \$2, \$3}'" \
            "Checking that RAID/LVM tools are installed in the VM"

        ssh_exec_show "lsblk -o NAME,SIZE,SERIAL,TYPE" \
            "Block devices visible inside the VM"
    fi

    success "Setup complete! The lab is ready."
    pause
}

# ── Disk Management Sub-menu ──
menu_disks() {
    while true; do
        clear
        show_banner
        echo -e "${BOLD}  Disk Management${RESET}"
        hr
        echo "  1) List all disks"
        echo "  2) Create data disks"
        echo "  3) Delete all data disks"
        echo "  4) Replace a data disk"
        echo "  5) Full disk reset (delete everything)"
        echo "  0) Back"
        hr
        echo ""
        echo -n "  Choose [0-5]: "
        read -r choice

        case "$choice" in
            1) disk_list; pause ;;
            2) disk_create_data; pause ;;
            3) disk_delete_all; pause ;;
            4)
                echo -n "  Disk number to replace [1-${DATA_DISK_COUNT}]: "
                read -r num
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= DATA_DISK_COUNT )); then
                    disk_replace "$num"
                else
                    warn "Invalid disk number."
                fi
                pause
                ;;
            5) disk_reset; pause ;;
            0) return ;;
            *) warn "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ── VM Management Sub-menu ──
menu_vm() {
    while true; do
        clear
        show_banner
        echo -e "${BOLD}  VM Management${RESET}"
        hr
        vm_status
        hr
        echo "  1) Start VM"
        echo "  2) Stop VM"
        echo "  3) VM Status"
        echo "  4) Open SSH session"
        echo "  0) Back"
        hr
        echo ""
        echo -n "  Choose [0-4]: "
        read -r choice

        case "$choice" in
            1) vm_start; pause ;;
            2) vm_stop; pause ;;
            3) vm_status; pause ;;
            4) vm_ssh ;;
            0) return ;;
            *) warn "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ── RAID Labs Sub-menu ──
menu_raid() {
    while true; do
        clear
        show_banner
        echo -e "${BOLD}  RAID Labs (mdadm)${RESET}"
        hr
        echo "  1) Theory: Understanding RAID"
        echo "  2) Create RAID 0 (stripe)"
        echo "  3) Create RAID 1 (mirror)"
        echo "  4) Create RAID 5 (striping+parity)"
        echo "  5) Create RAID 10 (mirror+stripe)"
        echo "  6) Show RAID Status"
        echo "  7) Simulate Disk Failure"
        echo "  8) Remove Failed Disk"
        echo "  9) Replace & Rebuild"
        echo " 10) Destroy RAID Arrays"
        echo "  0) Back"
        hr
        echo ""
        echo -n "  Choose [0-10]: "
        read -r choice

        case "$choice" in
            1) theory_raid ;;
            2) raid_lab_raid0 ;;
            3) raid_lab_raid1 ;;
            4) raid_lab_raid5 ;;
            5) raid_lab_raid10 ;;
            6) raid_lab_status ;;
            7) raid_lab_fail_disk ;;
            8) raid_lab_remove_disk ;;
            9) raid_lab_replace_disk ;;
            10) raid_lab_destroy ;;
            0) return ;;
            *) warn "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ── LVM Labs Sub-menu ──
menu_lvm() {
    while true; do
        clear
        show_banner
        echo -e "${BOLD}  LVM Labs${RESET}"
        hr
        echo "  1) Theory: Understanding LVM"
        echo "  2) Basic LVM (PV → VG → LV)"
        echo "  3) Resize a Logical Volume"
        echo "  4) LVM on RAID"
        echo "  5) Clean Up LVM"
        echo "  0) Back"
        hr
        echo ""
        echo -n "  Choose [0-5]: "
        read -r choice

        case "$choice" in
            1) theory_lvm ;;
            2) lvm_lab_basic ;;
            3) lvm_lab_resize ;;
            4) lvm_lab_on_raid ;;
            5) lvm_lab_cleanup ;;
            0) return ;;
            *) warn "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ── Theory & Docs Sub-menu ──
menu_theory() {
    while true; do
        clear
        show_banner
        echo -e "${BOLD}  Theory & Documentation${RESET}"
        hr
        echo "  1) RAID Theory"
        echo "  2) LVM Theory"
        echo "  3) RAID + LVM Combined"
        echo "  4) Disk Naming Conventions"
        echo "  0) Back"
        hr
        echo ""
        echo -n "  Choose [0-4]: "
        read -r choice

        case "$choice" in
            1) theory_raid ;;
            2) theory_lvm ;;
            3) theory_combined ;;
            4) theory_disk_naming ;;
            0) return ;;
            *) warn "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ── Guided Demos Sub-menu ──
menu_demos() {
    while true; do
        clear
        show_banner
        echo -e "${BOLD}  Guided Demos (Interactive Tutorials)${RESET}"
        hr
        echo "  1) RAID 1  — Mirror: create, fail, rebuild"
        echo "  2) RAID 5  — Parity: create, fail, rebuild"
        echo "  3) RAID 10 — Mirror+Stripe: create, fail, rebuild"
        echo "  4) LVM     — PV, VG, LV, resize"
        echo "  5) LVM on RAID — Production pattern"
        echo "  0) Back"
        hr
        echo ""
        echo -n "  Choose [0-5]: "
        read -r choice

        case "$choice" in
            1) demo_raid1 ;;
            2) demo_raid5 ;;
            3) demo_raid10 ;;
            4) demo_lvm ;;
            5) demo_lvm_on_raid ;;
            0) return ;;
            *) warn "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ── Full Reset ──
full_reset() {
    section "Full Reset"
    echo -e "${RED}${BOLD}  WARNING: This will destroy EVERYTHING:${RESET}"
    echo "  - Stop the VM (if running)"
    echo "  - Delete all disk images"
    echo "  - Delete cloud-init files"
    echo "  - Delete logs"
    echo ""

    if ! confirm "Are you absolutely sure?"; then
        info "Cancelled."
        pause
        return
    fi

    # Stop VM first
    if vm_is_running; then
        vm_stop
    fi

    # Delete disks
    rm -f "$DISKS_DIR"/*.qcow2 "$DISKS_DIR"/*.iso "$DISKS_DIR"/*.img
    rm -f "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    rm -f "$PID_FILE" "$MONITOR_SOCK"

    # Clear logs
    rm -f "$LOGS_DIR"/*.log

    success "Full reset complete. Run Setup to start fresh."
    pause
}

# ── Entry point ──
menu_main

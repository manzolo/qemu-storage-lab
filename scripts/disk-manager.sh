#!/usr/bin/env bash
# disk-manager.sh — Create/delete/list/replace qcow2 disk images

# Guard against double-sourcing
[[ -n "${_DISK_MANAGER_LOADED:-}" ]] && return 0
_DISK_MANAGER_LOADED=1

# ── Source config if not already loaded ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"

# ── Download cloud image if needed ──
disk_download_cloud_image() {
    if [[ -f "$CLOUD_IMAGE_FILE" ]]; then
        info "Cloud image already exists: $(basename "$CLOUD_IMAGE_FILE")"
        return 0
    fi

    section "Downloading Ubuntu Cloud Image"
    info "URL: $CLOUD_IMAGE_URL"
    info "Destination: $CLOUD_IMAGE_FILE"
    echo ""

    if command -v wget &>/dev/null; then
        wget -O "$CLOUD_IMAGE_FILE" "$CLOUD_IMAGE_URL"
    elif command -v curl &>/dev/null; then
        curl -L -o "$CLOUD_IMAGE_FILE" "$CLOUD_IMAGE_URL"
    else
        error "Need wget or curl to download image."
        return 1
    fi

    success "Cloud image downloaded."
}

# ── Create OS disk from cloud image ──
disk_create_os() {
    if [[ -f "$OS_DISK" ]]; then
        info "OS disk already exists: $(basename "$OS_DISK")"
        return 0
    fi

    disk_download_cloud_image || return 1

    info "Creating OS disk from cloud image..."
    cp "$CLOUD_IMAGE_FILE" "$OS_DISK"
    qemu-img resize "$OS_DISK" "$OS_DISK_SIZE"
    success "OS disk created: $(basename "$OS_DISK") (${OS_DISK_SIZE})"
}

# ── Create data disks ──
disk_create_data() {
    local count="${1:-$DATA_DISK_COUNT}"
    info "Creating ${count} data disks (${DATA_DISK_SIZE} each)..."

    for i in $(seq 1 "$count"); do
        local num
        num=$(printf "%02d" "$i")
        local disk_file="$DISKS_DIR/data-${num}.qcow2"
        if [[ -f "$disk_file" ]]; then
            info "  data-${num}.qcow2 already exists, skipping."
        else
            qemu-img create -f qcow2 "$disk_file" "$DATA_DISK_SIZE" >/dev/null
            success "  Created data-${num}.qcow2 (${DATA_DISK_SIZE})"
        fi
    done
}

# ── Generate cloud-init seed ISO ──
disk_create_cloud_init() {
    if [[ -f "$SEED_ISO" ]]; then
        info "Cloud-init seed ISO already exists."
        return 0
    fi

    info "Generating cloud-init configuration..."

    # user-data
    cat > "$CLOUD_INIT_DIR/user-data" << 'USERDATA_EOF'
#cloud-config
hostname: storage-lab
manage_etc_hosts: true

users:
  - name: VM_USER_PLACEHOLDER
    plain_text_passwd: VM_PASS_PLACEHOLDER
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: [sudo]

ssh_pwauth: true

package_update: true
packages:
  - mdadm
  - lvm2
  - xfsprogs
  - e2fsprogs
  - zfsutils-linux

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
USERDATA_EOF

    # Replace placeholders with actual values
    sed -i "s/VM_USER_PLACEHOLDER/$VM_USER/g" "$CLOUD_INIT_DIR/user-data"
    sed -i "s/VM_PASS_PLACEHOLDER/$VM_PASS/g" "$CLOUD_INIT_DIR/user-data"

    # meta-data
    cat > "$CLOUD_INIT_DIR/meta-data" << EOF
instance-id: storage-lab-001
local-hostname: storage-lab
EOF

    # Build ISO
    if [[ "${CLOUD_INIT_TOOL:-}" == "cloud-localds" ]]; then
        cloud-localds "$SEED_ISO" "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    elif [[ "${CLOUD_INIT_TOOL:-}" == "genisoimage" ]]; then
        genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
            "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    else
        # Try to detect
        if command -v cloud-localds &>/dev/null; then
            cloud-localds "$SEED_ISO" "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
        elif command -v genisoimage &>/dev/null; then
            genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
                "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
        else
            error "No tool found to create cloud-init ISO."
            return 1
        fi
    fi

    success "Cloud-init seed ISO created."
}

# ── Delete all data disks ──
disk_delete_all() {
    if ! confirm "Delete ALL data disks?"; then
        info "Cancelled."
        return 0
    fi

    local count=0
    for f in "$DISKS_DIR"/data-*.qcow2; do
        [[ -f "$f" ]] || continue
        rm -f "$f"
        count=$((count + 1))
    done

    success "Deleted ${count} data disk(s)."
}

# ── Replace a single data disk (simulates new drive) ──
disk_replace() {
    local num
    num=$(printf "%02d" "$1")
    local disk_file="$DISKS_DIR/data-${num}.qcow2"

    info "Replacing data-${num}.qcow2 (simulating new blank drive)..."
    rm -f "$disk_file"
    qemu-img create -f qcow2 "$disk_file" "$DATA_DISK_SIZE" >/dev/null
    success "Replaced data-${num}.qcow2 with a fresh ${DATA_DISK_SIZE} disk."
}

# ── List all disks ──
disk_list() {
    section "Disk Inventory"
    printf "${BOLD}  %-25s %-12s %-10s${RESET}\n" "FILE" "VIRTUAL SIZE" "STATUS"
    hr

    # OS disk
    if [[ -f "$OS_DISK" ]]; then
        local os_size
        os_size=$(qemu-img info --output=json "$OS_DISK" 2>/dev/null | grep -m1 -o '"virtual-size": [0-9]*' | grep -o '[0-9]*' || true)
        if [[ -n "$os_size" ]]; then
            os_size="$(( os_size / 1073741824 ))G"
        else
            os_size="?"
        fi
        printf "  %-25s %-12s ${GREEN}%-10s${RESET}\n" "os.qcow2" "${OS_DISK_SIZE}" "ready"
    else
        printf "  %-25s %-12s ${RED}%-10s${RESET}\n" "os.qcow2" "-" "missing"
    fi

    # Seed ISO
    if [[ -f "$SEED_ISO" ]]; then
        printf "  %-25s %-12s ${GREEN}%-10s${RESET}\n" "seed.iso" "cloud-init" "ready"
    else
        printf "  %-25s %-12s ${RED}%-10s${RESET}\n" "seed.iso" "-" "missing"
    fi

    # Data disks
    for i in $(seq 1 "$DATA_DISK_COUNT"); do
        local num
        num=$(printf "%02d" "$i")
        local disk_file="$DISKS_DIR/data-${num}.qcow2"
        if [[ -f "$disk_file" ]]; then
            printf "  %-25s %-12s ${GREEN}%-10s${RESET}\n" "data-${num}.qcow2" "${DATA_DISK_SIZE}" "ready"
        else
            printf "  %-25s %-12s ${RED}%-10s${RESET}\n" "data-${num}.qcow2" "-" "missing"
        fi
    done

    echo ""
}

# ── Full reset: delete everything ──
disk_reset() {
    if ! confirm "DELETE ALL disks (OS, data, cloud-init)? This is irreversible!"; then
        info "Cancelled."
        return 0
    fi

    rm -f "$DISKS_DIR"/*.qcow2 "$DISKS_DIR"/*.iso "$DISKS_DIR"/*.img
    rm -f "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    success "All disks and cloud-init files removed."
}

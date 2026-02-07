#!/usr/bin/env bash
# vm-manager.sh — Start/stop/status QEMU VM

# Guard against double-sourcing
[[ -n "${_VM_MANAGER_LOADED:-}" ]] && return 0
_VM_MANAGER_LOADED=1

# ── Source dependencies ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ssh-utils.sh"

# ── Check if VM is running ──
vm_is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(<"$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Stale PID file
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# ── Start VM ──
vm_start() {
    if vm_is_running; then
        info "VM is already running (PID: $(<"$PID_FILE"))."
        return 0
    fi

    # Verify required disks exist
    if [[ ! -f "$OS_DISK" ]]; then
        error "OS disk not found. Run Setup first."
        return 1
    fi
    if [[ ! -f "$SEED_ISO" ]]; then
        error "Cloud-init seed ISO not found. Run Setup first."
        return 1
    fi

    local debug="${VM_DEBUG:-0}"
    local serial_log="$LOGS_DIR/serial.log"

    section "Starting QEMU VM"
    info "RAM: ${VM_RAM}MB | CPUs: ${VM_CPUS} | SSH port: ${VM_SSH_PORT}"

    # Build QEMU command (common options)
    local qemu_cmd=(
        qemu-system-x86_64
        -machine accel=kvm:tcg
        -m "$VM_RAM"
        -smp "$VM_CPUS"
        -drive "file=${OS_DISK},format=qcow2,if=none,id=os"
        -device "virtio-blk-pci,drive=os,bootindex=0"
        -cdrom "$SEED_ISO"
    )

    # Add data disks with serial numbers
    for i in $(seq 1 "$DATA_DISK_COUNT"); do
        local num
        num=$(printf "%02d" "$i")
        local disk_file="$DISKS_DIR/data-${num}.qcow2"
        if [[ -f "$disk_file" ]]; then
            local drive_id="data${num}"
            qemu_cmd+=(-drive "file=${disk_file},format=qcow2,if=none,id=${drive_id}")
            qemu_cmd+=(-device "virtio-blk-pci,drive=${drive_id},serial=DISK-DATA${num}")
        fi
    done

    # Networking: user-net with SSH port forwarding + monitor socket
    qemu_cmd+=(
        -nic "user,hostfwd=tcp::${VM_SSH_PORT}-:22"
        -monitor "unix:${MONITOR_SOCK},server,nowait"
        -pidfile "$PID_FILE"
    )

    if [[ "$debug" == "true" || "$debug" == "1" ]]; then
        # ── Debug mode: graphical window, daemonized ──
        qemu_cmd+=(-daemonize)
        info "DEBUG mode: QEMU graphical window will open"
        info "Launching QEMU..."

        "${qemu_cmd[@]}" 2>&1 || {
            error "Failed to start QEMU. Check logs."
            return 1
        }

        sleep 1

        if ! vm_is_running; then
            error "VM process did not start."
            return 1
        fi
        success "VM started (PID: $(<"$PID_FILE"))."
        info "Watch the QEMU window for boot progress."

        ssh_wait "${VM_SSH_TIMEOUT:-300}" || {
            error "VM started but SSH is not reachable."
            return 1
        }
    else
        # ── Normal mode: daemonize, no display, no serial ──
        qemu_cmd+=(-display none -serial null -daemonize)

        info "Launching QEMU..."
        "${qemu_cmd[@]}" 2>&1 || {
            error "Failed to start QEMU. Check logs."
            return 1
        }

        sleep 1

        if vm_is_running; then
            success "VM started (PID: $(<"$PID_FILE"))."
        else
            error "VM process did not start."
            return 1
        fi

        ssh_wait "${VM_SSH_TIMEOUT:-300}" || {
            error "VM started but SSH is not reachable."
            return 1
        }
    fi

    success "VM is ready!"
}

# ── Stop VM ──
vm_stop() {
    if ! vm_is_running; then
        info "VM is not running."
        return 0
    fi

    local pid
    pid=$(<"$PID_FILE")

    info "Stopping VM (PID: ${pid})..."

    # Method 1: graceful shutdown via SSH
    if ssh_check; then
        info "Sending 'sudo poweroff' via SSH..."
        ssh_exec "sudo poweroff" 2>/dev/null || true
        # Wait up to 30s for the process to die
        local waited=0
        while (( waited < 30 )); do
            if ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$PID_FILE" "$MONITOR_SOCK"
                success "VM stopped gracefully."
                return 0
            fi
            sleep 2
            waited=$(( waited + 2 ))
        done
        warn "Graceful shutdown timed out."
    fi

    # Method 2: QEMU monitor quit
    if [[ -S "$MONITOR_SOCK" ]] && command -v socat &>/dev/null; then
        info "Sending 'quit' via QEMU monitor..."
        echo "quit" | socat - UNIX-CONNECT:"$MONITOR_SOCK" 2>/dev/null || true
        sleep 3
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$PID_FILE" "$MONITOR_SOCK"
            success "VM stopped via monitor."
            return 0
        fi
    fi

    # Method 3: kill
    warn "Sending SIGTERM to PID ${pid}..."
    kill "$pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        warn "Sending SIGKILL..."
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE" "$MONITOR_SOCK"
    success "VM stopped."
}

# ── VM status ──
vm_status() {
    if vm_is_running; then
        local pid
        pid=$(<"$PID_FILE")
        echo -e "${GREEN}${BOLD}VM is RUNNING${RESET} (PID: ${pid})"
        echo -e "  SSH port: ${VM_SSH_PORT}"
        if ssh_check; then
            echo -e "  SSH: ${GREEN}reachable${RESET}"
        else
            echo -e "  SSH: ${RED}not reachable${RESET}"
        fi
    else
        echo -e "${RED}${BOLD}VM is STOPPED${RESET}"
    fi
}

# ── Open interactive SSH to VM ──
vm_ssh() {
    if ! vm_is_running; then
        error "VM is not running. Start it first."
        return 1
    fi
    if ! ssh_check; then
        error "VM is running but SSH is not reachable."
        return 1
    fi
    ssh_interactive
}

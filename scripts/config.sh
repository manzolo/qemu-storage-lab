#!/usr/bin/env bash
# config.sh — Load configuration, defaults, colors, logging utilities

set -euo pipefail

# ── Paths (relative to project root) ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISKS_DIR="$LAB_DIR/disks"
LOGS_DIR="$LAB_DIR/logs"
CLOUD_INIT_DIR="$LAB_DIR/cloud-init"
SCRIPTS_DIR="$LAB_DIR/scripts"
CONF_FILE="$LAB_DIR/lab.conf"
PID_FILE="$LAB_DIR/vm.pid"
MONITOR_SOCK="$LAB_DIR/vm.sock"
LOG_FILE="$LOGS_DIR/lab-$(date +%Y%m%d-%H%M%S).log"

# ── Defaults ──
VM_RAM="${VM_RAM:-1024}"
VM_CPUS="${VM_CPUS:-1}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
DATA_DISK_COUNT="${DATA_DISK_COUNT:-4}"
DATA_DISK_SIZE="${DATA_DISK_SIZE:-5G}"
OS_DISK_SIZE="${OS_DISK_SIZE:-10G}"
CLOUD_IMAGE_URL="${CLOUD_IMAGE_URL:-https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img}"
VM_USER="${VM_USER:-lab}"
VM_PASS="${VM_PASS:-lab}"

# ── Load user config (overrides defaults) ──
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
fi

# ── Derived paths ──
CLOUD_IMAGE_FILE="$DISKS_DIR/ubuntu-cloud.img"
OS_DISK="$DISKS_DIR/os.qcow2"
SEED_ISO="$DISKS_DIR/seed.iso"

# ── Ensure directories exist ──
mkdir -p "$DISKS_DIR" "$LOGS_DIR" "$CLOUD_INIT_DIR"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Logging ──
_log() {
    local level="$1" color="$2" msg="$3"
    local ts
    ts="$(date '+%H:%M:%S')"
    echo -e "${DIM}[${ts}]${RESET} ${color}${level}${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level} ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}

log()     { _log "INFO" "$CYAN"   "$*"; }
info()    { _log "INFO" "$CYAN"   "$*"; }
warn()    { _log "WARN" "$YELLOW" "$*"; }
error()   { _log "ERR " "$RED"    "$*"; }
success() { _log " OK " "$GREEN"  "$*"; }

# ── Confirmation prompt ──
confirm() {
    local msg="${1:-Are you sure?}"
    echo -en "${YELLOW}${msg} [Y/n]: ${RESET}"
    read -r reply
    [[ ! "$reply" =~ ^[Nn]$ ]]
}

# ── Dependency checker ──
require_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        error "Required command '${cmd}' not found."
        [[ -n "$hint" ]] && echo -e "  ${DIM}Hint: ${hint}${RESET}"
        return 1
    fi
}

# ── Check all host dependencies ──
check_dependencies() {
    local ok=true
    info "Checking host dependencies..."

    require_cmd qemu-system-x86_64 "Install: sudo apt install qemu-system-x86" || ok=false
    require_cmd qemu-img           "Install: sudo apt install qemu-utils"       || ok=false
    require_cmd ssh                "Install: sudo apt install openssh-client"   || ok=false
    require_cmd sshpass            "Install: sudo apt install sshpass"          || ok=false

    # Need either cloud-localds or genisoimage for cloud-init
    if command -v cloud-localds &>/dev/null; then
        CLOUD_INIT_TOOL="cloud-localds"
    elif command -v genisoimage &>/dev/null; then
        CLOUD_INIT_TOOL="genisoimage"
    else
        error "Need 'cloud-localds' (cloud-image-utils) or 'genisoimage'."
        echo -e "  ${DIM}Install: sudo apt install cloud-image-utils${RESET}"
        ok=false
    fi

    if $ok; then
        success "All dependencies satisfied."
    else
        error "Missing dependencies — install them and retry."
        return 1
    fi
}

# ── SSH base options ──
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

# ── Horizontal rule ──
hr() {
    echo -e "${DIM}$(printf '%.0s─' {1..60})${RESET}"
}

# ── Section header ──
section() {
    echo ""
    hr
    echo -e "${BOLD}${CYAN}  $*${RESET}"
    hr
    echo ""
}

# ── Pause for user to read ──
pause() {
    echo ""
    echo -en "${DIM}Press Enter to continue...${RESET}"
    read -r
}

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  demo-common.sh — Shared framework for interactive demos
# ──────────────────────────────────────────────────────────────
[[ -n "${_DEMO_COMMON_LOADED:-}" ]] && return 0
_DEMO_COMMON_LOADED=1

# ── Source project modules ──
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$DEMO_DIR/.." && pwd)"

source "$PROJECT_DIR/scripts/config.sh"
source "$PROJECT_DIR/scripts/ssh-utils.sh"
source "$PROJECT_DIR/scripts/vm-manager.sh"

# ── Step counter ──
STEP_COUNT=0

# ──────────────────────────────────────────────────────────────
#  demo_header <title> <description>
#  Opening banner for the demo
# ──────────────────────────────────────────────────────────────
demo_header() {
    local title="$1"
    local description="$2"

    clear
    echo ""
    echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}  ║  GUIDED DEMO: ${title}$(printf '%*s' $(( 38 - ${#title} )) '')║${RESET}"
    echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${description}"
    echo ""
    hr
    echo -e "  ${DIM}Controls:  [Enter] run  |  [s] skip  |  [q] quit${RESET}"
    hr
    echo ""
    STEP_COUNT=0
}

# ──────────────────────────────────────────────────────────────
#  demo_note <text>
#  Educational note box (yellow)
# ──────────────────────────────────────────────────────────────
demo_note() {
    local text="$1"
    echo ""
    echo -e "  ${YELLOW}┌─ Note ──────────────────────────────────────────────┐${RESET}"
    while IFS= read -r line; do
        echo -e "  ${YELLOW}│${RESET} ${line}"
    done <<< "$text"
    echo -e "  ${YELLOW}└────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# ──────────────────────────────────────────────────────────────
#  demo_verify <command> <pattern> <description>
#  Run and verify (no confirmation, for intermediate checks)
# ──────────────────────────────────────────────────────────────
demo_verify() {
    local cmd="$1"
    local pattern="$2"
    local desc="$3"

    local output
    output=$(ssh_exec "$cmd" 2>&1) || true

    if echo "$output" | grep -qE "$pattern"; then
        echo -e "  ${GREEN}✓${RESET} ${desc}"
    else
        echo -e "  ${RED}✗${RESET} ${desc}"
        echo -e "    ${DIM}Output: ${output}${RESET}"
    fi
}

# ──────────────────────────────────────────────────────────────
#  demo_ensure_vm
#  Verify VM is running + SSH reachable, otherwise clear error
# ──────────────────────────────────────────────────────────────
demo_ensure_vm() {
    if ! vm_is_running; then
        echo ""
        error "VM is not running."
        echo -e "  ${CYAN}Start it from the main menu: VM Management > Start VM${RESET}"
        echo -e "  ${CYAN}Or run: Setup & Installation${RESET}"
        echo ""
        pause
        return 1
    fi
    if ! ssh_check; then
        echo ""
        error "VM is running but SSH is not reachable."
        echo -e "  ${CYAN}Wait a few seconds and try again.${RESET}"
        echo ""
        pause
        return 1
    fi
    return 0
}

# ──────────────────────────────────────────────────────────────
#  demo_cleanup_start
#  Clean environment (cleanup RAID + LVM)
# ──────────────────────────────────────────────────────────────
demo_cleanup_start() {
    echo -e "  ${DIM}Cleaning up environment...${RESET}"

    # Unmount everything
    ssh_exec "sudo umount /mnt/raid* 2>/dev/null || true" 2>/dev/null || true
    ssh_exec "sudo umount /mnt/lvm-data /mnt/raid-lvm 2>/dev/null || true" 2>/dev/null || true

    # Remove LVM
    local lvs_out
    lvs_out=$(ssh_exec "sudo lvs --noheadings -o lv_name,vg_name 2>/dev/null || true" 2>/dev/null || true)
    if [[ -n "$lvs_out" ]]; then
        while IFS= read -r line; do
            local lv vg
            lv=$(echo "$line" | awk '{print $1}')
            vg=$(echo "$line" | awk '{print $2}')
            [[ -z "$lv" || -z "$vg" ]] && continue
            ssh_exec "sudo lvremove -f /dev/${vg}/${lv} 2>/dev/null || true" 2>/dev/null || true
        done <<< "$lvs_out"
    fi

    local vgs_out
    vgs_out=$(ssh_exec "sudo vgs --noheadings -o vg_name 2>/dev/null || true" 2>/dev/null || true)
    if [[ -n "$vgs_out" ]]; then
        while IFS= read -r line; do
            local vg
            vg=$(echo "$line" | awk '{print $1}')
            [[ -z "$vg" ]] && continue
            ssh_exec "sudo vgremove -f ${vg} 2>/dev/null || true" 2>/dev/null || true
        done <<< "$vgs_out"
    fi

    ssh_exec "sudo pvremove -f /dev/md0 /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null || true" 2>/dev/null || true

    # Stop all RAID arrays
    local md_devs
    md_devs=$(ssh_exec "ls /dev/md[0-9]* 2>/dev/null || true" 2>/dev/null | tr '\n' ' ')
    for md in $md_devs; do
        [[ -z "$md" ]] && continue
        ssh_exec "sudo mdadm --stop $md 2>/dev/null || true" 2>/dev/null || true
    done

    # Zero superblocks
    ssh_exec "sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null || true" 2>/dev/null || true

    echo -e "  ${GREEN}✓${RESET} Environment clean"
    echo ""
}

# ──────────────────────────────────────────────────────────────
#  tutor_step <step_number> <title> <command> <explanation> [expected_pattern]
#  Core interactive step function
# ──────────────────────────────────────────────────────────────
tutor_step() {
    local step_num="$1"
    local title="$2"
    local cmd="$3"
    local explanation="$4"
    local expected_pattern="${5:-}"

    # Step header
    echo ""
    echo -e "${BOLD}${CYAN}  ═══ Step ${step_num}: ${title} ═══${RESET}"
    echo ""

    # Multi-line explanation
    while IFS= read -r line; do
        echo -e "  ${CYAN}${line}${RESET}"
    done <<< "$explanation"
    echo ""

    # Show command
    echo -e "  ${DIM}\$${RESET} ${BOLD}${cmd}${RESET}"
    echo ""

    # Interactive prompt
    echo -en "  ${YELLOW}[Enter] run  |  [s] skip  |  [q] quit ▸ ${RESET}"
    read -r reply

    case "$reply" in
        s|S)
            echo -e "  ${DIM}-- skipped --${RESET}"
            return 0
            ;;
        q|Q)
            echo ""
            info "Demo stopped by user."
            return 1
            ;;
    esac

    # Execute command
    hr
    local output
    output=$(ssh_exec "$cmd" 2>&1) || true
    echo "$output"
    hr

    # Verify pattern if provided
    if [[ -n "$expected_pattern" ]]; then
        echo ""
        if echo "$output" | grep -qE "$expected_pattern"; then
            echo -e "  ${GREEN}✓ Expected result found${RESET}"
        else
            echo -e "  ${RED}✗ Expected pattern not found: ${expected_pattern}${RESET}"
        fi
    fi

    # Brief pause to read
    sleep 0.5
    return 0
}

# ──────────────────────────────────────────────────────────────
#  _next_step
#  Increment and return the next step number
# ──────────────────────────────────────────────────────────────
_next_step() {
    STEP_COUNT=$(( STEP_COUNT + 1 ))
}

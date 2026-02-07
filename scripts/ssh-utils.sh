#!/usr/bin/env bash
# ssh-utils.sh — SSH connection helpers for guest interaction

# Guard against double-sourcing
[[ -n "${_SSH_UTILS_LOADED:-}" ]] && return 0
_SSH_UTILS_LOADED=1

# ── Source config if not already loaded ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"

# ── SSH command base ──
_ssh_cmd() {
    # shellcheck disable=SC2086
    sshpass -p "$VM_PASS" ssh $SSH_OPTS -p "$VM_SSH_PORT" "${VM_USER}@localhost" "$@"
}

# ── Check SSH connectivity (quick test) ──
ssh_check() {
    _ssh_cmd "echo ok" &>/dev/null
}

# ── Wait for SSH to become available ──
ssh_wait() {
    local timeout="${1:-120}"
    local elapsed=0
    local interval=3

    info "Waiting for SSH on port ${VM_SSH_PORT} (timeout: ${timeout}s)..."

    while (( elapsed < timeout )); do
        if ssh_check; then
            success "SSH connection established."
            return 0
        fi
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
        printf "  ${DIM}%3ds / %ds ...${RESET}\r" "$elapsed" "$timeout"
    done

    echo ""
    error "SSH connection timed out after ${timeout}s."
    return 1
}

# ── Execute command on guest ──
ssh_exec() {
    local cmd="$1"
    _ssh_cmd "$cmd"
}

# ── Execute command with educational display ──
ssh_exec_show() {
    local cmd="$1"
    local explanation="${2:-}"

    if [[ -n "$explanation" ]]; then
        echo ""
        echo -e "${CYAN}${explanation}${RESET}"
    fi

    echo -e "${DIM}  \$ ${BOLD}${cmd}${RESET}"
    hr
    local output
    if output=$(ssh_exec "$cmd" 2>&1); then
        echo "$output"
    else
        local rc=$?
        echo "$output"
        echo -e "${YELLOW}  (command exited with code ${rc})${RESET}"
    fi
    hr
    echo ""
}

# ── Open interactive SSH session ──
ssh_interactive() {
    info "Opening interactive SSH session (type 'exit' to return)..."
    echo ""
    # shellcheck disable=SC2086
    sshpass -p "$VM_PASS" ssh $SSH_OPTS -p "$VM_SSH_PORT" "${VM_USER}@localhost"
}

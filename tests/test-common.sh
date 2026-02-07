#!/usr/bin/env bash
# test-common.sh — Shared test framework for RAID/LVM labs
#
# Provides:
#   - Non-interactive overrides (pause, confirm)
#   - Assertion functions (assert_ok, assert_fail, assert_contains, assert_not_contains)
#   - Test lifecycle (test_start, test_end, report_results)
#   - Cleanup helpers (cleanup_raid, cleanup_lvm)
#   - VM setup/teardown (setup_vm, teardown_vm)

set -euo pipefail

# ── Resolve paths ──
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"

# ── Source project modules ──
# shellcheck disable=SC1091
source "$PROJECT_DIR/scripts/config.sh"
# shellcheck disable=SC1091
source "$PROJECT_DIR/scripts/ssh-utils.sh"
# shellcheck disable=SC1091
source "$PROJECT_DIR/scripts/vm-manager.sh"
# shellcheck disable=SC1091
source "$PROJECT_DIR/scripts/disk-manager.sh"

# ── Non-interactive overrides ──
pause()   { true; }
confirm() { return 0; }

# ── Parse common flags ──
SKIP_SETUP=false
SKIP_VM_TEARDOWN=false
for arg in "$@"; do
    case "$arg" in
        --skip-setup)       SKIP_SETUP=true ;;
        --skip-vm-teardown) SKIP_VM_TEARDOWN=true ;;
        --debug)            export VM_DEBUG=1 ;;
    esac
done

# ── Test counters ──
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
_CURRENT_TEST=""
_TEST_START_TIME=0

# ── Assertion functions ──

# assert_ok <description>
# Checks that the previous command exited 0.
# Usage: some_command; assert_ok "description"
assert_ok() {
    local rc=${PIPESTATUS[0]:-$?}
    local desc="$1"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if [[ "$rc" -eq 0 ]]; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        echo -e "  ${GREEN}PASS${RESET} ${desc}"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        echo -e "  ${RED}FAIL${RESET} ${desc} (exit code: ${rc})"
    fi
}

# assert_fail <description>
# Checks that the previous command exited != 0.
assert_fail() {
    local rc=${PIPESTATUS[0]:-$?}
    local desc="$1"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if [[ "$rc" -ne 0 ]]; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        echo -e "  ${GREEN}PASS${RESET} ${desc}"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        echo -e "  ${RED}FAIL${RESET} ${desc} (expected failure, got exit code 0)"
    fi
}

# assert_contains <output> <pattern> <description>
assert_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if echo "$output" | grep -qE "$pattern"; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        echo -e "  ${GREEN}PASS${RESET} ${desc}"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        echo -e "  ${RED}FAIL${RESET} ${desc} (pattern '${pattern}' not found)"
    fi
}

# assert_not_contains <output> <pattern> <description>
assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local desc="$3"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if ! echo "$output" | grep -qE "$pattern"; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        echo -e "  ${GREEN}PASS${RESET} ${desc}"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        echo -e "  ${RED}FAIL${RESET} ${desc} (pattern '${pattern}' unexpectedly found)"
    fi
}

# ── Test lifecycle ──

test_start() {
    _CURRENT_TEST="$1"
    _TEST_START_TIME=$(date +%s)
    echo ""
    echo -e "${BOLD}${CYAN}━━━ TEST: ${_CURRENT_TEST} ━━━${RESET}"
    echo ""
}

test_end() {
    local elapsed=$(( $(date +%s) - _TEST_START_TIME ))
    echo ""
    echo -e "${DIM}  [${_CURRENT_TEST}] completed in ${elapsed}s${RESET}"
    echo ""
}

# ── Cleanup helpers ──

# cleanup_raid — stop all md arrays, zero superblocks on all data disks
cleanup_raid() {
    info "Cleaning up RAID arrays..."
    ssh_exec "sudo umount /mnt/raid* 2>/dev/null || true" 2>/dev/null || true

    # Stop all md devices
    local md_devs
    md_devs=$(ssh_exec "ls /dev/md[0-9]* 2>/dev/null || true" 2>/dev/null | tr '\n' ' ')
    for md in $md_devs; do
        [[ -z "$md" ]] && continue
        ssh_exec "sudo mdadm --stop $md 2>/dev/null || true" 2>/dev/null || true
    done

    # Zero superblocks
    ssh_exec "sudo mdadm --zero-superblock /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null || true" 2>/dev/null || true
    info "RAID cleanup done."
}

# cleanup_lvm — remove all LVs, VGs, PVs
cleanup_lvm() {
    info "Cleaning up LVM..."
    ssh_exec "sudo umount /mnt/lvm-data /mnt/raid-lvm 2>/dev/null || true" 2>/dev/null || true

    # Remove LVs
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

    # Remove VGs
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

    # Remove PVs
    ssh_exec "sudo pvremove -f /dev/md0 /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null || true" 2>/dev/null || true
    info "LVM cleanup done."
}

# cleanup_zfs — destroy all ZFS pools, wipefs on data disks
cleanup_zfs() {
    info "Cleaning up ZFS pools..."
    local pools
    pools=$(ssh_exec "sudo zpool list -H -o name 2>/dev/null || true" 2>/dev/null || true)
    if [[ -n "$pools" ]]; then
        while IFS= read -r pool; do
            [[ -z "$pool" ]] && continue
            ssh_exec "sudo zpool destroy -f ${pool} 2>/dev/null || true" 2>/dev/null || true
        done <<< "$pools"
    fi
    ssh_exec "sudo wipefs -a /dev/vdb /dev/vdc /dev/vdd /dev/vde 2>/dev/null || true" 2>/dev/null || true
    info "ZFS cleanup done."
}

# ── VM setup / teardown ──

setup_vm() {
    if [[ "$SKIP_SETUP" == "true" ]]; then
        info "Skipping VM setup (--skip-setup)."
        # Just verify SSH is reachable
        if ! ssh_check; then
            error "VM is not reachable via SSH. Start the VM first or remove --skip-setup."
            return 1
        fi
        return 0
    fi

    info "Setting up VM for tests..."

    # Create disks if missing
    disk_download_cloud_image
    disk_create_os
    disk_create_cloud_init
    disk_create_data

    # Start VM
    vm_start
}

teardown_vm() {
    if [[ "$SKIP_VM_TEARDOWN" == "true" ]]; then
        info "Skipping VM teardown (--skip-vm-teardown)."
        return 0
    fi

    info "Tearing down VM..."
    vm_stop || true
}

# ── Results report ──

report_results() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  TEST RESULTS: ${_CURRENT_TEST:-unknown}${RESET}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "  Total:  ${TESTS_TOTAL}"
    echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${RESET}"
    echo -e "  ${RED}Failed: ${TESTS_FAILED}${RESET}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""

    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

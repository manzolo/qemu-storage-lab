#!/usr/bin/env bash
# run-all-tests.sh — Runner: executes all RAID/LVM tests and reports results
#
# Usage:
#   ./tests/run-all-tests.sh                  # Full run (setup VM, run tests, teardown)
#   ./tests/run-all-tests.sh --skip-setup     # Skip VM setup (VM already running)
#   ./tests/run-all-tests.sh --skip-vm-teardown  # Don't stop VM after tests

set -euo pipefail

# ── Resolve paths ──
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"

# ── Source project config for colors and utilities ──
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

# ── Parse flags ──
SKIP_SETUP=false
SKIP_VM_TEARDOWN=false
for arg in "$@"; do
    case "$arg" in
        --skip-setup)       SKIP_SETUP=true ;;
        --skip-vm-teardown) SKIP_VM_TEARDOWN=true ;;
        --debug)            export VM_DEBUG=1 ;;
    esac
done

# ── List of tests ──
TESTS=(
    "test-raid0.sh"
    "test-raid1.sh"
    "test-raid5.sh"
    "test-raid10.sh"
    "test-lvm-basic.sh"
    "test-lvm-raid.sh"
    "test-zfs-pool.sh"
    "test-zfs-mirror.sh"
)

# ── Results tracking ──
declare -A TEST_RESULTS
TOTAL_PASS=0
TOTAL_FAIL=0

# ── VM Setup ──
if [[ "$SKIP_SETUP" != "true" ]]; then
    section "Setting up VM for test suite"

    disk_download_cloud_image
    disk_create_os
    disk_create_cloud_init
    disk_create_data

    vm_start
else
    info "Skipping VM setup (--skip-setup)."
    if ! ssh_check; then
        error "VM is not reachable via SSH. Start the VM first or remove --skip-setup."
        exit 1
    fi
fi

# ── Run tests ──
section "Running test suite"

for test_file in "${TESTS[@]}"; do
    test_path="$TEST_DIR/$test_file"

    if [[ ! -f "$test_path" ]]; then
        warn "Test file not found: $test_file — skipping."
        TEST_RESULTS["$test_file"]="SKIP"
        continue
    fi

    echo ""
    echo -e "${BOLD}${BLUE}▶ Running: ${test_file}${RESET}"
    hr

    if bash "$test_path" --skip-setup; then
        TEST_RESULTS["$test_file"]="PASS"
        TOTAL_PASS=$(( TOTAL_PASS + 1 ))
    else
        TEST_RESULTS["$test_file"]="FAIL"
        TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
    fi
done

# ── VM Teardown ──
if [[ "$SKIP_VM_TEARDOWN" != "true" ]]; then
    section "Tearing down VM"
    vm_stop || true
else
    info "Skipping VM teardown (--skip-vm-teardown)."
fi

# ── Final report ──
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║              TEST SUITE RESULTS                     ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
printf "${BOLD}  %-25s %-10s${RESET}\n" "TEST" "RESULT"
hr

for test_file in "${TESTS[@]}"; do
    result="${TEST_RESULTS[$test_file]:-SKIP}"
    case "$result" in
        PASS) color="$GREEN" ;;
        FAIL) color="$RED"   ;;
        *)    color="$YELLOW" ;;
    esac
    printf "  %-25s ${color}%-10s${RESET}\n" "$test_file" "$result"
done

hr
echo ""
echo -e "  ${GREEN}Passed: ${TOTAL_PASS}${RESET}  |  ${RED}Failed: ${TOTAL_FAIL}${RESET}  |  Total: $(( TOTAL_PASS + TOTAL_FAIL ))"
echo ""

if [[ "$TOTAL_FAIL" -gt 0 ]]; then
    echo -e "${RED}${BOLD}  SOME TESTS FAILED${RESET}"
    exit 1
else
    echo -e "${GREEN}${BOLD}  ALL TESTS PASSED${RESET}"
    exit 0
fi

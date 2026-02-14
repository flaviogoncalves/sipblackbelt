#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenSIPS 3.6 Installation — Asciinema Recording
# ============================================================
# Usage:  sudo bash opensips_install_demo.sh
# Output: opensips_install_demo.cast
#
# Records a REAL OpenSIPS 3.6 installation on Debian 12
# including MariaDB database setup.
# Each step clears the screen for a clean presentation.

export DEBIAN_FRONTEND=noninteractive

CAST_FILE="${CAST_FILE:-opensips_install_demo.cast}"
TYPING_DELAY="${TYPING_DELAY:-0.04}"
LINE_PAUSE="${LINE_PAUSE:-1.0}"
POST_CMD_PAUSE="${POST_CMD_PAUSE:-2.0}"
SECTION_PAUSE="${SECTION_PAUSE:-3.0}"
COMMENT_PAUSE="${COMMENT_PAUSE:-2.5}"

C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_WHITE='\033[1;37m'
C_RESET='\033[0m'

# Speed markers for post-processing acceleration
FAST_START_MARKER=$'\033]9999;FAST_START\033\\'
FAST_END_MARKER=$'\033]9999;FAST_END\033\\'
mark_fast_start() { printf '%s' "$FAST_START_MARKER"; }
mark_fast_end()   { printf '%s' "$FAST_END_MARKER"; }

# ── Helpers ────────────────────────────────────────────────

type_text() {
    local text="$1"
    for (( i=0; i<${#text}; i++ )); do
        printf '%s' "${text:$i:1}"
        sleep "$TYPING_DELAY"
    done
}

run_cmd() {
    local cmd="$1"
    printf "${C_GREEN}root@opensips-lab${C_RESET}:${C_CYAN}~${C_RESET}# "
    type_text "$cmd"
    sleep "$LINE_PAUSE"
    printf '\n'
    eval "$cmd"
    local rc=$?
    sleep "$POST_CMD_PAUSE"
    return $rc
}

run_cmd_fast() {
    local cmd="$1"
    printf "${C_GREEN}root@opensips-lab${C_RESET}:${C_CYAN}~${C_RESET}# "
    type_text "$cmd"
    sleep "$LINE_PAUSE"
    printf '\n'
    mark_fast_start
    eval "$cmd"
    local rc=$?
    mark_fast_end
    sleep "$POST_CMD_PAUSE"
    return $rc
}

show_comment() {
    local text="$1"
    printf "${C_GREEN}root@opensips-lab${C_RESET}:${C_CYAN}~${C_RESET}# "
    type_text "# $text"
    printf '\n'
    sleep "$COMMENT_PAUSE"
}

show_banner() {
    local text="$1"
    clear
    printf '\n'
    printf "${C_CYAN}"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf '  %s\n' "$text"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf "${C_RESET}"
    printf '\n'
    sleep "$SECTION_PAUSE"
}

# ── Demo Flow (recorded by asciinema) ─────────────────────

run_demo() {
    clear
    printf "${C_CYAN}"
    cat << 'EOF'

   ___                   ____ ___ ____    _____    __
  / _ \ _ __   ___ _ __ / ___|_ _|  _ \  |___ /   / /_
 | | | | '_ \ / _ \ '_ \\___ \| || |_) |   |_ \  | '_ \
 | |_| | |_) |  __/ | | |___) | ||  __/   ___) | | (_) |
  \___/| .__/ \___|_| |_|____/___|_|     |____(_) \___/
       |_|
           Installation Lab — Debian 12

EOF
    printf "${C_RESET}"
    sleep 3

    # ── Step 1: System Update ──────────────────────────────
    show_banner "STEP 1 — Update & Upgrade the System"

    show_comment "Update package lists and upgrade all packages"
    run_cmd_fast "apt-get update && apt-get upgrade -y"

    # ── Step 2: Prerequisites ──────────────────────────────
    show_banner "STEP 2 — Install Prerequisites"

    show_comment "Install required packages"
    run_cmd_fast "apt-get install -y wget gnupg2 curl software-properties-common"

    # ── Step 3: Add OpenSIPS 3.6 Repositories ─────────────
    show_banner "STEP 3 — Add OpenSIPS 3.6 Repositories"

    show_comment "Download the OpenSIPS GPG key"
    run_cmd "curl https://apt.opensips.org/opensips-org.gpg -o /usr/share/keyrings/opensips-org.gpg"

    show_comment "Add the OpenSIPS 3.6 release repository"
    run_cmd 'echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org bookworm 3.6-releases" > /etc/apt/sources.list.d/opensips.list'

    show_comment "Add the OpenSIPS CLI nightly repository"
    run_cmd 'echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org bookworm cli-nightly" > /etc/apt/sources.list.d/opensips-cli.list'

    show_comment "Update package lists with the new repositories"
    run_cmd_fast "apt-get update"

    # ── Step 4: Install OpenSIPS ───────────────────────────
    show_banner "STEP 4 — Install OpenSIPS"

    show_comment "Install the OpenSIPS SIP proxy server"
    run_cmd_fast "apt install -y opensips"

    # ── Step 5: Install OpenSIPS CLI ───────────────────────
    show_banner "STEP 5 — Install OpenSIPS CLI"

    show_comment "Install the OpenSIPS command-line interface"
    run_cmd_fast "apt install -y opensips-cli"

    # ── Step 6: Install All OpenSIPS Modules ───────────────
    show_banner "STEP 6 — Install All OpenSIPS Modules"

    show_comment "Install every available opensips module"
    run_cmd_fast "apt install -y opensips-* || true"

    # ── Step 7: Enable & Start OpenSIPS ────────────────────
    show_banner "STEP 7 — Enable & Start OpenSIPS"

    show_comment "Enable OpenSIPS to start on boot"
    run_cmd "systemctl enable opensips"

    show_comment "Start the OpenSIPS service"
    run_cmd "systemctl start opensips || true"

    # ── Step 8: Verify the Installation ────────────────────
    show_banner "STEP 8 — Verify the Installation"

    show_comment "Check OpenSIPS version"
    run_cmd "opensips -V | head -5"

    show_comment "Check OpenSIPS service status"
    run_cmd "systemctl status opensips --no-pager || true"

    show_comment "Verify OpenSIPS is listening on SIP port 5060"
    run_cmd "ss -tulnp | grep opensips || true"

    # ── Step 9: Service Control Verification ───────────────
    show_banner "STEP 9 — Service Control: Stop & Start"

    show_comment "Stop the OpenSIPS service"
    run_cmd "systemctl stop opensips"

    show_comment "Verify OpenSIPS is stopped"
    run_cmd "systemctl status opensips --no-pager || true"

    show_comment "Start the OpenSIPS service again"
    run_cmd "systemctl start opensips || true"

    show_comment "Verify OpenSIPS is running again"
    run_cmd "systemctl status opensips --no-pager || true"

    # ── Step 10: Install MariaDB ───────────────────────────
    show_banner "STEP 10 — Install MySQL Server (MariaDB)"

    show_comment "OpenSIPS uses a database for subscribers, routes, dialplan, etc."
    show_comment "Install MariaDB (MySQL-compatible) database server"
    run_cmd_fast "apt install -y mariadb-server"

    show_comment "Verify MariaDB is running"
    run_cmd "systemctl status mariadb --no-pager || true"

    # ── Step 11: Create OpenSIPS Database ──────────────────
    show_banner "STEP 11 — Create the OpenSIPS Database"

    show_comment "Use opensips-cli to create the opensips database"
    show_comment "When prompted for db_url, use: mysql://localhost"
    run_cmd "opensips-cli -x database create opensips"

    # ── Step 12: Verify Database Tables ────────────────────
    show_banner "STEP 12 — Verify Database Tables"

    show_comment "Check that all OpenSIPS tables were created"
    run_cmd "mysql opensips -e 'show tables'"

    # ── Evidence Submission ────────────────────────────────
    show_banner "📋 Evidence Submission"

    show_comment "Final service status for evidence submission"
    run_cmd "systemctl status opensips --no-pager || true"

    # ── Summary ────────────────────────────────────────────
    clear
    printf '\n'
    printf "${C_GREEN}"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf '  ✅  OpenSIPS 3.6 Installation Complete!\n'
    printf '%*s\n' 70 '' | tr ' ' '='
    printf "${C_RESET}"
    printf '\n'
    printf "${C_WHITE}  Installed components:${C_RESET}\n"
    printf "    • OpenSIPS 3.6 SIP proxy server\n"
    printf "    • OpenSIPS CLI management tool\n"
    printf "    • All available OpenSIPS modules\n"
    printf "    • MariaDB database server\n"
    printf "    • OpenSIPS database with all tables\n"
    printf '\n'
    printf "${C_WHITE}  Repository commands used:${C_RESET}\n"
    printf "    curl https://apt.opensips.org/opensips-org.gpg -o /usr/share/keyrings/opensips-org.gpg\n"
    printf "    deb [signed-by=...] https://apt.opensips.org bookworm 3.6-releases\n"
    printf "    deb [signed-by=...] https://apt.opensips.org bookworm cli-nightly\n"
    printf '\n'
    printf "${C_WHITE}  Database:${C_RESET}\n"
    printf "    Server:   MariaDB on 127.0.0.1 (no external access)\n"
    printf "    Database: opensips\n"
    printf "    Created:  opensips-cli -x database create opensips\n"
    printf '\n'
    printf "${C_WHITE}  Evidence submission:${C_RESET}\n"
    printf "    Run: ${C_YELLOW}systemctl status opensips${C_RESET}\n"
    printf "    Copy the output and submit it in the lab portal.\n"
    printf '\n'
    printf "${C_WHITE}  Next steps:${C_RESET}\n"
    printf "    • Configure /etc/opensips/opensips.cfg\n"
    printf "    • Configure NAT traversal modules\n"
    printf "    • Register SIP endpoints and test calls\n"
    printf '\n'
    sleep 5
}

# ── Main ───────────────────────────────────────────────────

main() {
    [[ $EUID -ne 0 ]] && echo "ERROR: Run as root (sudo bash $0)." && exit 1

    # Install asciinema if missing
    if ! command -v asciinema &>/dev/null; then
        echo "Installing asciinema..."
        apt-get update -y && apt-get install -y asciinema
    fi

    rm -f "$CAST_FILE"
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

    clear
    echo "============================================"
    echo "  Recording OpenSIPS 3.6 installation demo"
    echo "  Output: ${CAST_FILE}"
    echo "============================================"
    echo ""
    sleep 2

    asciinema rec \
        --title "OpenSIPS 3.6 Installation — Debian 12" \
        --cols 120 \
        --rows 35 \
        --command "bash '${SCRIPT_PATH}' --run-demo" \
        "$CAST_FILE"

    # Post-process: accelerate verbose sections
    clear
    SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
    if [[ -f "${SCRIPT_DIR}/cast_accelerate.py" ]]; then
        echo "Post-processing: accelerating verbose output..."
        python3 "${SCRIPT_DIR}/cast_accelerate.py" \
            "$CAST_FILE" "${CAST_FILE%.cast}_final.cast"
        mv "${CAST_FILE%.cast}_final.cast" "$CAST_FILE"
        echo ""
    fi

    echo "============================================"
    echo "  ✅ Recording saved: ${CAST_FILE}"
    echo "  ▶  Play:  asciinema play ${CAST_FILE}"
    echo "  ⬆  Share: asciinema upload ${CAST_FILE}"
    echo "============================================"
}

# ── Dispatch ───────────────────────────────────────────────

if [[ "${1:-}" == "--run-demo" ]]; then
    run_demo
else
    main "$@"
fi
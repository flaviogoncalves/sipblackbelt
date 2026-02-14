#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenSIPS Script Generation Lab — Asciinema Recording
# ============================================================
# Usage:  sudo bash opensips_script_demo.sh
# Output: opensips_script_demo.cast
#
# Records the full lab: osipsconfig, rtpproxy, users.
# Assumes OpenSIPS 3.6 + MariaDB + OCP are already installed.

export DEBIAN_FRONTEND=noninteractive

CAST_FILE="${CAST_FILE:-opensips_script_demo.cast}"
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

# ── Demo Flow ──────────────────────────────────────────────

run_demo() {
    clear
    printf "${C_CYAN}"
    cat << 'EOF'

   ___                   ____ ___ ____
  / _ \ _ __   ___ _ __ / ___|_ _|  _ \
 | | | | '_ \ / _ \ '_ \\___ \| || |_) |
 | |_| | |_) |  __/ | | |___) | ||  __/
  \___/| .__/ \___|_| |_|____/___|_|
       |_|
   Script Generation & RTPProxy Lab — Debian 12

EOF
    printf "${C_RESET}"
    sleep 3

    # ── Player Controls ────────────────────────────────────
    clear
    printf '\n'
    printf "${C_YELLOW}"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf '  PLAYER CONTROLS\n'
    printf '%*s\n' 70 '' | tr ' ' '='
    printf "${C_RESET}"
    printf '\n'
    printf "${C_WHITE}  You can control this recording:${C_RESET}\n"
    printf '\n'
    printf "    ${C_GREEN}Space${C_RESET}     — Pause / Resume playback\n"
    printf "    ${C_GREEN}.${C_RESET}         — Step frame by frame (while paused)\n"
    printf "    ${C_GREEN}]${C_RESET}         — Speed up (2x, 4x)\n"
    printf "    ${C_GREEN}[${C_RESET}         — Slow down\n"
    printf '\n'
    printf "  ${C_YELLOW}TIP:${C_RESET} Pause the recording at any time to\n"
    printf "     copy and paste commands into your own terminal.\n"
    printf '\n'
    printf "${C_YELLOW}"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf "${C_RESET}"
    printf '\n'
    sleep 6

    # ── Prerequisites Check ────────────────────────────────
    show_banner "PREREQUISITES — Verify Services"

    show_comment "Verify OpenSIPS is running"
    run_cmd "systemctl status opensips --no-pager || true"

    show_comment "Verify MariaDB is running"
    run_cmd "systemctl status mariadb --no-pager || true"

    show_comment "Verify Apache/OCP is running"
    run_cmd "systemctl status apache2 --no-pager || true"

    # ── Step 1: Install dependencies for osipsconfig ───────
    show_banner "STEP 1 — Install Dependencies"

    show_comment "osipsconfig needs m4 (macro processor) and ncurses"
    run_cmd_fast "apt install -y m4 libncurses5-dev"

    # ── Step 2: Backup current config ──────────────────────
    show_banner "STEP 2 — Backup Current OpenSIPS Config"

    show_comment "Save the original opensips.cfg before generating a new one"
    run_cmd "cp /etc/opensips/opensips.cfg /etc/opensips/opensips.cfg.orig"
    run_cmd "ls -la /etc/opensips/opensips.cfg*"

    # ── Step 3: Generate config with osipsconfig ─────────────
    show_banner "STEP 3 — Generate Residential Script with osipsconfig"

    show_comment "We will now run osipsconfig interactively"
    show_comment "Select: USE_NAT, USE_AUTH, USE_DBUSRLOC"
    sleep 2

    printf '\n'
    printf "${C_YELLOW}"
    printf '%*s\n' 70 '' | tr ' ' '-'
    printf "  Navigate in osipsconfig:\n"
    printf "    1. Generate OpenSIPS Script > Residential Script\n"
    printf "    2. Configure Residential Script\n"
    printf "    3. Toggle USE_AUTH, USE_DBUSRLOC, USE_NAT with Space\n"
    printf "    4. Press q to go back\n"
    printf "    5. Generate Residential Script\n"
    printf "    6. Press q repeatedly to exit\n"
    printf '%*s\n' 70 '' | tr ' ' '-'
    printf "${C_RESET}"
    printf '\n'
    sleep 4

    printf "${C_GREEN}root@opensips-lab${C_RESET}:${C_CYAN}~${C_RESET}# "
    type_text "/usr/sbin/osipsconfig"
    sleep "$LINE_PAUSE"
    printf '\n'

    /usr/sbin/osipsconfig

    sleep "$POST_CMD_PAUSE"

    # Find the generated config file
    show_comment "Find the generated config file"
    run_cmd "ls -lt /etc/opensips/opensips_residential_*.cfg | head -1"

    GENERATED_CFG=$(ls -t /etc/opensips/opensips_residential_*.cfg 2>/dev/null | head -1)

    if [[ -z "$GENERATED_CFG" ]]; then
        show_comment "WARNING: No generated config found!"
        show_comment "You may need to run osipsconfig again"
        return 1
    fi

    show_comment "Generated: ${GENERATED_CFG}"

    # ── Step 4: Install the generated config ──────────────
    show_banner "STEP 4 — Install Generated Config"

    show_comment "Copy the generated config as the active opensips.cfg"
    run_cmd "cp \"${GENERATED_CFG}\" /etc/opensips/opensips.cfg"
    run_cmd "chmod 644 /etc/opensips/opensips.cfg"

    show_comment "Review the CUSTOMIZE ME sections"
    run_cmd "grep -n 'CUSTOMIZE ME' /etc/opensips/opensips.cfg || echo 'No CUSTOMIZE ME markers found'"

    show_comment "Update the listen address to all interfaces"
    run_cmd "sed -i 's|^listen=udp:127.0.0.1:5060|listen=udp:0.0.0.0:5060|' /etc/opensips/opensips.cfg"
    run_cmd "sed -i 's|^listen=tcp:127.0.0.1:5060|listen=tcp:0.0.0.0:5060|' /etc/opensips/opensips.cfg"

    show_comment "Update the rtpproxy socket in the database"
    run_cmd "mysql -Dopensips -e \"DELETE FROM rtpproxy WHERE setid=1;\""
    run_cmd "mysql -Dopensips -e \"INSERT INTO rtpproxy (setid, url) VALUES (1, 'udp:127.0.0.1:7899');\""
    run_cmd "mysql -Dopensips -e \"SELECT * FROM rtpproxy;\""

    show_comment "Verify the listen addresses"
    run_cmd "grep -n '^listen=' /etc/opensips/opensips.cfg"

    # ── Step 5: Install RTPProxy ───────────────────────────
    show_banner "STEP 5 — Install RTPProxy"

    show_comment "Download rtpproxy 1.2.1 for Debian"
    run_cmd_fast "wget https://archive.debian.org/debian/pool/main/r/rtpproxy/rtpproxy_1.2.1-2.2_amd64.deb"

    show_comment "Add sbin to PATH for dpkg"
    run_cmd "export PATH=\"\$PATH:/sbin:/usr/sbin\""

    show_comment "Install rtpproxy"
    run_cmd_fast "dpkg -i rtpproxy_1.2.1-2.2_amd64.deb || apt install -f -y"

    # ── Step 6: Configure RTPProxy ─────────────────────────
    show_banner "STEP 6 — Configure RTPProxy"

    show_comment "Edit /etc/default/rtpproxy"
    show_comment "Set control socket to udp:127.0.0.1:7899"
    show_comment "Set listen address to 0.0.0.0 (all interfaces)"

    printf "${C_GREEN}root@opensips-lab${C_RESET}:${C_CYAN}~${C_RESET}# "
    type_text "cat > /etc/default/rtpproxy << 'EOF'"
    sleep "$LINE_PAUSE"
    printf '\n'

    cat > /etc/default/rtpproxy << 'RTPCONF'
# RTPProxy configuration
CONTROL_SOCK=udp:127.0.0.1:7899
EXTRA_OPTS="-l 0.0.0.0"
RTPCONF
    sleep "$POST_CMD_PAUSE"

    show_comment "Verify the configuration"
    run_cmd "cat /etc/default/rtpproxy"

    show_comment "Restart rtpproxy with the new configuration"
    run_cmd "systemctl stop rtpproxy"
    run_cmd "systemctl start rtpproxy"

    show_comment "Verify rtpproxy is running"
    run_cmd "systemctl status rtpproxy --no-pager || true"

    # ── Step 7: Verify RTPPROXY in Control Panel ─────────────
    show_banner "STEP 7 — Verify RTPPROXY in Control Panel"

    IP_ADDR=$(hostname -I | awk '{print $1}')
    show_comment "The rtpproxy socket was configured in the database (Step 4)"
    show_comment "You can verify it in the Control Panel:"
    run_cmd "echo \"Open http://${IP_ADDR}/ in your browser\""

    show_comment "Navigate to the RTPPROXY module"
    show_comment "It should show: udp:127.0.0.1:7899"
    sleep 4

    # ── Step 8: Restart OpenSIPS ───────────────────────────
    show_banner "STEP 8 — Restart OpenSIPS"

    show_comment "Validate the configuration file first"
    run_cmd "opensips -C /etc/opensips/opensips.cfg || true"

    show_comment "Restart OpenSIPS with the new config"
    run_cmd "systemctl restart opensips"

    show_comment "Check for errors in the logs"
    run_cmd "journalctl -u opensips --no-pager -n 30 || true"

    show_comment "Verify OpenSIPS is running"
    run_cmd "systemctl status opensips --no-pager || true"

    # ── Step 9: Add SIP Users ──────────────────────────────
    show_banner "STEP 9 — Add SIP Users"

    show_comment "Add user 1000 with password supersecret"
    run_cmd "opensips-cli -x user add 1000 supersecret"

    show_comment "Add user 1001 with password supersecret"
    run_cmd "opensips-cli -x user add 1001 supersecret"

    show_comment "Verify users were created"
    run_cmd "mysql -Dopensips -e 'SELECT username, domain FROM subscriber'"

    # ── Step 10: Set Server IP Address ─────────────────────
    show_banner "STEP 10 — Set Server IP Address"

    IP_ADDR=$(hostname -I | awk '{print $1}')
    show_comment "Replace the listen directive with your server IP"
    show_comment "Server IP detected: ${IP_ADDR}"

    run_cmd "sed -i 's|^listen=udp:0.0.0.0:5060|socket=udp:${IP_ADDR}:5060|' /etc/opensips/opensips.cfg"
    run_cmd "sed -i 's|^listen=tcp:0.0.0.0:5060|socket=tcp:${IP_ADDR}:5060|' /etc/opensips/opensips.cfg"
    run_cmd "sed -i 's|^listen=udp:|socket=udp:|' /etc/opensips/opensips.cfg"
    run_cmd "sed -i 's|^listen=tcp:|socket=tcp:|' /etc/opensips/opensips.cfg"

    show_comment "Verify the socket addresses"
    run_cmd "grep -n '^socket=' /etc/opensips/opensips.cfg"

    # ── Step 11: Switch to Hash Passwords ──────────────────
    show_banner "STEP 11 — Switch to Hash Password Authentication"

    show_comment "Change auth_db to use HA1 hash instead of plaintext"
    show_comment "This is more secure — passwords are stored as MD5 hashes"

    run_cmd "sed -i 's|modparam(\"auth_db\", \"calculate_ha1\", yes)|modparam(\"auth_db\", \"calculate_ha1\", no)|' /etc/opensips/opensips.cfg"
    run_cmd "sed -i 's|modparam(\"auth_db\", \"password_column\", \"password\")|modparam(\"auth_db\", \"password_column\", \"ha1\")|' /etc/opensips/opensips.cfg"

    show_comment "Verify the changes"
    run_cmd "grep -n 'calculate_ha1\|password_column' /etc/opensips/opensips.cfg"

    show_comment "Restart OpenSIPS with the new settings"
    run_cmd "opensips -C /etc/opensips/opensips.cfg || true"
    run_cmd "systemctl restart opensips"
    run_cmd "systemctl status opensips --no-pager || true"

    # ── Evidence Submission ────────────────────────────────
    show_banner "EVIDENCE SUBMISSION"

    show_comment "OpenSIPS service status"
    run_cmd "systemctl status opensips --no-pager || true"

    show_comment "RTPProxy service status"
    run_cmd "systemctl status rtpproxy --no-pager || true"

    show_comment "Generated config in use"
    run_cmd "head -5 /etc/opensips/opensips.cfg"

    show_comment "SIP users registered"
    run_cmd "mysql -Dopensips -e 'SELECT username, domain FROM subscriber'"

    show_comment "Listening ports"
    run_cmd "ss -tulnp | grep -E 'opensips|rtpproxy'"

    # ── Summary ────────────────────────────────────────────
    clear
    printf '\n'
    printf "${C_GREEN}"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf '  OpenSIPS Script Generation Lab — Complete!\n'
    printf '%*s\n' 70 '' | tr ' ' '='
    printf "${C_RESET}"
    printf '\n'
    printf "${C_WHITE}  Completed:${C_RESET}\n"
    printf "    - Generated residential script (USE_NAT, USE_AUTH, USE_DBUSRLOC)\n"
    printf "    - Installed and configured RTPProxy on port 7899\n"
    printf "    - Configured RTPPROXY module in Control Panel\n"
    printf "    - Added SIP users 1000 and 1001\n"
    printf "    - Set server IP address in socket directive\n"
    printf "    - Switched to HA1 hash password authentication\n"
    printf '\n'
    printf "${C_WHITE}  Next steps:${C_RESET}\n"
    printf "    - Register SIP endpoints (softphones) with users 1000/1001\n"
    printf "    - Test SIP calls between the two users\n"
    printf "    - Monitor calls in the Control Panel\n"
    printf '\n'
    sleep 5
}

# ── Main ───────────────────────────────────────────────────

main() {
    [[ $EUID -ne 0 ]] && echo "ERROR: Run as root (sudo bash $0)." && exit 1

    if ! command -v asciinema &>/dev/null; then
        echo "Installing asciinema..."
        apt-get update -y && apt-get install -y asciinema
    fi

    rm -f "$CAST_FILE"
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

    clear
    echo "============================================"
    echo "  Recording OpenSIPS Script Generation Lab"
    echo "  Output: ${CAST_FILE}"
    echo "============================================"
    echo ""
    sleep 2

    asciinema rec \
        --title "OpenSIPS Script Generation & RTPProxy — Debian 12" \
        --cols 120 \
        --rows 35 \
        --command "bash '${SCRIPT_PATH}' --run-demo" \
        "$CAST_FILE"

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
    echo "  Recording saved: ${CAST_FILE}"
    echo "  Play:  asciinema play ${CAST_FILE}"
    echo "  Share: asciinema upload ${CAST_FILE}"
    echo "============================================"
}

# ── Dispatch ───────────────────────────────────────────────

if [[ "${1:-}" == "--run-demo" ]]; then
    run_demo
else
    main "$@"
fi
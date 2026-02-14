#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenSIPS Control Panel 9.3.5 Installation — Asciinema Recording
# ============================================================
# Usage:  sudo bash opensips_cp_demo.sh
# Output: opensips_cp_demo.cast
#
# Records a REAL OpenSIPS CP 9.3.5 installation on Debian 12.
# Assumes OpenSIPS 3.6 + MariaDB are already installed.
# Each step clears the screen for a clean presentation.

export DEBIAN_FRONTEND=noninteractive

CAST_FILE="${CAST_FILE:-opensips_cp_demo.cast}"
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

   ___                   ____ ___ ____     ____ ____
  / _ \ _ __   ___ _ __ / ___|_ _|  _ \  / ___|  _ \
 | | | | '_ \ / _ \ '_ \\___ \| || |_) || |   | |_) |
 | |_| | |_) |  __/ | | |___) | ||  __/ | |___|  __/
  \___/| .__/ \___|_| |_|____/___|_|     \____|_|
       |_|
   Control Panel 9.3.5 — Installation Lab — Debian 12

EOF
    printf "${C_RESET}"
    sleep 3

    # ── Player Controls Notice ─────────────────────────────
    clear
    printf '\n'
    printf "${C_YELLOW}"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf '  ⏯  PLAYER CONTROLS\n'
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
    show_banner "PREREQUISITES — Verify OpenSIPS & MariaDB"

    show_comment "This lab assumes OpenSIPS 3.6 and MariaDB are installed"
    run_cmd "opensips -V | head -3"

    show_comment "Verify OpenSIPS service is active"
    run_cmd "systemctl status opensips --no-pager || true"

    show_comment "Verify MariaDB is running"
    run_cmd "systemctl status mariadb --no-pager || true"

    # ── Step 1: Install Apache and PHP ─────────────────────
    show_banner "STEP 1 — Install Apache and PHP"

    show_comment "Update package list"
    run_cmd_fast "apt update"

    show_comment "Install Apache web server and PHP with required extensions"
    run_cmd_fast "apt install -y apache2 libapache2-mod-php php-curl php php-mysql php-gd php-pear php-cli php-apcu"

    show_comment "Enable required Apache modules"
    run_cmd "a2enmod rewrite"
    run_cmd "a2enmod php8.2"
    run_cmd "a2enmod headers"

    show_comment "Ensure Apache listens on all interfaces (0.0.0.0:80)"
    run_cmd "sed -i 's/^Listen .*/Listen 0.0.0.0:80/' /etc/apache2/ports.conf"
    run_cmd "cat /etc/apache2/ports.conf | grep Listen"

    show_comment "Start and enable Apache"
    run_cmd "systemctl start apache2"
    run_cmd "systemctl enable apache2"

    show_comment "Verify Apache is running"
    run_cmd "systemctl status apache2 --no-pager || true"

    # ── Step 2: Download OpenSIPS Control Panel ────────────
    show_banner "STEP 2 — Download OpenSIPS Control Panel 9.3.5"

    show_comment "Navigate to web directory"
    run_cmd "cd /var/www/html"

    show_comment "Install git if needed"
    run_cmd_fast "apt install -y git"

    show_comment "Clone OpenSIPS Control Panel branch 9.3.5"
    run_cmd_fast "git clone -b 9.3.5 https://github.com/OpenSIPS/opensips-cp.git"

    show_comment "Set proper ownership for Apache"
    run_cmd "chown -R www-data:www-data /var/www/html/opensips-cp/"

    # ── Step 3: Configure Apache Virtual Host ──────────────
    show_banner "STEP 3 — Configure Apache Virtual Host"

    show_comment "Create Apache configuration for OpenSIPS CP"
    run_cmd "cat > /etc/apache2/sites-available/opensips-cp.conf << 'VHOST'
<VirtualHost 0.0.0.0:80>
    DocumentRoot /var/www/html/opensips-cp/web

    <Directory /var/www/html/opensips-cp/web>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride None
        Require all granted

        Header always unset X-Frame-Options
        Header unset X-Frame-Options
        Header always set Access-Control-Allow-Origin \"*\"
    </Directory>
</VirtualHost>
VHOST"

    show_comment "Display the VirtualHost configuration"
    run_cmd "cat /etc/apache2/sites-available/opensips-cp.conf"

    show_comment "Disable default site and enable OpenSIPS CP site"
    run_cmd "a2dissite 000-default || true"
    run_cmd "a2ensite opensips-cp"

    show_comment "Test Apache configuration"
    run_cmd "apache2ctl configtest"

    show_comment "Restart Apache to apply changes"
    run_cmd "systemctl restart apache2"

    # ── Step 4: Verify MySQL Access ─────────────────────────
    show_banner "STEP 4 — Verify MySQL Access"

    show_comment "The opensips user was created by opensips-cli in the previous lab"
    show_comment "Verify it can connect to the opensips database"
    run_cmd "mysql -u opensips -popensipsrw -e 'SELECT \"Connection OK\" AS status'"

    # ── Step 5: Import OCP Database Schema ─────────────────
    show_banner "STEP 5 — Import OCP Database Schema"

    show_comment "Import the OCP tables and admin user into the opensips database"
    show_comment "This creates OCP tables + admin user (admin/opensips)"
    run_cmd "cd /var/www/html/opensips-cp && mysql -Dopensips < config/db_schema.mysql"

    show_comment "Verify the ocp_admin_privileges table was created"
    run_cmd "mysql -Dopensips -e 'SELECT username,first_name,last_name FROM ocp_admin_privileges'"

    show_comment "Verify the ocp_boxes_config table"
    run_cmd "mysql -Dopensips -e 'SELECT * FROM ocp_boxes_config'"

    # ── Step 6: Configure OpenSIPS CP Database Connection ──
    show_banner "STEP 6 — Configure OpenSIPS CP"

    show_comment "Configure CP to use the opensips MySQL user"

    # Write the file directly
    printf "${C_GREEN}root@opensips-lab${C_RESET}:${C_CYAN}~${C_RESET}# "
    type_text "cat > /var/www/html/opensips-cp/config/db.inc.php"
    sleep "$LINE_PAUSE"
    printf '\n'

    cat > /var/www/html/opensips-cp/config/db.inc.php << 'EOF'
<?php
/*
 * Database connection to the OCP / OpenSIPS database
 */
$config->db_driver = "mysql";
$config->db_host   = "localhost";
$config->db_port   = 3306;
$config->db_user   = "opensips";
$config->db_pass   = "opensipsrw";
$config->db_name   = "opensips";
?>
EOF
    sleep "$POST_CMD_PAUSE"

    show_comment "Verify the configuration file"
    run_cmd "cat /var/www/html/opensips-cp/config/db.inc.php"

    # ── Step 7: Set File Permissions ───────────────────────
    show_banner "STEP 7 — Set File Permissions"

    show_comment "Set proper ownership on the entire CP directory"
    run_cmd "chown -R www-data:www-data /var/www/html/opensips-cp/"

    show_comment "Set directory permissions"
    run_cmd "find /var/www/html/opensips-cp/ -type d -exec chmod 755 {} \\;"

    show_comment "Set file permissions"
    run_cmd "find /var/www/html/opensips-cp/ -type f -exec chmod 644 {} \\;"

    # ── Step 8: Install Cron Jobs for Monitoring ───────────
    show_banner "STEP 8 — Install Monitoring Cron Jobs"

    show_comment "Install the stats monitoring cron job"
    run_cmd "cp /var/www/html/opensips-cp/config/tools/system/smonitor/opensips_stats_cron /etc/cron.d/"

    show_comment "Restart cron service"
    run_cmd "systemctl restart cron"

    # ── Step 9: Verify Installation ────────────────────────
    show_banner "STEP 9 — Verify Installation"

    show_comment "Verify Apache is serving the CP"
    run_cmd "systemctl status apache2 --no-pager || true"

    show_comment "Test HTTP response from the Control Panel"
    run_cmd "curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' http://localhost/"

    show_comment "Get the server public IP address"
    run_cmd "hostname -I | awk '{print \$1}'"

    show_comment "OpenSIPS CP is accessible at http://<YOUR_IP>/"
    show_comment "Default login: admin / opensips"

    # ── Evidence Submission ────────────────────────────────
    show_banner "EVIDENCE SUBMISSION"

    show_comment "Apache service status"
    run_cmd "systemctl status apache2 --no-pager || true"

    show_comment "OpenSIPS service status"
    run_cmd "systemctl status opensips --no-pager || true"

    show_comment "Verify CP files are in place"
    run_cmd "ls -la /var/www/html/opensips-cp/web/index.php"

    show_comment "Verify HTTP access to the Control Panel"
    run_cmd "curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' http://localhost/"

    # ── Summary ────────────────────────────────────────────
    clear
    printf '\n'
    printf "${C_GREEN}"
    printf '%*s\n' 70 '' | tr ' ' '='
    printf '  OpenSIPS Control Panel 9.3.5 — Installed!\n'
    printf '%*s\n' 70 '' | tr ' ' '='
    printf "${C_RESET}"
    printf '\n'
    printf "${C_WHITE}  Installed components:${C_RESET}\n"
    printf "    - Apache 2 web server with PHP 8.2\n"
    printf "    - OpenSIPS Control Panel 9.3.5\n"
    printf "    - OCP database tables (db_schema.mysql)\n"
    printf "    - Monitoring cron jobs\n"
    printf '\n'
    printf "${C_WHITE}  Access the Control Panel:${C_RESET}\n"
    printf "    URL:      ${C_YELLOW}http://<YOUR_SERVER_IP>/${C_RESET}\n"
    printf "    Username: ${C_YELLOW}admin${C_RESET}\n"
    printf "    Password: ${C_YELLOW}opensips${C_RESET}\n"
    printf '\n'
    printf "${C_WHITE}  Evidence submission:${C_RESET}\n"
    printf "    - Screenshot of the CP login page\n"
    printf "    - Output of: ${C_YELLOW}systemctl status apache2${C_RESET}\n"
    printf "    - Output of: ${C_YELLOW}curl -s -o /dev/null -w 'HTTP %%{http_code}' http://localhost/${C_RESET}\n"
    printf '\n'
    printf "${C_WHITE}  Next steps:${C_RESET}\n"
    printf "    - Log in and explore the dashboard\n"
    printf "    - Configure OpenSIPS modules via the CP\n"
    printf "    - Set up user provisioning\n"
    printf "    - Configure monitoring and statistics\n"
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
    echo "  Recording OpenSIPS CP 9.3.5 install demo"
    echo "  Output: ${CAST_FILE}"
    echo "============================================"
    echo ""
    sleep 2

    asciinema rec \
        --title "OpenSIPS Control Panel 9.3.5 — Debian 12" \
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
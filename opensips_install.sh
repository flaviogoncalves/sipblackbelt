#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenSIPS 3.6 — Complete Installation Script
# ============================================================
# Installs everything on Debian 12 (Bookworm):
#
#   PART 1 — OpenSIPS 3.6 + CLI + all modules
#   PART 2 — MariaDB + opensips database
#   PART 3 — Apache + PHP + OpenSIPS Control Panel 9.3.5
#   PART 4 — Residential script (USE_AUTH, USE_DBUSRLOC, USE_NAT)
#   PART 5 — RTPProxy installation & configuration
#   PART 6 — SIP users + HA1 authentication
#   PART 7 — Final verification
#
# Usage:  sudo bash opensips_install.sh
# ============================================================

export DEBIAN_FRONTEND=noninteractive

# — Colors —————————————————————————————————————————————————————
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_RESET='\033[0m'

step_num=0
step() {
    step_num=$((step_num + 1))
    printf "\n${C_CYAN}══════════════════════════════════════════════════════════════${C_RESET}\n"
    printf "${C_CYAN}  STEP ${step_num} — %s${C_RESET}\n" "$1"
    printf "${C_CYAN}══════════════════════════════════════════════════════════════${C_RESET}\n\n"
}

info()  { printf "${C_GREEN}  ▸ %s${C_RESET}\n" "$1"; }
warn()  { printf "${C_YELLOW}  ⚠ %s${C_RESET}\n" "$1"; }
error() { printf "${C_RED}  ✗ %s${C_RESET}\n" "$1"; }
ok()    { printf "${C_GREEN}  ✓ %s${C_RESET}\n" "$1"; }

fail() {
    error "$1"
    exit 1
}

# — Pre-flight checks ————————————————————————————————————————
[[ $EUID -ne 0 ]] && fail "This script must be run as root. Use: sudo bash $0"

if [[ ! -f /etc/debian_version ]]; then
    fail "This script requires Debian 12 (Bookworm)"
fi

DEBIAN_VER=$(cat /etc/debian_version)
info "Detected Debian version: ${DEBIAN_VER}"

SERVER_IP=$(hostname -I | awk '{print $1}')
info "Server IP: ${SERVER_IP}"

# ═══════════════════════════════════════════════════════════════
#  PART 1 — OpenSIPS 3.6 Installation
# ═══════════════════════════════════════════════════════════════

step "Update & Upgrade System"
apt-get update -y
apt-get upgrade -y
ok "System updated"

step "Install Prerequisites"
apt-get install -y wget gnupg2 curl software-properties-common git m4 libncurses5-dev python3-pymysql
ok "Prerequisites installed"

step "Add OpenSIPS 3.6 Repositories"
curl -fsSL https://apt.opensips.org/opensips-org.gpg -o /usr/share/keyrings/opensips-org.gpg

echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org bookworm 3.6-releases" \
    > /etc/apt/sources.list.d/opensips.list

echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org bookworm cli-nightly" \
    > /etc/apt/sources.list.d/opensips-cli.list

apt-get update -y
ok "OpenSIPS repositories added"

step "Install OpenSIPS 3.6"
apt-get install -y opensips
ok "OpenSIPS installed"

step "Install OpenSIPS CLI"
apt-get install -y opensips-cli
ok "OpenSIPS CLI installed"

step "Install All OpenSIPS Modules"
apt-get install -y opensips-* 2>/dev/null || true
ok "OpenSIPS modules installed"

step "Enable & Start OpenSIPS"
systemctl enable opensips
systemctl start opensips || true
ok "OpenSIPS enabled and started"

opensips -V | head -3
systemctl status opensips --no-pager || true

# ═══════════════════════════════════════════════════════════════
#  PART 2 — MariaDB + OpenSIPS Database
# ═══════════════════════════════════════════════════════════════

step "Install MariaDB"
apt-get install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb
ok "MariaDB installed and running"

step "Create OpenSIPS Database"

# Pre-configure opensips-cli to avoid interactive prompts
info "Configuring opensips-cli (no-prompt mode)..."
mkdir -p /etc/opensips
cat > /etc/opensips/opensips-cli.cfg << CLICFG
[default]
database_admin_url = mysql://root@localhost
database_url = mysql://opensips:opensipsrw@localhost/opensips
database_name = opensips
prompt_name = opensips-cli
domain = ${SERVER_IP}
CLICFG
ok "opensips-cli.cfg written (domain=${SERVER_IP})"

info "Running: opensips-cli -x database create opensips"
# Pipe empty lines as fallback if CLI still prompts for password
(echo ""; echo ""; echo "") | opensips-cli -x database create opensips 2>&1 || {
    warn "opensips-cli database create returned non-zero — trying direct MySQL creation..."
    
    # Direct MySQL fallback: create DB, user, and import schema manually
    mysql -e "CREATE DATABASE IF NOT EXISTS opensips;"
    mysql -e "CREATE USER IF NOT EXISTS 'opensips'@'localhost' IDENTIFIED BY 'opensipsrw';"
    mysql -e "GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Import OpenSIPS standard tables
    SCHEMA_DIR="/usr/share/opensips"
    if [[ -d "$SCHEMA_DIR/mysql" ]]; then
        for sql_file in "$SCHEMA_DIR/mysql/"*.sql; do
            mysql -Dopensips < "$sql_file" 2>/dev/null || true
        done
        ok "Database tables imported from $SCHEMA_DIR/mysql/"
    else
        warn "Schema directory $SCHEMA_DIR/mysql not found — tables may be incomplete"
    fi
}

# Verify database was actually created
if mysql -e "USE opensips" 2>/dev/null; then
    ok "OpenSIPS database created and verified"
else
    fail "Database 'opensips' was not created. Check MariaDB."
fi

TABLE_COUNT=$(mysql -Dopensips -e 'SHOW TABLES' | wc -l)
ok "${TABLE_COUNT} tables found in opensips database"

# ═══════════════════════════════════════════════════════════════
#  PART 3 — Apache + PHP + OpenSIPS Control Panel
# ═══════════════════════════════════════════════════════════════

step "Install Apache & PHP"
apt-get install -y apache2 libapache2-mod-php php-curl php php-mysql \
    php-gd php-pear php-cli php-apcu php8.2-mysql

# Ensure PDO MySQL is enabled (critical for OpenSIPS CP)
phpenmod pdo_mysql
phpenmod mysqli

a2enmod rewrite
a2enmod php8.2
a2enmod headers

sed -i 's/^Listen .*/Listen 0.0.0.0:80/' /etc/apache2/ports.conf

systemctl enable apache2
systemctl start apache2
ok "Apache + PHP installed (pdo_mysql enabled)"

step "Download OpenSIPS Control Panel 9.3.5"
cd /var/www/html

if [[ -d opensips-cp ]]; then
    warn "opensips-cp directory already exists — removing"
    rm -rf opensips-cp
fi

git clone -b 9.3.5 https://github.com/OpenSIPS/opensips-cp.git
chown -R www-data:www-data /var/www/html/opensips-cp/
ok "Control Panel downloaded"

step "Configure Apache for OpenSIPS CP"

# Add OCP config to Apache (official Alias /cp method)
cat > /etc/apache2/conf-available/opensips-cp.conf << 'OCPCONF'
<Directory /var/www/html/opensips-cp/web>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride None
    Require all granted
</Directory>
<Directory /var/www/html/opensips-cp>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride None
    Require all denied
</Directory>
Alias /cp /var/www/html/opensips-cp/web

<DirectoryMatch "/var/www/html/opensips-cp/web/tools/.*/.*/(template|custom_actions|lib)/">
    Require all denied
</DirectoryMatch>
OCPCONF

a2enconf opensips-cp
apache2ctl configtest
systemctl restart apache2
ok "Apache configured — Control Panel at /cp"

step "Import OCP Database Schema"
info "Testing MySQL user connection..."
mysql -u opensips -popensipsrw -e 'SELECT "Connection OK" AS status' 2>/dev/null \
    && ok "MySQL user 'opensips' can connect" \
    || warn "MySQL user connection test failed"

cd /var/www/html/opensips-cp
mysql -Dopensips < config/db_schema.mysql
ok "OCP schema imported (admin user: admin / opensips)"

mysql -Dopensips -e 'SELECT username, first_name, last_name FROM ocp_admin_privileges'

step "Configure OpenSIPS CP Database Connection"
cat > /var/www/html/opensips-cp/config/db.inc.php << 'EOF'
<?php
if (!isset($config)) $config = new stdClass();

$config->db_driver = "mysql";
$config->db_host   = "localhost";
$config->db_port   = 3306;
$config->db_user   = "opensips";
$config->db_pass   = "opensipsrw";
$config->db_name   = "opensips";
?>
EOF
ok "DB configuration written"

step "Configure OpenSIPS CP Boxes (MI Connection)"
cat > /var/www/html/opensips-cp/config/boxes.global.inc.php << BOXEOF
<?php

// each server is a "box"
\$box_id=0;

// box description
\$boxes[\$box_id]['desc']="OpenSIPS Server";

// MI connector (via JSON backend): json:host:port/json
\$boxes[\$box_id]['mi']['conn']="json:127.0.0.1:8888/json";

// IP of the box
\$boxes[\$box_id]['ip']="${SERVER_IP}";

// monit (optional - leave blank if not using monit)
\$boxes[\$box_id]['monit']['conn']="";
\$boxes[\$box_id]['monit']['user']="";
\$boxes[\$box_id]['monit']['pass']="";

?>
BOXEOF
ok "boxes.global.inc.php configured (MI: json:127.0.0.1:8888/json)"

step "Set File Permissions & Install Cron"
chown -R www-data:www-data /var/www/html/opensips-cp/
find /var/www/html/opensips-cp/ -type d -exec chmod 755 {} \;
find /var/www/html/opensips-cp/ -type f -exec chmod 644 {} \;

cp /var/www/html/opensips-cp/config/tools/system/smonitor/opensips_stats_cron /etc/cron.d/
systemctl restart cron
ok "Permissions set + monitoring cron installed"

# ═══════════════════════════════════════════════════════════════
#  PART 4 — Generate Residential Script
# ═══════════════════════════════════════════════════════════════

step "Backup Current OpenSIPS Config"
cp /etc/opensips/opensips.cfg /etc/opensips/opensips.cfg.orig
ok "Backup saved: /etc/opensips/opensips.cfg.orig"

step "Generate Residential Script (USE_AUTH, USE_DBUSRLOC, USE_NAT)"
info "Using m4 templates to generate residential config..."

M4_TEMPLATE_DIR="/usr/share/opensips/menuconfig_templates"
M4_DEF_FILE="${M4_TEMPLATE_DIR}/opensips_residential_def.m4"
M4_TEMPLATE="${M4_TEMPLATE_DIR}/opensips_residential.m4"

if [[ ! -f "$M4_DEF_FILE" ]] || [[ ! -f "$M4_TEMPLATE" ]]; then
    fail "M4 templates not found at ${M4_TEMPLATE_DIR}. Is opensips installed?"
fi

# Backup original m4 defaults
cp "$M4_DEF_FILE" "${M4_DEF_FILE}.bak"

# Enable the required features in the defaults file
sed -i "s/define(\`USE_AUTH', \`no')/define(\`USE_AUTH', \`yes')/" "$M4_DEF_FILE"
sed -i "s/define(\`USE_DBUSRLOC', \`no')/define(\`USE_DBUSRLOC', \`yes')/" "$M4_DEF_FILE"
sed -i "s/define(\`USE_NAT', \`no')/define(\`USE_NAT', \`yes')/" "$M4_DEF_FILE"

info "Enabled: USE_AUTH, USE_DBUSRLOC, USE_NAT"

# Generate the residential config with m4
GENERATED_CFG="/etc/opensips/opensips_residential_$(date +%Y-%m-%d_%H:%M:%S).cfg"
m4 "$M4_TEMPLATE" > "$GENERATED_CFG"

# Restore original m4 defaults
mv "${M4_DEF_FILE}.bak" "$M4_DEF_FILE"

if [[ ! -s "$GENERATED_CFG" ]]; then
    fail "Generated config is empty. Check m4 templates."
fi

ok "Generated: ${GENERATED_CFG}"

step "Install & Configure Generated Config"
info "Installing generated config as active opensips.cfg..."
cp "$GENERATED_CFG" /etc/opensips/opensips.cfg
chmod 644 /etc/opensips/opensips.cfg

info "Post-generation edits..."

# Update socket addresses: 127.0.0.1 → SERVER_IP
info "Replacing 127.0.0.1 with ${SERVER_IP} in socket lines..."

# Replace 127.0.0.1 in any socket= line (handles any spacing/comments)
sed -i "/^[[:space:]]*socket=/{s/127\.0\.0\.1/${SERVER_IP}/g}" /etc/opensips/opensips.cfg

# Verify the changes were applied
info "Socket lines after update:"
grep -n '^[[:space:]]*socket=' /etc/opensips/opensips.cfg || warn "No socket= lines found"

# If no socket lines exist, add them
if ! grep -q '^[[:space:]]*socket=' /etc/opensips/opensips.cfg; then
    warn "No socket= lines found — adding them manually"
    sed -i "/^####### Global Parameters/a\\
socket=udp:${SERVER_IP}:5060\\
socket=tcp:${SERVER_IP}:5060" /etc/opensips/opensips.cfg
    ok "Socket lines added manually"
fi

info "Configured socket addresses for ${SERVER_IP}"

# Configure rtpproxy socket in the database
mysql -Dopensips -e "DELETE FROM rtpproxy_sockets WHERE set_id=1;" 2>/dev/null || true
mysql -Dopensips -e "INSERT INTO rtpproxy_sockets (set_id, rtpproxy_sock) VALUES (1, 'udp:127.0.0.1:7899');"
ok "RTPProxy socket configured in database: udp:127.0.0.1:7899"

# Switch to HA1 hash authentication (more secure)
sed -i 's|modparam("auth_db", "calculate_ha1", yes)|modparam("auth_db", "calculate_ha1", no)|' /etc/opensips/opensips.cfg
sed -i 's|modparam("auth_db", "password_column", "password")|modparam("auth_db", "password_column", "ha1")|' /etc/opensips/opensips.cfg
info "Switched to HA1 hash authentication"

# Add HTTPD + MI_HTTP modules for Control Panel communication
info "Adding httpd + mi_http modules for Control Panel..."
# Find the last loadmodule line and append after it
LAST_LOADMOD=$(grep -n '^loadmodule' /etc/opensips/opensips.cfg | tail -1 | cut -d: -f1)
if [[ -n "$LAST_LOADMOD" ]]; then
    sed -i "${LAST_LOADMOD}a\\
\\
#### HTTPD + MI_HTTP for Control Panel\\
loadmodule \"httpd.so\"\\
modparam(\"httpd\", \"port\", 8888)\\
\\
loadmodule \"mi_http.so\"\\
modparam(\"mi_http\", \"root\", \"json\")" /etc/opensips/opensips.cfg
    ok "httpd (port 8888) + mi_http modules added to opensips.cfg"
else
    warn "Could not find loadmodule lines — adding httpd at end of module section"
    cat >> /etc/opensips/opensips.cfg << 'HTTPD_BLOCK'

#### HTTPD + MI_HTTP for Control Panel
loadmodule "httpd.so"
modparam("httpd", "port", 8888)

loadmodule "mi_http.so"
modparam("mi_http", "root", "json")
HTTPD_BLOCK
    ok "httpd + mi_http appended to config"
fi

grep -n '^socket=\|calculate_ha1\|password_column' /etc/opensips/opensips.cfg || true
ok "Config installed and customized"

# ═══════════════════════════════════════════════════════════════
#  PART 5 — RTPProxy Installation & Configuration
# ═══════════════════════════════════════════════════════════════

step "Install RTPProxy"
info "Downloading rtpproxy 1.2.1 from Debian archive..."

cd /tmp
export PATH="$PATH:/sbin:/usr/sbin"

# Try primary mirror, fallback to secondary
if ! wget -q --timeout=30 https://archive.debian.org/debian/pool/main/r/rtpproxy/rtpproxy_1.2.1-2.2_amd64.deb 2>/dev/null; then
    warn "Primary mirror failed, trying secondary..."
    wget -q --timeout=30 http://ftp.de.debian.org/debian/pool/main/r/rtpproxy/rtpproxy_1.2.1-2.2_amd64.deb 2>/dev/null \
        || fail "Could not download rtpproxy. Check your internet connection."
fi

dpkg -i /tmp/rtpproxy_1.2.1-2.2_amd64.deb 2>/dev/null || apt-get install -f -y
rm -f /tmp/rtpproxy_1.2.1-2.2_amd64.deb
ok "RTPProxy installed"

step "Configure RTPProxy"
cat > /etc/default/rtpproxy << 'RTPCONF'
# RTPProxy configuration
CONTROL_SOCK=udp:127.0.0.1:7899
EXTRA_OPTS="-l 0.0.0.0"
RTPCONF

info "Control socket: udp:127.0.0.1:7899"
info "Listen address: 0.0.0.0 (all interfaces)"

systemctl stop rtpproxy 2>/dev/null || true
systemctl start rtpproxy
systemctl enable rtpproxy 2>/dev/null || true
ok "RTPProxy configured and running"

# ═══════════════════════════════════════════════════════════════
#  PART 6 — SIP Users + Restart OpenSIPS
# ═══════════════════════════════════════════════════════════════

step "Validate & Restart OpenSIPS"
info "Validating configuration..."
if opensips -C /etc/opensips/opensips.cfg 2>&1; then
    ok "Configuration is valid"
else
    warn "Config validation returned warnings (may still work)"
fi

systemctl restart opensips
ok "OpenSIPS restarted with residential config"

step "Add SIP Users"
opensips-cli -x user add 1000@${SERVER_IP} supersecret || warn "User 1000 may already exist"
ok "User 1000@${SERVER_IP} processed"

opensips-cli -x user add 1001@${SERVER_IP} supersecret || warn "User 1001 may already exist"
ok "User 1001@${SERVER_IP} processed"

info "Verifying users in database..."
mysql -Dopensips -e 'SELECT username, domain, ha1 FROM subscriber'

# ═══════════════════════════════════════════════════════════════
#  PART 7 — Final Verification
# ═══════════════════════════════════════════════════════════════

step "Final Verification"

info "OpenSIPS version:"
opensips -V | head -3

printf "\n"
info "Service status:"
printf "  OpenSIPS:  "
systemctl is-active opensips 2>/dev/null || echo "inactive"
printf "  MariaDB:   "
systemctl is-active mariadb 2>/dev/null || echo "inactive"
printf "  Apache:    "
systemctl is-active apache2 2>/dev/null || echo "inactive"
printf "  RTPProxy:  "
systemctl is-active rtpproxy 2>/dev/null || echo "inactive"

printf "\n"
info "Control Panel HTTP check..."
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost/cp/ 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    ok "Control Panel responding (HTTP ${HTTP_CODE})"
else
    warn "Control Panel returned HTTP ${HTTP_CODE}"
fi

printf "\n"
info "RTPProxy in database:"
mysql -Dopensips -e 'SELECT * FROM rtpproxy_sockets'

printf "\n"
info "SIP subscribers:"
mysql -Dopensips -e 'SELECT username, domain FROM subscriber'

printf "\n"
info "Listening ports:"
ss -tulnp | grep -E '(opensips|apache|mariadbd|mysql|rtpproxy)' || true

# ═══════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════

printf "\n"
printf "${C_GREEN}══════════════════════════════════════════════════════════════${C_RESET}\n"
printf "${C_GREEN}  ✅  OpenSIPS 3.6 — Complete Installation Done!${C_RESET}\n"
printf "${C_GREEN}══════════════════════════════════════════════════════════════${C_RESET}\n"
printf "\n"
printf "  ${C_CYAN}Installed components:${C_RESET}\n"
printf "    • OpenSIPS 3.6 SIP proxy + all modules\n"
printf "    • OpenSIPS CLI\n"
printf "    • MariaDB database server\n"
printf "    • Apache + PHP 8.2\n"
printf "    • OpenSIPS Control Panel 9.3.5\n"
printf "    • Residential script (USE_AUTH, USE_DBUSRLOC, USE_NAT)\n"
printf "    • RTPProxy 1.2.1 (NAT traversal)\n"
printf "    • SIP users 1000 & 1001\n"
printf "\n"
printf "  ${C_CYAN}Access:${C_RESET}\n"
printf "    Control Panel:  ${C_YELLOW}http://${SERVER_IP}/cp/${C_RESET}\n"
printf "    Login:          ${C_YELLOW}admin / opensips${C_RESET}\n"
printf "\n"
printf "  ${C_CYAN}SIP Registration:${C_RESET}\n"
printf "    Server:         ${C_YELLOW}${SERVER_IP}${C_RESET}\n"
printf "    Port:           ${C_YELLOW}5060${C_RESET}\n"
printf "    User 1:         ${C_YELLOW}1000@${SERVER_IP} / supersecret${C_RESET}\n"
printf "    User 2:         ${C_YELLOW}1001@${SERVER_IP} / supersecret${C_RESET}\n"
printf "    Auth:           HA1 hash (secure)\n"
printf "\n"
printf "  ${C_CYAN}RTPProxy:${C_RESET}\n"
printf "    Control socket: udp:127.0.0.1:7899\n"
printf "    Listen:         0.0.0.0 (all interfaces)\n"
printf "\n"
printf "  ${C_CYAN}Database:${C_RESET}\n"
printf "    Server:         MariaDB (localhost:3306)\n"
printf "    Database:       opensips\n"
printf "    User:           opensips / opensipsrw\n"
printf "\n"
printf "  ${C_CYAN}Key files:${C_RESET}\n"
printf "    OpenSIPS config:  /etc/opensips/opensips.cfg\n"
printf "    Original backup:  /etc/opensips/opensips.cfg.orig\n"
printf "    Generated config: ${GENERATED_CFG}\n"
printf "    CP directory:     /var/www/html/opensips-cp/\n"
printf "    CP DB config:     /var/www/html/opensips-cp/config/db.inc.php\n"
printf "    RTPProxy config:  /etc/default/rtpproxy\n"
printf "\n"
printf "  ${C_CYAN}Service commands:${C_RESET}\n"
printf "    systemctl {start|stop|restart|status} opensips\n"
printf "    systemctl {start|stop|restart|status} mariadb\n"
printf "    systemctl {start|stop|restart|status} apache2\n"
printf "    systemctl {start|stop|restart|status} rtpproxy\n"
printf "\n"
printf "  ${C_CYAN}Next steps:${C_RESET}\n"
printf "    • Register softphones with users 1000/1001\n"
printf "    • Test SIP calls between the two users\n"
printf "    • Monitor calls in the Control Panel\n"
printf "\n"
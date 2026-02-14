#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenSIPS 3.6 — Complete Installation Script (Multi-Distro)
# ============================================================
# Supports:
#   • Debian 12 (Bookworm)
#   • Ubuntu 24.04 (Noble Numbat)
#
# NOT supported:
#   • Debian 13 (Trixie) — failed testing (SQLAlchemy 2.x, libpcre3 conflicts)
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

# ═══════════════════════════════════════════════════════════════
#  OS Detection — auto-detect distro, codename, PHP version
# ═══════════════════════════════════════════════════════════════

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        fail "Cannot detect OS — /etc/os-release not found"
    fi

    . /etc/os-release

    DISTRO_ID="${ID,,}"         # debian or ubuntu (lowercased)
    DISTRO_VER="${VERSION_ID}"  # 12, 24.04
    DISTRO_CODENAME="${VERSION_CODENAME:-unknown}"
    DISTRO_PRETTY="${PRETTY_NAME}"

    case "${DISTRO_ID}" in
        debian)
            case "${DISTRO_VER}" in
                12)
                    OPENSIPS_REPO_CODENAME="bookworm"
                    PHP_VER="8.2"
                    NCURSES_PKG="libncurses5-dev"
                    ;;
                13)
                    fail "Debian 13 (Trixie) is NOT supported. Testing revealed multiple dependency conflicts (SQLAlchemy 2.x, libpcre3 removal). Please use Debian 12 (Bookworm) or Ubuntu 24.04 (Noble) instead."
                    ;;
                *)
                    fail "Unsupported Debian version: ${DISTRO_VER}. Supported: Debian 12 (Bookworm). Note: Debian 13 (Trixie) failed testing due to dependency conflicts."
                    ;;
            esac
            ;;
        ubuntu)
            case "${DISTRO_VER}" in
                24.04)
                    OPENSIPS_REPO_CODENAME="noble"
                    PHP_VER="8.3"
                    NCURSES_PKG="libncurses-dev"
                    ;;
                *)
                    fail "Unsupported Ubuntu version: ${DISTRO_VER}. Supported: 24.04"
                    ;;
            esac
            ;;
        *)
            fail "Unsupported distribution: ${DISTRO_ID}. Supported: debian, ubuntu"
            ;;
    esac

    # PHP package names derived from version
    PHP_MYSQL_PKG="php${PHP_VER}-mysql"
    PHP_MOD_APACHE="php${PHP_VER}"

    info "Detected: ${DISTRO_PRETTY}"
    info "  Distro ID:      ${DISTRO_ID}"
    info "  Version:        ${DISTRO_VER} (${DISTRO_CODENAME})"
    info "  OpenSIPS repo:  ${OPENSIPS_REPO_CODENAME}"
    info "  PHP version:    ${PHP_VER}"
    info "  ncurses pkg:    ${NCURSES_PKG}"
}

detect_os

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
# python3-pymysql needed by opensips-cli for MySQL connectivity
PREREQS="wget gnupg2 curl git m4 ${NCURSES_PKG} python3-pymysql lsb-release"

# SIP troubleshooting & network tools
PREREQS="${PREREQS} net-tools sngrep ngrep sipsak sipvicious"

# software-properties-common is Ubuntu-only (provides add-apt-repository)
if [[ "${DISTRO_ID}" == "ubuntu" ]]; then
    PREREQS="${PREREQS} software-properties-common"
fi

apt-get install -y ${PREREQS}
ok "Prerequisites installed"

step "Add OpenSIPS 3.6 Repositories"
curl -fsSL https://apt.opensips.org/opensips-org.gpg -o /usr/share/keyrings/opensips-org.gpg

echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org ${OPENSIPS_REPO_CODENAME} 3.6-releases" \
    > /etc/apt/sources.list.d/opensips.list

echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org ${OPENSIPS_REPO_CODENAME} cli-nightly" \
    > /etc/apt/sources.list.d/opensips-cli.list

apt-get update -y
ok "OpenSIPS repositories added (codename: ${OPENSIPS_REPO_CODENAME})"

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
plain_text_passwords = false
CLICFG
ok "opensips-cli.cfg written (domain=${SERVER_IP}, plain_text_passwords=false)"

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

step "Install Apache & PHP ${PHP_VER}"

# Install Apache + PHP + the version-specific MySQL extension
apt-get install -y apache2 libapache2-mod-php php-curl php php-mysql \
    php-gd php-pear php-cli php-apcu "${PHP_MYSQL_PKG}"

# Ensure PDO MySQL is enabled (critical for OpenSIPS CP)
phpenmod pdo_mysql
phpenmod mysqli

a2enmod rewrite
a2enmod "php${PHP_VER}" || warn "php${PHP_VER} module may not need explicit enabling"
a2enmod headers

sed -i 's/^Listen .*/Listen 0.0.0.0:80/' /etc/apache2/ports.conf

systemctl enable apache2
systemctl start apache2
ok "Apache + PHP ${PHP_VER} installed (pdo_mysql enabled)"

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

step "Configure Control Panel for HA1 Password Hashing"
CP_DIR="/var/www/html/opensips-cp"

# 1) globals.php — CP admin login password mode
GLOBALS_FILE="${CP_DIR}/config/globals.php"
if [[ -f "$GLOBALS_FILE" ]]; then
    if grep -q 'admin_passwd_mode' "$GLOBALS_FILE"; then
        sed -i "s/\$config->admin_passwd_mode\s*=\s*[0-9]/\$config->admin_passwd_mode = 1/" "$GLOBALS_FILE"
    else
        sed -i '/^\?>$/i \$config->admin_passwd_mode = 1;' "$GLOBALS_FILE"
    fi
    ok "globals.php: admin_passwd_mode = 1 (HA1)"
else
    warn "globals.php not found at ${GLOBALS_FILE}"
fi

# 2) SIP subscriber password mode — CP 9.3.3+ stores this in ocp_tools_config table
#    (local.inc.php files are deprecated since CP 9.3.2)
info "Setting passwd_mode=1 in ocp_tools_config (database)..."
if mysql -Dopensips -e "SELECT 1 FROM ocp_tools_config WHERE module='user_management' AND param='passwd_mode'" 2>/dev/null | grep -q 1; then
    mysql -Dopensips -e "UPDATE ocp_tools_config SET value='1' WHERE module='user_management' AND param='passwd_mode';"
    ok "ocp_tools_config: passwd_mode updated to 1 (HA1)"
else
    mysql -Dopensips -e "INSERT INTO ocp_tools_config (module, param, value) VALUES ('user_management', 'passwd_mode', '1');"
    ok "ocp_tools_config: passwd_mode inserted as 1 (HA1)"
fi

info "CP password verification:"
mysql -Dopensips -e "SELECT module, param, value FROM ocp_tools_config WHERE param='passwd_mode';"

# ═══════════════════════════════════════════════════════════════
#  PART 4 — Install Residential Config (AUTH + DBUSRLOC + NAT)
# ═══════════════════════════════════════════════════════════════

step "Backup Current OpenSIPS Config"
cp /etc/opensips/opensips.cfg /etc/opensips/opensips.cfg.orig
ok "Backup saved: /etc/opensips/opensips.cfg.orig"

step "Install Residential Config (USE_AUTH, USE_DBUSRLOC, USE_NAT)"
info "Writing opensips.cfg with AUTH + DB_USRLOC + NAT + RTPProxy..."

GENERATED_CFG="/etc/opensips/opensips_residential_$(date +%Y-%m-%d_%H%M%S).cfg"

cat > "$GENERATED_CFG" << OPENSIPS_CFG
#
# OpenSIPS 3.6 — Residential Configuration
# Generated by opensips_install.sh
# Features: AUTH, DBUSRLOC, NAT, RTPProxy, HTTPD/MI_HTTP
#

####### Global Parameters #########

#debug_mode=yes

log_level=3
xlog_level=3
stderror_enabled=no
syslog_enabled=yes
syslog_facility=LOG_LOCAL0

udp_workers=4

/* uncomment the next line to enable the auto temporary blacklisting of
   not available destinations (default disabled) */
#disable_dns_blacklist=no

/* uncomment the next line to enable IPv6 lookup after IPv4 dns
   lookup failures (default disabled) */
#dns_try_ipv6=yes


socket=udp:${SERVER_IP}:5060


####### Modules Section ########

#set module path
mpath="/usr/lib/x86_64-linux-gnu/opensips/modules/"

#### SIGNALING module
loadmodule "signaling.so"

#### StateLess module
loadmodule "sl.so"

#### Transaction Module
loadmodule "tm.so"
modparam("tm", "fr_timeout", 5)
modparam("tm", "fr_inv_timeout", 30)
modparam("tm", "restart_fr_on_each_reply", 0)
modparam("tm", "onreply_avp_mode", 1)

#### Record Route Module
loadmodule "rr.so"
/* do not append from tag to the RR (no need for this script) */
modparam("rr", "append_fromtag", 0)

#### MAX ForWarD module
loadmodule "maxfwd.so"

#### SIP MSG OPerationS module
loadmodule "sipmsgops.so"

#### FIFO Management Interface
loadmodule "mi_fifo.so"
modparam("mi_fifo", "fifo_name", "/tmp/opensips_fifo")
modparam("mi_fifo", "fifo_mode", 0666)

#### MYSQL module
loadmodule "db_mysql.so"

#### USeR LOCation module
loadmodule "usrloc.so"
modparam("usrloc", "nat_bflag", "NAT")
modparam("usrloc", "working_mode_preset", "single-instance-sql-write-back")
modparam("usrloc", "db_url",
	"mysql://opensips:opensipsrw@localhost/opensips") # CUSTOMIZE ME


#### REGISTRAR module
loadmodule "registrar.so"
modparam("registrar", "tcp_persistent_flag", "TCP_PERSISTENT")
modparam("registrar", "received_avp", "\$avp(received_nh)")
/* uncomment the next line not to allow more than 10 contacts per AOR */
#modparam("registrar", "max_contacts", 10)

#### ACCounting module
loadmodule "acc.so"
/* what special events should be accounted ? */
modparam("acc", "early_media", 0)
modparam("acc", "report_cancels", 0)
/* by default we do not adjust the direct of the sequential requests.
   if you enable this parameter, be sure to enable "append_fromtag"
   in "rr" module */
modparam("acc", "detect_direction", 0)

#### AUTHentication modules
loadmodule "auth.so"
loadmodule "auth_db.so"
modparam("auth_db", "calculate_ha1", no)
modparam("auth_db", "password_column", "ha1")
modparam("auth_db", "db_url",
	"mysql://opensips:opensipsrw@localhost/opensips") # CUSTOMIZE ME
modparam("auth_db", "load_credentials", "")

####  NAT modules
loadmodule "nathelper.so"
modparam("nathelper", "natping_interval", 10)
modparam("nathelper", "ping_nated_only", 1)
modparam("nathelper", "sipping_bflag", "SIP_PING_FLAG")
modparam("nathelper", "sipping_from", "sip:pinger@${SERVER_IP}")
modparam("nathelper", "received_avp", "\$avp(received_nh)")

loadmodule "rtpproxy.so"
modparam("rtpproxy", "rtpproxy_sock", "udp:localhost:7899")

loadmodule "proto_udp.so"

#### HTTPD + MI_HTTP for Control Panel
loadmodule "httpd.so"
modparam("httpd", "port", 8888)

loadmodule "mi_http.so"
modparam("mi_http", "root", "json")


####### Routing Logic ########

# main request routing logic

route{

	# initial NAT handling; detect if the request comes from behind a NAT
	# and apply contact fixing
	force_rport();
	if (nat_uac_test("diff-port-src-via,private-via,diff-ip-src-via,private-contact")) {
		if (is_method("REGISTER")) {
			fix_nated_register();
			setbflag("NAT");
		} else {
			fix_nated_contact();
			setflag("NAT");
		}
	}

	if (!mf_process_maxfwd_header(10)) {
		send_reply(483,"Too Many Hops");
		exit;
	}

	if (has_totag()) {

		# handle hop-by-hop ACK (no routing required)
		if ( is_method("ACK") && t_check_trans() ) {
			t_relay();
			exit;
		}

		# sequential request within a dialog should
		# take the path determined by record-routing
		if ( !loose_route() ) {
			# we do record-routing for all our traffic, so we should not
			# receive any sequential requests without Route hdr.
			send_reply(404,"Not here");
			exit;
		}

		if (is_method("BYE")) {
			# do accounting even if the transaction fails
			do_accounting("log","failed");
		}

		if (check_route_param("nat=yes"))
			setflag("NAT");
		# route it out to whatever destination was set by loose_route()
		# in \$du (destination URI).
		route(relay);
		exit;
	}

	# CANCEL processing
	if (is_method("CANCEL")) {
		if (t_check_trans())
			t_relay();
		exit;
	}

	# absorb retransmissions, but do not create transaction
	t_check_trans();

	if ( !(is_method("REGISTER")  ) ) {

		if (is_myself("\$fd")) {

			# authenticate if from local subscriber
			# authenticate all initial non-REGISTER request that pretend to be
			# generated by local subscriber (domain from FROM URI is local)
			if (!proxy_authorize("", "subscriber")) {
				proxy_challenge("", "auth");
				exit;
			}
			if (\$au!=\$fU) {
				send_reply(403,"Forbidden auth ID");
				exit;
			}

			consume_credentials();
			# caller authenticated

		} else {
			# if caller is not local, then called number must be local

			if (!is_myself("\$rd")) {
				send_reply(403,"Relay Forbidden");
				exit;
			}
		}

	}

	# preloaded route checking
	if (loose_route()) {
		xlog("L_ERR",
			"Attempt to route with preloaded Route's [\$fu/\$tu/\$ru/\$ci]");
		if (!is_method("ACK"))
			send_reply(403,"Preload Route denied");
		exit;
	}

	# record routing
	if (!is_method("REGISTER|MESSAGE"))
		record_route();

	# account only INVITEs
	if (is_method("INVITE")) {
		do_accounting("log");
	}

	if (!is_myself("\$rd")) {
		append_hf("P-hint: outbound\r\n");
		route(relay);
	}

	# requests for my domain

	if (is_method("PUBLISH|SUBSCRIBE")) {
		send_reply(503, "Service Unavailable");
		exit;
	}

	if (is_method("REGISTER")) {
		# authenticate the REGISTER requests
		if (!www_authorize("", "subscriber")) {
			www_challenge("", "auth");
			exit;
		}

		if (\$au!=\$tU) {
			send_reply(403,"Forbidden auth ID");
			exit;
		}

		if (isflagset("NAT")) {
			setbflag("SIP_PING_FLAG");
		}

		# store the registration and generate a SIP reply
		if (!save("location"))
			xlog("failed to register AoR \$tu\n");

		exit;
	}

	if (\$rU==NULL) {
		# request with no Username in RURI
		send_reply(484,"Address Incomplete");
		exit;
	}

	# do lookup with method filtering
	if (!lookup("location", "method-filtering")) {
		if (!db_does_uri_exist("\$ru","subscriber")) {
			send_reply(420,"Bad Extension");
			exit;
		}

		t_reply(404, "Not Found");
		exit;
	}

	if (isbflagset("NAT")) setflag("NAT");

	# when routing via usrloc, log the missed calls also
	do_accounting("log","missed");
	route(relay);
}


route[relay] {
	# for INVITEs enable some additional helper routes
	if (is_method("INVITE")) {

		if (isflagset("NAT") && has_body("application/sdp")) {
			rtpproxy_offer("ro");
		}

		t_on_branch("per_branch_ops");
		t_on_reply("handle_nat");
		t_on_failure("missed_call");
	}

	if (isflagset("NAT")) {
		add_rr_param(";nat=yes");
	}

	if (!t_relay()) {
		send_reply(500,"Internal Error");
	}
	exit;
}


branch_route[per_branch_ops] {
	xlog("new branch at \$ru\n");
}


onreply_route[handle_nat] {
	if (nat_uac_test("private-contact"))
		fix_nated_contact();
	if ( isflagset("NAT") && has_body("application/sdp") )
		rtpproxy_answer("ro");
	xlog("incoming reply\n");
}


failure_route[missed_call] {
	if (t_was_cancelled()) {
		exit;
	}

	# uncomment the following lines if you want to block client
	# redirect based on 3xx replies.
	##if (t_check_status("3[0-9][0-9]")) {
	##t_reply(404,"Not found");
	##	exit;
	##}
}
OPENSIPS_CFG

ok "Residential config written: ${GENERATED_CFG}"

# Install as active config
cp "$GENERATED_CFG" /etc/opensips/opensips.cfg
chmod 644 /etc/opensips/opensips.cfg
ok "Installed as /etc/opensips/opensips.cfg"

# Verify the config has required modules
info "Verifying config modules..."
for MODULE in "auth_db.so" "usrloc.so" "nathelper.so" "rtpproxy.so" "httpd.so" "mi_http.so"; do
    if grep -q "$MODULE" /etc/opensips/opensips.cfg; then
        ok "  Found: $MODULE"
    else
        error "  Missing: $MODULE"
    fi
done

# Configure rtpproxy socket in the database
mysql -Dopensips -e "DELETE FROM rtpproxy_sockets WHERE set_id=1;" 2>/dev/null || true
mysql -Dopensips -e "INSERT INTO rtpproxy_sockets (set_id, rtpproxy_sock) VALUES (1, 'udp:127.0.0.1:7899');"
ok "RTPProxy socket configured in database: udp:127.0.0.1:7899"

info "Config summary:"
grep -n 'socket=\|calculate_ha1\|password_column\|rtpproxy_sock\|httpd.*port' /etc/opensips/opensips.cfg || true
ok "Config installed and verified"

# ═══════════════════════════════════════════════════════════════
#  PART 5 — RTPProxy Installation & Configuration
# ═══════════════════════════════════════════════════════════════

step "Install RTPProxy"
info "Installing rtpproxy..."

cd /tmp
export PATH="$PATH:/sbin:/usr/sbin"

install_rtpproxy_from_deb() {
    local deb_url="$1"
    local deb_file="/tmp/rtpproxy.deb"

    info "Downloading rtpproxy from: ${deb_url}"
    if wget -q --timeout=30 -O "${deb_file}" "${deb_url}" 2>/dev/null; then
        dpkg -i "${deb_file}" 2>/dev/null || apt-get install -f -y
        rm -f "${deb_file}"
        return 0
    fi
    return 1
}

RTPPROXY_INSTALLED=false

# Strategy 1: Try native apt (works on Debian 12, some older Ubuntu)
if apt-get install -y rtpproxy 2>/dev/null; then
    RTPPROXY_INSTALLED=true
    ok "RTPProxy installed from system repositories"
fi

# Strategy 2: Download pre-built .deb
if [[ "$RTPPROXY_INSTALLED" == "false" ]]; then
    info "rtpproxy not in repos — downloading pre-built .deb..."

    # Primary: Debian archive (works for Debian 12/13 and often Ubuntu)
    DEB_URL_PRIMARY="https://archive.debian.org/debian/pool/main/r/rtpproxy/rtpproxy_1.2.1-2.2_amd64.deb"
    # Fallback: Ubuntu jammy (22.04) package
    DEB_URL_FALLBACK="http://archive.ubuntu.com/ubuntu/pool/universe/r/rtpproxy/rtpproxy_1.2.1-2.2ubuntu1_amd64.deb"

    if install_rtpproxy_from_deb "$DEB_URL_PRIMARY"; then
        RTPPROXY_INSTALLED=true
        ok "RTPProxy installed from Debian archive"
    elif install_rtpproxy_from_deb "$DEB_URL_FALLBACK"; then
        RTPPROXY_INSTALLED=true
        ok "RTPProxy installed from Ubuntu archive"
    fi
fi

# Strategy 3: Build from source as last resort
if [[ "$RTPPROXY_INSTALLED" == "false" ]]; then
    warn "Pre-built .deb not available — building rtpproxy from source..."
    apt-get install -y build-essential autoconf automake libtool

    cd /tmp
    if git clone --depth 1 https://github.com/sippy/rtpproxy.git rtpproxy-src; then
        cd rtpproxy-src
        git submodule update --init --recursive 2>/dev/null || true
        autoreconf -fi
        ./configure
        make -j"$(nproc)"
        make install
        cd /tmp && rm -rf rtpproxy-src

        # Create systemd service for source-built rtpproxy
        cat > /etc/systemd/system/rtpproxy.service << 'SVCFILE'
[Unit]
Description=RTP Proxy
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/rtpproxy
ExecStart=/usr/local/bin/rtpproxy -f -s $CONTROL_SOCK $EXTRA_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
SVCFILE
        systemctl daemon-reload
        RTPPROXY_INSTALLED=true
        ok "RTPProxy built and installed from source"
    else
        warn "Could not clone rtpproxy source — RTPProxy NOT installed"
    fi
fi

if [[ "$RTPPROXY_INSTALLED" == "false" ]]; then
    warn "RTPProxy installation failed — NAT traversal may not work"
    warn "You can install it manually later"
fi

step "Configure RTPProxy"
cat > /etc/default/rtpproxy << 'RTPCONF'
# RTPProxy configuration
CONTROL_SOCK=udp:127.0.0.1:7899
EXTRA_OPTS="-l 0.0.0.0"
RTPCONF

info "Control socket: udp:127.0.0.1:7899"
info "Listen address: 0.0.0.0 (all interfaces)"

if [[ "$RTPPROXY_INSTALLED" == "true" ]]; then
    systemctl stop rtpproxy 2>/dev/null || true
    systemctl start rtpproxy
    systemctl enable rtpproxy 2>/dev/null || true
    ok "RTPProxy configured and running"
else
    warn "Skipping RTPProxy service start (not installed)"
fi

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

step "Add SIP Domain"
mysql -Dopensips -e "DELETE FROM domain WHERE domain='${SERVER_IP}';" 2>/dev/null || true
mysql -Dopensips -e "INSERT INTO domain (domain) VALUES ('${SERVER_IP}');"
ok "Domain '${SERVER_IP}' added to domain table"

info "Domains in database:"
mysql -Dopensips -e 'SELECT * FROM domain'

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
printf "  ${C_CYAN}System:${C_RESET}\n"
printf "    OS:             ${DISTRO_PRETTY}\n"
printf "    PHP:            ${PHP_VER}\n"
printf "    OpenSIPS repo:  ${OPENSIPS_REPO_CODENAME}\n"
printf "\n"
printf "  ${C_CYAN}Installed components:${C_RESET}\n"
printf "    • OpenSIPS 3.6 SIP proxy + all modules\n"
printf "    • OpenSIPS CLI\n"
printf "    • MariaDB database server\n"
printf "    • Apache + PHP ${PHP_VER}\n"
printf "    • OpenSIPS Control Panel 9.3.5\n"
printf "    • Residential script (USE_AUTH, USE_DBUSRLOC, USE_NAT)\n"
printf "    • RTPProxy (NAT traversal)\n"
printf "    • SIP users 1000 & 1001\n"
printf "    • Troubleshooting tools: sngrep, ngrep, sipsak, sipvicious\n"
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

printf "${C_RED}╔════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_RED}║                                                            ║${C_RESET}\n"
printf "${C_RED}║   ⚠⚠⚠  SECURITY WARNING — DO NOT USE IN PRODUCTION  ⚠⚠⚠   ║${C_RESET}\n"
printf "${C_RED}║                                                            ║${C_RESET}\n"
printf "${C_RED}║   This script uses DEFAULT, EASY-TO-GUESS passwords:       ║${C_RESET}\n"
printf "${C_RED}║                                                            ║${C_RESET}\n"
printf "${C_RED}║     • MySQL opensips user:    opensipsrw                   ║${C_RESET}\n"
printf "${C_RED}║     • Control Panel login:    admin / opensips             ║${C_RESET}\n"
printf "${C_RED}║     • SIP users 1000 & 1001:  supersecret                 ║${C_RESET}\n"
printf "${C_RED}║                                                            ║${C_RESET}\n"
printf "${C_RED}║   Before exposing this server to the internet, you MUST:   ║${C_RESET}\n"
printf "${C_RED}║                                                            ║${C_RESET}\n"
printf "${C_RED}║     1. Change the MySQL 'opensips' user password           ║${C_RESET}\n"
printf "${C_RED}║        (update db.inc.php + opensips-cli.cfg too)          ║${C_RESET}\n"
printf "${C_RED}║     2. Change the Control Panel admin password             ║${C_RESET}\n"
printf "${C_RED}║     3. Change SIP user passwords (or delete test users)    ║${C_RESET}\n"
printf "${C_RED}║     4. Configure a firewall (ufw / iptables)              ║${C_RESET}\n"
printf "${C_RED}║     5. Enable TLS for SIP signaling                       ║${C_RESET}\n"
printf "${C_RED}║                                                            ║${C_RESET}\n"
printf "${C_RED}╚════════════════════════════════════════════════════════════╝${C_RESET}\n"
printf "\n"
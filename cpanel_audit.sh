
#!/bin/bash
# ======================================================
# cPanel / DirectAdmin / Webuzo Server Audit Script
# Author : Arjun PC
# Safety : READ-ONLY
# Purpose: Infrastructure & Kernel Audit
# ======================================================

OBSERVATIONS=()

add_observation() {
    OBSERVATIONS+=("- $1")
}

section_start() {
    echo
    echo "**$1**"
    echo
    echo "s~~~"
}

section_end() {
    echo "s~~~"
    echo
}

echo "======================================================"
echo "              SERVER AUDIT REPORT"
echo "======================================================"

# ------------------------------------------------------
section_start "Server Details"

echo "Hostname    : $(hostname)"
echo "Uptime      : $(uptime -p)"
echo "OS          : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo "Kernel      : $(uname -r)"

section_end

# ------------------------------------------------------
section_start "Environment Check (envchk)"

bash <(curl -ks https://codesilo.dimenoc.com/codex/envchk/-/raw/master/envchk)

section_end

# ------------------------------------------------------
section_start "Quick Service Check"

bash <(curl -ks https://codesilo.dimenoc.com/giovanni.r/check-services/-/raw/main/check-services.sh)

section_end

# ------------------------------------------------------
section_start "Control Panel Detection"

if [[ -x /usr/local/cpanel/cpanel ]]; then
    echo "Control Panel : cPanel"
    /usr/local/cpanel/cpanel -V

elif [[ -x /usr/local/directadmin/directadmin ]]; then
    echo "Control Panel : DirectAdmin"
    /usr/local/directadmin/directadmin v | head -1

elif command -v webuzo >/dev/null 2>&1; then
    echo "Control Panel : Webuzo"
    webuzo -v

else
    echo "Control Panel : Not detected"
fi

section_end

# ------------------------------------------------------
section_start "CSF Firewall Status"

if systemctl list-unit-files | grep -q csf.service; then
    systemctl status csf --no-pager
else
    echo "csf.service : Not installed"
fi

section_end

# ------------------------------------------------------
section_start "LFD Daemon Status"

if systemctl list-unit-files | grep -q lfd.service; then
    systemctl status lfd --no-pager
else
    echo "lfd.service : Not installed"
fi

section_end

# ------------------------------------------------------
section_start "Drive Health Status"

DRIVE_OUTPUT=$(bash <(curl -ks https://codesilo.dimenoc.com/codex/check-drive-health/-/raw/main/check-drive-health) 2>&1)

echo "$DRIVE_OUTPUT"

if echo "$DRIVE_OUTPUT" | grep -qiE 'critical|failed|unhealthy|degraded|SMART error|health warning'; then
    add_observation "Drive health issue detected. Kindly review the Drive Health Status section."
elif echo "$DRIVE_OUTPUT" | grep -qiE 'healthy|health: passed|drive is healthy'; then
    add_observation "Drive health check completed. No drive issues reported."
else
    add_observation "Drive health check completed. Kindly review the output to confirm drive health."
fi

section_end

# ------------------------------------------------------
section_start "MySQL / MariaDB Service Status"

if systemctl list-unit-files | grep -q mariadb.service; then
    DB_SERVICE="mariadb"
    systemctl status mariadb --no-pager

elif systemctl list-unit-files | grep -q mysqld.service; then
    DB_SERVICE="mysqld"
    systemctl status mysqld --no-pager

else
    DB_SERVICE=""
    echo "MySQL/MariaDB service not found"
fi

if [[ -n "$DB_SERVICE" ]]; then
    if systemctl is-active --quiet "$DB_SERVICE"; then
        add_observation "MySQL/MariaDB service is running."
    else
        add_observation "MySQL/MariaDB service is not active. Kindly investigate."
    fi
else
    add_observation "MySQL/MariaDB service not found."
fi

section_end

# ------------------------------------------------------
section_start "Apache Service Status"

if systemctl list-unit-files | grep -q httpd.service; then
    APACHE_SERVICE="httpd"
    systemctl status httpd --no-pager

elif systemctl list-unit-files | grep -q apache2.service; then
    APACHE_SERVICE="apache2"
    systemctl status apache2 --no-pager

else
    APACHE_SERVICE=""
    echo "Apache service not found"
fi

if [[ -n "$APACHE_SERVICE" ]]; then
    if systemctl is-active --quiet "$APACHE_SERVICE"; then
        add_observation "Apache service is running."
    else
        add_observation "Apache service is not active. Kindly investigate."
    fi
fi

section_end

# ------------------------------------------------------
section_start "Nginx Service Status"

if systemctl list-unit-files | grep -q nginx.service; then
    systemctl status nginx --no-pager

    if systemctl is-active --quiet nginx; then
        add_observation "Nginx service is running."
    else
        add_observation "Nginx service is not active. Kindly investigate."
    fi
else
    echo "nginx.service : Not installed"
fi

section_end

# ------------------------------------------------------
section_start "Exim Mail Queue"

if command -v exim >/dev/null 2>&1; then
    MAIL_QUEUE=$(exim -bpc 2>/dev/null)
    echo "Messages in queue : $MAIL_QUEUE"

    if [[ "$MAIL_QUEUE" =~ ^[0-9]+$ ]]; then
        if (( MAIL_QUEUE == 0 )); then
            add_observation "Exim mail queue is empty."
        else
            add_observation "Exim mail queue contains $MAIL_QUEUE messages. Kindly review the queue."
        fi
    else
        add_observation "Unable to determine Exim mail queue count."
    fi
else
    echo "Exim not installed"
    add_observation "Exim is not installed."
fi

section_end

# ------------------------------------------------------
section_start "Kernel Audit Status (READ-ONLY)"

RUNNING_KERNEL=$(uname -r)

INSTALLED_KERNEL=$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | sort -V | tail -1)

AVAILABLE_KERNEL=$(yum -q list available kernel 2>/dev/null | awk 'NR==2 {print $2}')

echo "Running Kernel   : $RUNNING_KERNEL"
echo "Installed Kernel : $INSTALLED_KERNEL"

if [[ -n "$AVAILABLE_KERNEL" ]]; then
    echo "Available Kernel : $AVAILABLE_KERNEL"
else
    echo "Available Kernel : None"
fi

if [[ "$RUNNING_KERNEL" != "$INSTALLED_KERNEL" ]]; then
    echo "Status           : Reboot required (new kernel already installed)"
    add_observation "New kernel is installed but not running. Server reboot is required to load the installed kernel."

elif [[ -n "$AVAILABLE_KERNEL" ]]; then
    echo "Status           : Kernel update available (NOT installed)"
    add_observation "Kernel update available ($AVAILABLE_KERNEL). Installation pending."

else
    echo "Status           : Fully up to date"
    add_observation "Kernel is up to date."
fi

section_end

# ------------------------------------------------------
section_start "Load Average"

uptime

if command -v sar >/dev/null 2>&1; then
    echo
    echo "Last 10 Load Samples (sar -q):"
    sar -q | tail -10
else
    echo "sar : Not installed"
fi

section_end

# ------------------------------------------------------
section_start "Disk Usage"

df -hT

section_end

# ------------------------------------------------------
section_start "Block Devices (lsblk)"

lsblk

section_end

# ------------------------------------------------------
section_start "Memory Usage"

free -h

if command -v sar >/dev/null 2>&1; then
    echo
    echo "Last 10 Memory Samples (sar -r):"
    sar -r | tail -10
else
    echo "sar : Not installed"
fi

section_end

# ------------------------------------------------------
section_start "CPU Utilization (mpstat)"

if command -v mpstat >/dev/null 2>&1; then
    mpstat 1 3
else
    echo "mpstat : Not installed"
fi

section_end

# ------------------------------------------------------
section_start "Top CPU Processes"

ps aux --sort=-%cpu | head -10

section_end

# ------------------------------------------------------
section_start "Backup Status"

# cPanel backup logs
CPBACKUP_LOG_DIR="/usr/local/cpanel/logs/cpbackup"
BACKUP_FOUND=0

if [[ -d "$CPBACKUP_LOG_DIR" ]]; then
    echo "cPanel Backup Logs:"

    LATEST_LOG=$(ls -1t "$CPBACKUP_LOG_DIR"/*.log 2>/dev/null | head -1)

    if [[ -n "$LATEST_LOG" ]]; then
        BACKUP_FOUND=1

        echo "Latest Log : $(basename "$LATEST_LOG")"

        COMPLETED=$(grep "Completed at" "$LATEST_LOG" | tail -1)
        FINAL_STATE=$(grep "Final state" "$LATEST_LOG" | tail -1)

        [[ -n "$COMPLETED" ]] && echo "$COMPLETED"
        [[ -n "$FINAL_STATE" ]] && echo "$FINAL_STATE"

        if echo "$FINAL_STATE" | grep -qiE 'success|completed'; then
            add_observation "Latest cPanel backup completed successfully."
        elif echo "$FINAL_STATE" | grep -qiE 'fail|error'; then
            add_observation "Latest cPanel backup reported a failure. Kindly investigate."
        else
            add_observation "cPanel backup log found, but the final backup status could not be confirmed."
        fi
    else
        echo "No backup logs found"
    fi
else
    echo "cPanel backup logs : Not present"
fi

echo

# Webuzo backup logs
WEBUZO_BACKUP_LOG="/var/webuzo/logs/admin_auto_backup.log"

if [[ -f "$WEBUZO_BACKUP_LOG" ]]; then
    BACKUP_FOUND=1

    echo "Webuzo Backup Log:"
    echo "Log File : $WEBUZO_BACKUP_LOG"
    tail -20 "$WEBUZO_BACKUP_LOG"

    WEBUZO_LAST_LINE=$(tail -20 "$WEBUZO_BACKUP_LOG")

    if echo "$WEBUZO_LAST_LINE" | grep -qiE 'success|completed'; then
        add_observation "Webuzo backup log contains a success/completion message. Verify the latest backup entry."
    elif echo "$WEBUZO_LAST_LINE" | grep -qiE 'fail|error'; then
        add_observation "Webuzo backup log contains failure/error messages. Kindly investigate."
    else
        add_observation "Webuzo backup log found. Backup completion status requires verification."
    fi
else
    echo "Webuzo backup log : Not present"
fi

echo

# Root backup directory listing
if [[ -d /backup ]]; then
    echo "Backup Root Directory (/backup):"
    ls -lh /backup
    echo
else
    echo "/backup directory not found"
    add_observation "/backup directory not found."
fi

# Backup folders
if [[ -d /backup ]]; then
    echo "Filesystem Backup Directories (/backup):"

    for dir in daily weekly monthly; do
        BACKUP_PATH="/backup/$dir"

        if [[ -d "$BACKUP_PATH" ]]; then
            echo "-- $BACKUP_PATH --"
            ls -lh "$BACKUP_PATH" | head -20
        else
            echo "$BACKUP_PATH : Not found"
        fi

        echo
    done
fi

if (( BACKUP_FOUND == 0 )); then
    add_observation "No cPanel or Webuzo backup log was found. Kindly verify the backup configuration and status."
fi

section_end

# ------------------------------------------------------
# Disk Space Observation (included in final observations)

ROOT_USAGE=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')

if [[ "$ROOT_USAGE" =~ ^[0-9]+$ ]]; then
    if (( ROOT_USAGE >= 90 )); then
        add_observation "Critical disk usage detected on root filesystem (${ROOT_USAGE}%). Immediate investigation recommended."

    elif (( ROOT_USAGE >= 80 )); then
        add_observation "Root filesystem disk usage is high (${ROOT_USAGE}%). Kindly monitor."

    else
        add_observation "Root filesystem disk usage is within the configured threshold (${ROOT_USAGE}%)."
    fi
else
    add_observation "Unable to determine root filesystem disk usage."
fi

# ------------------------------------------------------
echo "======================================================"
echo "          AUDIT COMPLETED (READ-ONLY & SAFE)"
echo "======================================================"

echo
echo '**`Observations`**'
echo

for observation in "${OBSERVATIONS[@]}"; do
    echo "$observation"
done

echo
echo "======================================================"
echo "                END OF AUDIT REPORT"
echo "======================================================"

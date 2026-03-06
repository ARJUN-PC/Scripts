#!/bin/bash
# ======================================================
# cPanel / DirectAdmin / Webuzo Server Audit Script (READ-ONLY)
# Author : Arjun PC
# Safety : NO reboot | NO restart | NO install | NO change
# Purpose: Infrastructure & Kernel Audit
# ======================================================

echo "======================================================"
echo "            Server Audit Report"
echo "======================================================"
echo "Date        : $(date)"
echo

# ------------------------------------------------------
echo "---- Server Details ----"
echo "Hostname    : $(hostname)"
echo "Uptime      : $(uptime -p)"
echo "OS          : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo "Kernel      : $(uname -r)"
echo

# ------------------------------------------------------
echo "---- Environment Check (envchk) ----"
bash <(curl -ks https://codesilo.dimenoc.com/codex/envchk/-/raw/master/envchk)
echo

# ------------------------------------------------------
echo "---- Control Panel Detection ----"
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
echo

# ------------------------------------------------------
echo "---- CSF Firewall Status ----"
if systemctl list-unit-files | grep -q csf.service; then
  systemctl status csf --no-pager
else
  echo "csf.service : Not installed"
fi
echo

# ------------------------------------------------------
echo "---- LFD Daemon Status ----"
if systemctl list-unit-files | grep -q lfd.service; then
  systemctl status lfd --no-pager
else
  echo "lfd.service : Not installed"
fi
echo

# ------------------------------------------------------
echo "---- Drive Health Status ----"
bash <(curl -ks https://codesilo.dimenoc.com/codex/check-drive-health/-/raw/main/check-drive-health)
echo

# ------------------------------------------------------
echo "---- MySQL / MariaDB Service Status ----"
if systemctl list-unit-files | grep -q mariadb.service; then
  systemctl status mariadb --no-pager
elif systemctl list-unit-files | grep -q mysqld.service; then
  systemctl status mysqld --no-pager
else
  echo "MySQL/MariaDB service not found"
fi
echo

# ------------------------------------------------------
echo "---- Apache Service Status ----"
if systemctl list-unit-files | grep -q httpd.service; then
  systemctl status httpd --no-pager
elif systemctl list-unit-files | grep -q apache2.service; then
  systemctl status apache2 --no-pager
else
  echo "Apache service not found"
fi
echo

# ------------------------------------------------------
echo "---- Nginx Service Status ----"
if systemctl list-unit-files | grep -q nginx.service; then
  systemctl status nginx --no-pager
else
  echo "nginx.service : Not installed"
fi
echo

# ------------------------------------------------------
echo "---- Exim Mail Queue ----"
if command -v exim >/dev/null 2>&1; then
  echo "Messages in queue : $(exim -bpc)"
else
  echo "Exim not installed"
fi
echo

# ------------------------------------------------------
echo "---- Kernel Audit Status (READ-ONLY) ----"

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
elif [[ -n "$AVAILABLE_KERNEL" ]]; then
  echo "Status           : Kernel update available (NOT installed)"
else
  echo "Status           : Fully up to date"
fi
echo

# ------------------------------------------------------
echo "---- Load Average ----"
uptime
if command -v sar >/dev/null; then
  echo
  echo "Last 10 Load Samples (sar -q):"
  sar -q | tail -10
else
  echo "sar : Not installed"
fi
echo

# ------------------------------------------------------
echo "---- Disk Usage ----"
df -hT
echo

# ------------------------------------------------------
echo "---- Block Devices (lsblk) ----"
lsblk
echo

# ------------------------------------------------------
echo "---- Memory Usage ----"
free -h
if command -v sar >/dev/null; then
  echo
  echo "Last 10 Memory Samples (sar -r):"
  sar -r | tail -10
else
  echo "sar : Not installed"
fi
echo

# ------------------------------------------------------
echo "---- CPU Utilization (mpstat) ----"
if command -v mpstat >/dev/null; then
  mpstat 1 3
else
  echo "mpstat : Not installed"
fi
echo

# ------------------------------------------------------
echo "---- Top CPU Processes ----"
ps aux --sort=-%cpu | head -10
echo

# ------------------------------------------------------
echo "---- Backup Status ----"

# cPanel backup logs
CPBACKUP_LOG_DIR="/usr/local/cpanel/logs/cpbackup"
if [[ -d "$CPBACKUP_LOG_DIR" ]]; then
  echo "cPanel Backup Logs:"
  LATEST_LOG=$(ls -1t $CPBACKUP_LOG_DIR/*.log 2>/dev/null | head -1)
  if [[ -n "$LATEST_LOG" ]]; then
    echo "Latest Log : $(basename "$LATEST_LOG")"
    grep "Completed at" "$LATEST_LOG"
    grep "Final state" "$LATEST_LOG"
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
  echo "Webuzo Backup Log:"
  echo "Log File : $WEBUZO_BACKUP_LOG"
  tail -20 "$WEBUZO_BACKUP_LOG"
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

echo
echo "======================================================"
echo "        Audit Completed (READ-ONLY & SAFE)"
echo "======================================================"

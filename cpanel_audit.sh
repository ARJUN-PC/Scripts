#!/bin/bash
# ======================================================
# cPanel / DirectAdmin Server Audit Script (READ-ONLY)
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
echo "---- cPanel Version ----"
if [[ -x /usr/local/cpanel/cpanel ]]; then
  /usr/local/cpanel/cpanel -V
else
  echo "cPanel : Not installed"
fi
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
CPBACKUP_LOG_DIR="/usr/local/cpanel/logs/cpbackup"

if [[ -d "$CPBACKUP_LOG_DIR" ]]; then
  LATEST_LOG=$(ls -1t $CPBACKUP_LOG_DIR/*.log 2>/dev/null | head -1)
  if [[ -n "$LATEST_LOG" ]]; then
    echo "Latest Log : $(basename "$LATEST_LOG")"
    grep "Completed at" "$LATEST_LOG"
    grep "Final state" "$LATEST_LOG"
  else
    echo "No backup logs found"
  fi
else
  echo "cPanel backup directory not found"
fi

echo
echo "======================================================"
echo "        Audit Completed (READ-ONLY & SAFE)"
echo "======================================================"

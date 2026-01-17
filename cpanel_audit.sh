#!/bin/bash
# ======================================================
# cPanel Server Audit Script (READ-ONLY)
# Author : Arjun PC
# Safety : NO reboot | NO restart | NO install | NO change
# ======================================================

echo "======================================================"
echo "            cPanel Server Audit Report"
echo "======================================================"
echo "Date        : $(date)"
echo

# ------------------------------------------------------
echo "---- Environment Check (envchk) ----"
bash <(curl -ks https://codesilo.dimenoc.com/codex/envchk/-/raw/master/envchk)
echo

# ------------------------------------------------------
echo "---- Server Details ----"
echo "Hostname    : $(hostname)"
echo "Uptime      : $(uptime -p)"
echo "OS          : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo "Kernel      : $(uname -r)"
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
	/usr/local/cpanel/cpanel -V 2>/dev/null || echo "cPanel : Not installed"
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
	      echo "---- Kernel Update Status (NO ACTION) ----"
	      RUNNING_KERNEL=$(uname -r)
	      LATEST_KERNEL=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)

	      echo "Running Kernel : $RUNNING_KERNEL"
	      echo "Installed     : $LATEST_KERNEL"

	      if [[ "$RUNNING_KERNEL" == "$LATEST_KERNEL" ]]; then
	        echo "Status        : Up-to-date"
		else
		  echo "Status        : Update installed, reboot pending"
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
				      echo "---- cPanel Backup Status (Execution Logs) ----"
				      BACKUP_LOG_DIR="/usr/local/cpanel/logs/cpbackup"

				      if [[ -d "$BACKUP_LOG_DIR" ]]; then
				        LATEST_LOG=$(ls -1t $BACKUP_LOG_DIR/*.log 2>/dev/null | head -1)
					  if [[ -n "$LATEST_LOG" ]]; then
					      echo "Latest Log : $(basename "$LATEST_LOG")"
					          grep "Completed at" "$LATEST_LOG"
						      grep "Final state" "$LATEST_LOG"
						        else
							    echo "No backup logs found"
							      fi
							      else
							        echo "Backup log directory not found"
								fi

								echo
								echo "======================================================"
								echo "        Audit Completed (READ-ONLY & SAFE)"
								echo "======================================================"


#!/bin/bash

# ==========================================================
# cPanel Account Backup Status Checker
# Read-only script - No configuration changes
# Terminal output only - No CSV report
# ==========================================================

USER_DIR="/var/cpanel/users"
DOMAIN_FILE="/etc/trueuserdomains"

# Create temporary files for grouping accounts
TMP_DIR=$(mktemp -d) || {
    echo "ERROR: Unable to create temporary directory."
    exit 1
}

trap 'rm -rf "$TMP_DIR"' EXIT

ENABLED_FILE="$TMP_DIR/enabled"
DISABLED_FILE="$TMP_DIR/disabled"
UNKNOWN_FILE="$TMP_DIR/unknown"

touch "$ENABLED_FILE" "$DISABLED_FILE" "$UNKNOWN_FILE"

# Check root privileges
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Please execute this script as root."
    exit 1
fi

# Check cPanel account directory
if [[ ! -d "$USER_DIR" ]]; then
    echo "ERROR: cPanel user directory not found."
    exit 1
fi

if [[ ! -r "$DOMAIN_FILE" ]]; then
    echo "ERROR: Unable to read $DOMAIN_FILE"
    exit 1
fi

# Process all cPanel accounts
for file in "$USER_DIR"/*; do

    [[ -f "$file" ]] || continue

    USER=$(basename "$file")

    # Get primary domain
    DOMAIN=$(awk -F': ' -v user="$USER" \
        '$2 == user {print $1; exit}' "$DOMAIN_FILE")

    [[ -z "$DOMAIN" ]] && DOMAIN="N/A"

    # Read account backup status
    BACKUP=$(awk -F= '$1 == "BACKUP" {print $2; exit}' "$file")

    case "$BACKUP" in
        1)
            printf '%s\t%s\n' "$USER" "$DOMAIN" >> "$ENABLED_FILE"
            ;;
        0)
            printf '%s\t%s\n' "$USER" "$DOMAIN" >> "$DISABLED_FILE"
            ;;
        *)
            printf '%s\t%s\n' "$USER" "$DOMAIN" >> "$UNKNOWN_FILE"
            ;;
    esac

done

# Sort accounts alphabetically
for file in "$ENABLED_FILE" "$DISABLED_FILE" "$UNKNOWN_FILE"; do
    sort -o "$file" "$file"
done

# Calculate totals
ENABLED=$(wc -l < "$ENABLED_FILE")
DISABLED=$(wc -l < "$DISABLED_FILE")
UNKNOWN=$(wc -l < "$UNKNOWN_FILE")
TOTAL=$((ENABLED + DISABLED + UNKNOWN))

# Display report
echo ""
echo "=============================================================="
echo "               CPANEL BACKUP STATUS REPORT"
echo "=============================================================="

# Backup enabled accounts
echo ""
echo "--------------- BACKUP ENABLED ($ENABLED) ----------------"
printf "%-25s %-40s\n" "USERNAME" "DOMAIN"
echo "--------------------------------------------------------------"

while IFS=$'\t' read -r USER DOMAIN; do
    [[ -z "$USER" ]] && continue
    printf "%-25s %-40s\n" "$USER" "$DOMAIN"
done < "$ENABLED_FILE"

# Backup disabled accounts
echo ""
echo "--------------- BACKUP DISABLED ($DISABLED) ---------------"
printf "%-25s %-40s\n" "USERNAME" "DOMAIN"
echo "--------------------------------------------------------------"

while IFS=$'\t' read -r USER DOMAIN; do
    [[ -z "$USER" ]] && continue
    printf "%-25s %-40s\n" "$USER" "$DOMAIN"
done < "$DISABLED_FILE"

# Unknown backup status
if (( UNKNOWN > 0 )); then

    echo ""
    echo "--------------- UNKNOWN STATUS ($UNKNOWN) ----------------"

    printf "%-25s %-40s\n" "USERNAME" "DOMAIN"
    echo "--------------------------------------------------------------"

    while IFS=$'\t' read -r USER DOMAIN; do
        [[ -z "$USER" ]] && continue
        printf "%-25s %-40s\n" "$USER" "$DOMAIN"
    done < "$UNKNOWN_FILE"

fi

# Final summary
echo ""
echo "=============================================================="
echo "                       SUMMARY"
echo "=============================================================="

echo "TOTAL ACCOUNTS  : $TOTAL"
echo "BACKUP ENABLED  : $ENABLED"
echo "BACKUP DISABLED : $DISABLED"
echo "UNKNOWN         : $UNKNOWN"

echo "=============================================================="
echo ""
echo "Backup status check completed."

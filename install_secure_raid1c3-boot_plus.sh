#!/bin/bash
# Author: NAZY-OS
# License: MIT License
# Description: Secure boot setup with btrfs RAID for GRUB
# Version: 2.0 (vollständig überarbeitet)
# Usage: ./install_secure_raid1c3-boot_plus.sh -r /dev/sdb /dev/sdc [-b /dev/nvme0n1p1] -s /dev/sda

set -euo pipefail

# =============================================
# HELP FUNCTION
# =============================================
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Secure boot setup script with btrfs RAID support

Options:
  -h, --help            Show this help message
  -b, --boot DEVICE     Source device with /boot partition to copy files from
  -s, --target DEVICE   Target device for GRUB MBR installation
  -d, --destiny PATH    Mount point for the new /boot partition (default: /mnt/secure_boot)
  -c, --chroot-source PATH|DEVICE
                        Path to chroot environment or device to bind mount
  -r, --raid DEVICE1 [DEVICE2 ...]
                        2 devices for RAID1 or 3+ devices for RAID1c3

IMPORTANT NOTES:
1. All data on target devices will be DESTROYED!
2. For RAID1: Exactly 2 devices required
3. For RAID1c3: Minimum 3 devices required
4. GRUB will be installed in MBR mode with btrfs support

Examples:
  # RAID1 with 2 devices
  $0 -r /dev/sdb /dev/sdc -b /dev/nvme0n1p1 -s /dev/sda

  # RAID1c3 with 3 devices
  $0 --raid /dev/vdb1 /dev/vdc1 /dev/vdd1 --boot /dev/sda1 --target /dev/sdb
EOF
}

# =============================================
# ERROR HANDLING
# =============================================
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

confirm_operation() {
    local devices_list="$1"
    read -p "WARNING: This will destroy all data on: $devices_list. Continue? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || error_exit "Operation cancelled by user"
}

# =============================================
# INITIAL SETUP
# =============================================
[[ $EUID -eq 0 ]] || error_exit "This script must be run as root"

# Variables
boot_source=""
grub_target=""
raid_devices=()
mount_point="/mnt/secure_boot"
chroot_source=""
temp_dirs=()
raid_level="raid1"
chroot_mount=""
base_mount_point="/mnt"

# =============================================
# ARGUMENT PARSING
# =============================================
while getopts ":hb:s:d:c:r:-:" opt; do
    case $opt in
        h) show_help; exit 0 ;;
        b) boot_source="$OPTARG" ;;
        s) grub_target="$OPTARG" ;;
        d) mount_point="$OPTARG" ;;
        c) chroot_source="$OPTARG" ;;
        r)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                raid_devices+=("$1")
                shift
            done
            ;;
        -)
            case "${OPTARG}" in
                help) show_help; exit 0 ;;
                boot) shift; boot_source="$1"; shift ;;
                target) shift; grub_target="$1"; shift ;;
                destiny) shift; mount_point="$1"; shift ;;
                chroot_source) shift; chroot_source="$1"; shift ;;
                raid)
                    shift
                    while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                        raid_devices+=("$1")
                        shift
                    done
                    ;;
                *) error_exit "Invalid option: --${OPTARG}" ;;
            esac
            ;;
        \?) error_exit "Invalid option: -$OPTARG" ;;
        :) error_exit "Option -$OPTARG requires an argument." ;;
    esac
done

# =============================================
# VALIDATION
# =============================================
[[ -z "$boot_source" && -z "$grub_target" && ${#raid_devices[@]} -eq 0 ]] &&
    error_exit "No operation specified"

if [[ ${#raid_devices[@]} -gt 0 ]]; then
    if [[ ${#raid_devices[@]} -eq 2 ]]; then
        raid_level="raid1"
    elif [[ ${#raid_devices[@]} -ge 3 ]]; then
        raid_level="raid1c3"
    else
        error_exit "At least 2 devices required for RAID"
    fi

    for device in "${raid_devices[@]}"; do
        mountpoint -q "$(findmnt -n -o TARGET "$device")" &&
            error_exit "Device $device is already mounted"
    done
fi

[[ -n "$boot_source" ]] &&
    mountpoint -q "$(findmnt -n -o TARGET "$boot_source")" ||
    error_exit "Boot source must be mounted"

# =============================================
# CHROOT HANDLING (KORRIGIERT)
# =============================================
if [[ -n "$chroot_source" ]]; then
    if [[ -b "$chroot_source" ]]; then
        temp_chroot=$(mktemp -d -p "$base_mount_point" chroot_XXXXXX)
        temp_dirs+=("$temp_chroot")
        mount "$chroot_source" "$temp_chroot" ||
            error_exit "Failed to mount chroot source"
        chroot_mount="$temp_chroot"
    elif [[ -d "$chroot_source" ]]; then
        chroot_mount="$chroot_source"
    else
        error_exit "Chroot source must be device or directory"
    fi
fi

# =============================================
# RAID SETUP (KORRIGIERT)
# =============================================
if [[ ${#raid_devices[@]} -gt 0 ]]; then
    confirm_operation "${raid_devices[*]}"

    # Create mount point
    mkdir -p "$mount_point" || error_exit "Failed to create mount point"

    # Format and mount RAID
    echo "Creating btrfs $raid_level filesystem..."
    mkfs.btrfs --label 'SecureGrubBoot' --force -m "$raid_level" -d "$raid_level" "${raid_devices[@]}" ||
        error_exit "Failed to create filesystem"

    echo "Mounting RAID to $mount_point..."
    mount LABEL=SecureGrubBoot "$mount_point" ||
        error_exit "Failed to mount RAID"

    # Copy boot files
    if [[ -n "$boot_source" ]]; then
        if [[ -n "$chroot_mount" ]]; then
            echo "Copying from chroot..."
            [[ -d "${chroot_mount}/boot" ]] ||
                error_exit "No /boot in chroot"
            cp -a "${chroot_mount}/boot/"* "$mount_point/" ||
                error_exit "Failed to copy from chroot"
        else
            source_mount=$(findmnt -n -o TARGET "$boot_source")
            echo "Copying from $source_mount..."
            [[ -d "${source_mount}/boot" ]] ||
                error_exit "No /boot on source"
            cp -a "${source_mount}/boot/"* "$mount_point/" ||
                error_exit "Failed to copy"
        fi
    else
        echo "Warning: No boot source specified"
    fi

    mkdir -p "$mount_point/grub" ||
        error_exit "Failed to create grub dir"
fi

# =============================================
# GRUB INSTALLATION
# =============================================
if [[ -n "$grub_target" ]]; then
    echo "Installing GRUB to $grub_target..."
    grub-install --target=i386-pc --modules="btrfs" --force "$grub_target" ||
        error_exit "GRUB install failed"
fi

# =============================================
# SUCCESS REPORT
# =============================================
echo
echo "============================================"
echo "SUCCESS: All operations completed"
echo "============================================"
[[ -n "$boot_source" ]] && echo "Boot source: $boot_source${chroot_mount:+ (via chroot)}"
[[ -n "$grub_target" ]] && echo "GRUB target: $grub_target"
[[ ${#raid_devices[@]} -gt 0 ]] && echo "RAID $raid_level on: ${raid_devices[*]}"
echo "Mount point: $mount_point"
echo "============================================"

# =============================================
# CLEANUP (KORRIGIERT)
# =============================================
if [[ ${#raid_devices[@]} -gt 0 ]]; then
    umount "$mount_point" 2>/dev/null || true
    rmdir "$mount_point" 2>/dev/null || true
fi

if [[ -n "$chroot_mount" ]]; then
    if [[ -n "$temp_chroot" ]]; then
        umount "$chroot_mount" 2>/dev/null || true
        rmdir "$chroot_mount" 2>/dev/null || true
    fi
fi

for dir in "${temp_dirs[@]}"; do
    rmdir "$dir" 2>/dev/null || true
done

exit 0

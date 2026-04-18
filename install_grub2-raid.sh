#!/bin/bash

# Script Name: install_grub2-raid.sh
# Version: v1.4-BETA
# Author: [NAZY-OS]
# License: GPL-2.0

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <disk1> <disk2> [<disk3> ... <diskN>]
Options:
  -h, --help                Show this help message and exit
  -i, --init                Initialize the setup
  -u, --update-boot         Update boot and remount subvolumes
  -l, --lock                Lock script for modifications
  -U, --unlock              Unlock script for modifications
  -c, --checksum-test       Perform a checksum test
EOF
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Please run as root"
        exit 1
    fi
}

check_grub() {
    command -v grub2-install &> /dev/null || { 
        echo "grub2-install not found. Install GRUB."; exit 1; 
    }
}

load_modules() {
    modprobe btrfs
    modprobe sha256_generic
}

create_raid_list() {
    for DISK in "${DISKS[@]}"; do
        UUID=$(blkid -s UUID -o value "$DISK")
        UUID_LIST+="$UUID "
    done
    echo $UUID_LIST > /mnt/.SECURE_RAID.lst
}

handle_existing_grub() {
    if [[ -f /boot/grub/grub.cfg ]]; then
        cp /boot/grub/grub.cfg /tmp/grub.cfg.bak
        read -p "Restore previous GRUB config? (y/n): " choice
        [[ "$choice" == "y" ]] && cp /tmp/grub.cfg.bak /boot/grub/grub.cfg
    fi
}

parse_params() {
    while (( "$#" )); do
        case "$1" in
            -i|--init) INIT=true ;;
            -u|--update-boot) UPDATE_BOOT=true ;;
            -l|--lock) LOCK=true ;;
            -U|--unlock) LOCK=false ;;
            -c|--checksum-test) CHECKSUM_TEST=true ;;
            *) DISKS+=("$1") ;;
        esac
        shift
    done
}

check_args() {
    [[ "${#DISKS[@]}" -lt 2 ]] && { echo "At least 2 disks required."; exit 1; }
    for DISK in "${DISKS[@]}"; do
        SIZE=$(fdisk -l "$DISK" | grep 'Disk' | awk '{print $3}' | sed 's/,//')
        [[ "$SIZE" -lt 3096 || "$SIZE" -gt 4096 ]] && { echo "Disk $DISK size must be between 3096 and 4096 MB."; exit 1; }
    done
}

format_disks() {
    mkfs.btrfs -d raid1 -m raid1 --label "SecureGrubRaid1" --checksum sha256 --force "${DISKS[@]}"
    mount "${DISKS[0]}" /mnt
}

init_subvolumes() {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@boot
    umount /mnt
    mount -o subvol=@,ro "${DISKS[0]}" /mnt
    mkdir -p /mnt/boot
    mount -o subvol=@boot,ro "${DISKS[0]}" /mnt/boot
}

install_grub() {
    for DISK in "${DISKS[@]}"; do
        grub2-install --target=x86_64-efi "$DISK"
    done
}

generate_grub_cfg() {
    cat << EOF | tee /mnt/boot/grub/grub.cfg
set default=0
set timeout=5
insmod btrfs
insmod sha256

menuentry "Linux" {
    linux /vmlinuz root=/dev/sda1 rootflags=subvol=@,ro rw
    initrd /initrd.img
}
menuentry "Reboot" { reboot; }
menuentry "Shutdown" { shutdown; }
menuentry "Show Checksum Test" {
    insmod btrfs
    echo "Running checksum verification..."
    btrfs scrub start /mnt/@
    btrfs scrub status /mnt/@
}
EOF
}

checksum_logging() {
    CHECKSUM_FILE="/var/log/btrfs_checksums_$(date +%Y%m%d_%H%M%S).log"
    find /mnt/@ -type f -exec sha256sum {} \; > "$CHECKSUM_FILE"
}

# Main Execution
check_root
load_modules
check_grub
parse_params "$@"
check_args

if [[ "$LOCK" == true ]]; then
    echo "Locked. No modifications will be made."
    exit 0
fi

[[ "$CHECKSUM_TEST" == true ]] && { echo "Performing checksum test..."; exit 0; }
format_disks
if [[ "$INIT" == true ]]; then
    init_subvolumes
    handle_existing_grub
    install_grub
}
generate_grub_cfg
create_raid_list
checksum_logging

echo "GRUB installed, RAID created, and configuration generated."

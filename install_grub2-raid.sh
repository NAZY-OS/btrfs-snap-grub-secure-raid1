#!/bin/bash

# Script Name: install_grub2-raid.sh
# Version: v1.5-BETA
# Author: [NAZY-OS]
# License: GPL-2.0

# Display usage help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <disk1> <disk2> [<disk3> ... <diskN>]
Options:
  -h, --help                Show this help message and exit
  -i, --init                Initialize the setup
  -u, --update-boot         Update boot and remount subvolumes
  -l, --lock                Lock script to prevent modifications
  -U, --unlock              Unlock script for modifications
  -f, --force               Force execution of operations
EOF
}

# Check if the script is run as root
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

# Check if the 'grub2-install' command is available
check_grub() {
    command -v grub2-install &> /dev/null || { 
        echo "Error: grub2-install not found. Install GRUB."; 
        exit 1; 
    }
}

# Load necessary kernel modules
load_modules() {
    modprobe btrfs || { echo "Error: Failed to load btrfs module."; exit 1; }
}

# Unmount all partitions
unmount_partitions() {
    for PARTITION in /dev/sd*1; do
        if mount | grep "$PARTITION" > /dev/null; then
            umount "$PARTITION" || { echo "Error: Failed to unmount $PARTITION."; exit 1; }
        fi
    done
}

# Create a list of UUIDs from the provided disks
create_raid_list() {
    UUID_LIST=""
    for DISK in "${DISKS[@]}"; do
        UUID=$(blkid -s UUID -o value "$DISK") || { echo "Error: Failed to get UUID for $DISK"; exit 1; }
        UUID_LIST+="$UUID "
    done
    echo "$UUID_LIST" > /mnt/.SECURE_RAID.lst
}

# Handle existing GRUB configuration
handle_existing_grub() {
    if [[ -f /boot/grub/grub.cfg ]]; then
        cp /boot/grub/grub.cfg /tmp/grub.cfg.bak
        read -p "Restore previous GRUB config? (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            cp /tmp/grub.cfg.bak /boot/grub/grub.cfg || { echo "Error: Failed to restore GRUB config."; exit 1; }
        fi
    fi
}

# Parse command-line parameters
parse_params() {
    while (( "$#" )); do
        case "$1" in
            -i|--init) INIT=true ;;
            -u|--update-boot) UPDATE_BOOT=true ;;
            -l|--lock) LOCK=true ;;
            -U|--unlock) LOCK=false ;;
            -f|--force) FORCE=true ;;
            *) DISKS+=("$1") ;;  # Collect disk parameters
        esac
        shift
    done
}

# Validate the provided disks
check_args() {
    if [[ "${#DISKS[@]}" -lt 2 ]]; then
        echo "Error: At least 2 disks are required."
        exit 1
    fi
    for DISK in "${DISKS[@]}"; do
        SIZE=$(fdisk -l "$DISK" | grep 'Disk' | awk '{print $3}' | sed 's/,//') || { 
            echo "Error: Failed to get size for $DISK"; 
            exit 1; 
        }
        if [[ "$SIZE" -lt 3096 || "$SIZE" -gt 4096 ]]; then
            echo "Error: Disk $DISK size must be between 3096 and 4096 MB."
            exit 1
        fi
    done
}

# Format the disks with Btrfs file system
format_disks() {
    mkfs.btrfs -d raid1 -m raid1 --label "SecureGrubRaid1" --force "${DISKS[@]}" || {
        echo "Error: Failed to format disks."
        exit 1
    }
    mount "${DISKS[0]}" /mnt || { echo "Error: Failed to mount ${DISKS[0]} to /mnt."; exit 1; }
}

# Initialize Btrfs subvolumes
init_subvolumes() {
    btrfs subvolume create /mnt/@ || { echo "Error: Failed to create subvolume @."; exit 1; }
    btrfs subvolume create /mnt/@boot || { echo "Error: Failed to create subvolume @boot."; exit 1; }
    umount /mnt || { echo "Error: Failed to unmount /mnt."; exit 1; }

    mount -o subvol=@,ro "${DISKS[0]}" /mnt || { echo "Error: Failed to mount @ subvolume."; exit 1; }
    mkdir -p /mnt/boot
    mount -o subvol=@boot,ro "${DISKS[0]}" /mnt/boot || { echo "Error: Failed to mount @boot subvolume."; exit 1; }
}

# Install GRUB on the specified disks
install_grub() {
    for DISK in "${DISKS[@]}"; do
        grub2-install --target=x86_64-efi "$DISK" || {
            echo "Error: Failed to install GRUB on $DISK."
            exit 1
        }
    done
}

# Generate the GRUB configuration file
generate_grub_cfg() {
    cat << EOF | tee /mnt/boot/grub/grub.cfg
set default=0
set timeout=5
insmod btrfs

menuentry "Linux" {
    linux /vmlinuz root=/dev/sda1 rootflags=subvol=@,ro rw
    initrd /initrd.img
}
menuentry "Reboot" { reboot; }
menuentry "Shutdown" { shutdown; }
EOF
}

# Main Execution
check_root
load_modules
check_grub
parse_params "$@"
unmount_partitions
check_args

if [[ "$LOCK" == true ]]; then
    echo "Locked. No modifications will be made."
    exit 0
fi

format_disks
if [[ "$INIT" == true || "$FORCE" == true ]]; then
    init_subvolumes
    handle_existing_grub
    
    # Check if grub.cfg exists before proceeding with installation
    if [[ -f /mnt/boot/grub/grub.cfg ]]; then
        install_grub
    else
        echo "No grub.cfg found; skipping GRUB installation."
    fi
fi

generate_grub_cfg
create_raid_list

echo "GRUB installed, RAID created, and configuration generated."
#!/bin/bash

# Script Name: install_grub2-raid.sh
# Version: v1.5-BETA
# Author: [NAZY-OS]
# License: GPL-2.0

# Display usage help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <disk1> <disk2> [<disk3> ... <diskN>]
Options:
  -h, --help                Show this help message and exit
  -i, --init                Initialize the setup
  -u, --update-boot         Update boot and remount subvolumes
  -l, --lock                Lock script to prevent modifications
  -U, --unlock              Unlock script for modifications
  -c, --checksum-test       Perform a checksum test
  -f, --force               Force execution of operations
EOF
}

# Check if the script is run as root
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

# Check if the 'grub2-install' command is available
check_grub() {
    command -v grub2-install &> /dev/null || { 
        echo "Error: grub2-install not found. Install GRUB."; 
        exit 1; 
    }
}

# Load necessary kernel modules
load_modules() {
    modprobe btrfs || { echo "Error: Failed to load btrfs module."; exit 1; }
    modprobe sha256_generic || { echo "Error: Failed to load sha256_generic module."; exit 1; }
}

# Create a list of UUIDs from the provided disks
create_raid_list() {
    UUID_LIST=""
    for DISK in "${DISKS[@]}"; do
        UUID=$(blkid -s UUID -o value "$DISK") || { echo "Error: Failed to get UUID for $DISK"; exit 1; }
        UUID_LIST+="$UUID "
    done
    echo "$UUID_LIST" > /mnt/.SECURE_RAID.lst
}

# Handle existing GRUB configuration
handle_existing_grub() {
    if [[ -f /boot/grub/grub.cfg ]]; then
        cp /boot/grub/grub.cfg /tmp/grub.cfg.bak
        read -p "Restore previous GRUB config? (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            cp /tmp/grub.cfg.bak /boot/grub/grub.cfg || { echo "Error: Failed to restore GRUB config."; exit 1; }
        fi
    fi
}

# Parse command-line parameters
parse_params() {
    while (( "$#" )); do
        case "$1" in
            -i|--init) INIT=true ;;
            -u|--update-boot) UPDATE_BOOT=true ;;
            -l|--lock) LOCK=true ;;
            -U|--unlock) LOCK=false ;;
            -c|--checksum-test) CHECKSUM_TEST=true ;;
            -f|--force) FORCE=true ;;
            *) DISKS+=("$1") ;;  # Collect disk parameters
        esac
        shift
    done
}

# Validate the provided disks
check_args() {
    if [[ "${#DISKS[@]}" -lt 2 ]]; then
        echo "Error: At least 2 disks are required."
        exit 1
    fi
    for DISK in "${DISKS[@]}"; do
        SIZE=$(fdisk -l "$DISK" | grep 'Disk' | awk '{print $3}' | sed 's/,//') || { 
            echo "Error: Failed to get size for $DISK"; 
            exit 1; 
        }
        if [[ "$SIZE" -lt 3096 || "$SIZE" -gt 4096 ]]; then
            echo "Error: Disk $DISK size must be between 3096 and 4096 MB."
            exit 1
        fi
    done
}

# Format the disks with Btrfs file system
format_disks() {
    mkfs.btrfs -d raid1 -m raid1 --label "SecureGrubRaid1" --checksum sha256 --force "${DISKS[@]}" || {
        echo "Error: Failed to format disks."
        exit 1
    }
    mount "${DISKS[0]}" /mnt || { echo "Error: Failed to mount ${DISKS[0]} to /mnt."; exit 1; }
}

# Initialize Btrfs subvolumes
init_subvolumes() {
    btrfs subvolume create /mnt/@ || { echo "Error: Failed to create subvolume @."; exit 1; }
    btrfs subvolume create /mnt/@boot || { echo "Error: Failed to create subvolume @boot."; exit 1; }
    umount /mnt || { echo "Error: Failed to unmount /mnt."; exit 1; }
    
    mount -o subvol=@,ro "${DISKS[0]}" /mnt || { echo "Error: Failed to mount @ subvolume."; exit 1; }
    mkdir -p /mnt/boot
    mount -o subvol=@boot,ro "${DISKS[0]}" /mnt/boot || { echo "Error: Failed to mount @boot subvolume."; exit 1; }
}

# Install GRUB on the specified disks
install_grub() {
    for DISK in "${DISKS[@]}"; do
        grub2-install --target=x86_64-efi "$DISK" || {
            echo "Error: Failed to install GRUB on $DISK."
            exit 1
        }
    done
}

# Generate the GRUB configuration file
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

# Log the checksums of files in the Btrfs subvolume
checksum_logging() {
    CHECKSUM_FILE="/var/log/btrfs_checksums_$(date +%Y%m%d_%H%M%S).log"
    find /mnt/@ -type f -exec sha256sum {} \; > "$CHECKSUM_FILE" || {
        echo "Error: Failed to generate checksums."
        exit 1
    }
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

if [[ "$CHECKSUM_TEST" == true ]]; then
    echo "Performing checksum test..."
    checksum_logging
    exit 0
fi

format_disks
if [[ "$INIT" == true || "$FORCE" == true ]]; then
    init_subvolumes
    handle_existing_grub
    
    # Check if grub.cfg exists before proceeding with installation
    if [[ -f /mnt/boot/grub/grub.cfg ]]; then
        install_grub
    else
        echo "No grub.cfg found; skipping GRUB installation."
    fi
fi

generate_grub_cfg
create_raid_list
checksum_logging

echo "GRUB installed, RAID created, and configuration generated."
#!/bin/bash

# Script Name: install_grub2-raid.sh
# Version: v1.4-BETA
# Author: [NAZY-OS]
# License: GPL-2.0

# Display usage help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <disk1> <disk2> [<disk3> ... <diskN>]
Options:
  -h, --help                Show this help message and exit
  -i, --init                Initialize the setup
  -u, --update-boot         Update boot and remount subvolumes
  -l, --lock                Lock script to prevent modifications
  -U, --unlock              Unlock script for modifications
  -c, --checksum-test       Perform a checksum test
EOF
}

# Check if the script is run as root
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

# Check if the 'grub2-install' command is available
check_grub() {
    command -v grub2-install &> /dev/null || { 
        echo "Error: grub2-install not found. Install GRUB."; 
        exit 1; 
    }
}

# Load necessary kernel modules
load_modules() {
    modprobe btrfs || { echo "Error: Failed to load btrfs module."; exit 1; }
    modprobe sha256_generic || { echo "Error: Failed to load sha256_generic module."; exit 1; }
}

# Create a list of UUIDs from the provided disks
create_raid_list() {
    UUID_LIST=""
    for DISK in "${DISKS[@]}"; do
        UUID=$(blkid -s UUID -o value "$DISK") || { echo "Error: Failed to get UUID for $DISK"; exit 1; }
        UUID_LIST+="$UUID "
    done
    echo "$UUID_LIST" > /mnt/.SECURE_RAID.lst
}

# Handle existing GRUB configuration
handle_existing_grub() {
    if [[ -f /boot/grub/grub.cfg ]]; then
        cp /boot/grub/grub.cfg /tmp/grub.cfg.bak
        read -p "Restore previous GRUB config? (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            cp /tmp/grub.cfg.bak /boot/grub/grub.cfg
        fi
    fi
}

# Parse command-line parameters
parse_params() {
    while (( "$#" )); do
        case "$1" in
            -i|--init) INIT=true ;;
            -u|--update-boot) UPDATE_BOOT=true ;;
            -l|--lock) LOCK=true ;;
            -U|--unlock) LOCK=false ;;
            -c|--checksum-test) CHECKSUM_TEST=true ;;
            *) DISKS+=("$1") ;;  # Collect disk parameters
        esac
        shift
    done
}

# Validate the provided disks
check_args() {
    if [[ "${#DISKS[@]}" -lt 2 ]]; then
        echo "Error: At least 2 disks are required."
        exit 1
    fi
    for DISK in "${DISKS[@]}"; do
        SIZE=$(fdisk -l "$DISK" | grep 'Disk' | awk '{print $3}' | sed 's/,//') || { 
            echo "Error: Failed to get size for $DISK"; 
            exit 1; 
        }
        if [[ "$SIZE" -lt 3096 || "$SIZE" -gt 4096 ]]; then
            echo "Error: Disk $DISK size must be between 3096 and 4096 MB."
            exit 1
        fi
    done
}

# Format the disks with Btrfs file system
format_disks() {
    mkfs.btrfs -d raid1 -m raid1 --label "SecureGrubRaid1" --checksum sha256 --force "${DISKS[@]}" || {
        echo "Error: Failed to format disks.";
        exit 1;
    }
    mount "${DISKS[0]}" /mnt || { echo "Error: Failed to mount ${DISKS[0]} to /mnt."; exit 1; }
}

# Initialize Btrfs subvolumes
init_subvolumes() {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@boot
    umount /mnt || { echo "Error: Failed to unmount /mnt."; exit 1; }
    mount -o subvol=@,ro "${DISKS[0]}" /mnt || { echo "Error: Failed to mount @ subvolume."; exit 1; }
    mkdir -p /mnt/boot
    mount -o subvol=@boot,ro "${DISKS[0]}" /mnt/boot || { echo "Error: Failed to mount @boot subvolume."; exit 1; }
}

# Install GRUB on the specified disks
install_grub() {
    for DISK in "${DISKS[@]}"; do
        grub2-install --target=x86_64-efi "$DISK" || {
            echo "Error: Failed to install GRUB on $DISK."
            exit 1
        }
    done
}

# Generate the GRUB configuration file
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

# Log the checksums of files in the Btrfs subvolume
checksum_logging() {
    CHECKSUM_FILE="/var/log/btrfs_checksums_$(date +%Y%m%d_%H%M%S).log"
    find /mnt/@ -type f -exec sha256sum {} \; > "$CHECKSUM_FILE" || {
        echo "Error: Failed to generate checksums."
        exit 1
    }
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

if [[ "$CHECKSUM_TEST" == true ]]; then
    echo "Performing checksum test..."
    checksum_logging
    exit 0
fi

format_disks
if [[ "$INIT" == true ]]; then
    init_subvolumes
    handle_existing_grub

    # Check if grub.cfg exists before proceeding with installation
    if [[ -f /mnt/boot/grub/grub.cfg ]]; then
        install_grub
    else
        echo "No grub.cfg found; skipping GRUB installation."
    fi
fi

generate_grub_cfg
create_raid_list
checksum_logging

echo "GRUB installed, RAID created, and configuration generated."

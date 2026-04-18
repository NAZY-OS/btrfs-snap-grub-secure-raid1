#!/bin/bash

# Script Name: install_grub2-raid.sh
# Version: v1.2-BETA
# Author: [NAZY-OS]
# License: GPL-2.0

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <disk1> <disk2> [<disk3> ... <diskN>]

Options:
  -h, --help                Show this help message and exit
  -u, --update-boot         Update boot and remount subvolumes as read-write
  -l, --lock                Lock the script to prevent modifications
  -u, --unlock              Unlock the script to allow modifications
  -c, --checksum-test       Perform a checksum and file change test

Note: A minimum of 3 disks is recommended for optimal performance.
The total size of each disk should be between 3096 and 4096 MB.

Examples:
  $0 /dev/sda /dev/sdb
  $0 /dev/sda /dev/sdb /dev/sdc --update-boot
EOF
}

# Function to create the .SECURE_RAID.lst file
create_secure_raid_list() {
    echo "Creating .SECURE_RAID.lst with UUIDs of boot disks."
    UUID_LIST=""

    for DISK in "${DISKS[@]}"; do
        UUID=$(sudo blkid -s UUID -o value "$DISK")
        UUID_LIST+="$UUID "
    done

    echo $UUID_LIST > /mnt/.SECURE_RAID.lst
}

# Function to handle existing GRUB files
handle_existing_grub() {
    if [ -f /boot/grub/grub.cfg ]; then
        echo "Existing GRUB configuration found. Creating a backup in /tmp."
        sudo cp /boot/grub/grub.cfg /tmp/grub.cfg.bak

        read -p "Do you want to restore the previous GRUB configuration? (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            sudo cp /tmp/grub.cfg.bak /boot/grub/grub.cfg
            echo "Previous GRUB configuration restored."
        fi
    fi
}

# Check the number of parameters
if [ "$#" -lt 3 ] && [[ "$1" != "--checksum-test" && "$1" != "-c" ]]; then
    show_help
    exit 1
fi

DISKS=()
UPDATE_BOOT=false
LOCK=false
CHECKSUM_TEST=false

# Check for parameters
while (( "$#" )); do
    case "$1" in
        --update-boot|-u)
            UPDATE_BOOT=true
            shift
            ;;
        --lock|-l)
            LOCK=true
            shift
            ;;
        --unlock|-u)
            LOCK=false
            shift
            ;;
        --checksum-test|-c)
            CHECKSUM_TEST=true
            shift
            ;;
        *)
            DISKS+=("$1")
            shift
            ;;
    esac
done

if [ "$LOCK" = true ]; then
    echo "The script is in lock mode. No modifications will be made."
    exit 0
fi

if [ "$CHECKSUM_TEST" = true ]; then
    CHECKSUM_FILE="/var/log/btrfs_checksums.log"
    TARGET_DIR="/mnt/@"

    if [[ ! -f $CHECKSUM_FILE ]]; then
        echo "Checksum file not found. Please run the script without the checksum test option to create it first."
        exit 1
    fi

    OLD_CHECKSUMS=$(cat "$CHECKSUM_FILE")
    NEW_CHECKSUMS=$(find "$TARGET_DIR" -type f -exec sha256sum {} \;)

    echo "Checking for changes..."
    DIFF=$(diff <(echo "$OLD_CHECKSUMS") <(echo "$NEW_CHECKSUMS"))

    if [[ -n "$DIFF" ]]; then
        echo "Changes detected:"
        echo "$DIFF"
    else
        echo "No changes found."
    fi
    exit 0
fi

# Check for sufficient disk space
for DISK in "${DISKS[@]}"; do
    SIZE=$(sudo fdisk -l "$DISK" | grep 'Disk' | awk '{print $3}')
    
    if [ "$SIZE" -lt 3096 ] || [ "$SIZE" -gt 4096 ]; then
        echo "Disk $DISK size must be between 3096 and 4096 MB."
        exit 1
    fi
done

# Format the Btrfs file system with RAID 1, SHA256 checksums, and label
echo "Formatting the Btrfs file system in RAID 1 with SHA256 checksums and label 'SecureGrubRaid1'"
sudo mkfs.btrfs -d raid1 -m raid1 --label "SecureGrubRaid1" --checksum sha256 "${DISKS[@]}"

# Mount the Btrfs file system
echo "Mounting the Btrfs file system"
sudo mount "${DISKS[0]}" /mnt

# Create the subvolumes
sudo btrfs subvolume create /mnt/@          # Root subvolume
sudo btrfs subvolume create /mnt/@boot      # Boot subvolume
sudo umount /mnt

# Mount the subvolumes with read-only option
sudo mount -o subvol=@,ro "${DISKS[0]}" /mnt        # Mount root subvolume as read-only
sudo mkdir -p /mnt/boot
sudo mount -o subvol=@boot,ro "${DISKS[0]}" /mnt/boot # Mount boot subvolume as read-only

# Handle existing GRUB files
handle_existing_grub

# Install GRUB on all specified disks
for DISK in "${DISKS[@]}"; do
    echo "Installing GRUB on $DISK"
    sudo grub-install --target=i386-pc "$DISK"
done

# Generate GRUB configuration
echo "Adding custom entry to GRUB configuration"
cat <<EOF | sudo tee /etc/grub.d/40_custom
set default=0
set timeout=5

menuentry "Linux" {
    linux /vmlinuz root=/dev/sda1 rootflags=subvol=@,ro rw
    initrd /initrd.img
}

menuentry "Reboot" {
    reboot
}

menuentry "Shutdown" {
    shutdown
}

menuentry "Show Checksum Test" {
    insmod btrfs
    echo "Running checksum verification..."
    btrfs scrub start /mnt/@
    btrfs scrub status /mnt/@
}
EOF

# Generate the final GRUB configuration
echo "Generating GRUB configuration"
sudo grub-mkconfig -o /mnt/boot/grub/grub.cfg

# Create .SECURE_RAID.lst file
create_secure_raid_list

# Checksum and change logging
CHECKSUM_FILE="/var/log/btrfs_checksums_$(date +%Y%m%d_%H%M%S).log"
TARGET_DIR="/mnt/@"

if [[ ! -f $CHECKSUM_FILE ]]; then
    echo "Creating initial checksum file..."
    find "$TARGET_DIR" -type f -exec sha256sum {} \; > "$CHECKSUM_FILE"
    echo "Initial checksums saved to $CHECKSUM_FILE."
fi

# Load existing checksums into a new variable
OLD_CHECKSUMS=$(cat "$CHECKSUM_FILE")
NEW_CHECKSUMS=$(find "$TARGET_DIR" -type f -exec sha256sum {} \;)

# Compare and log changes
echo "Checking for changes..."
DIFF=$(diff <(echo "$OLD_CHECKSUMS") <(echo "$NEW_CHECKSUMS"))

if [[ -n "$DIFF" ]]; then
    echo "Changes detected:"
    echo "$DIFF"
    
    CHANGE_LOG="/var/log/btrfs_changes_$(date +%Y%m%d_%H%M%S).log"
    echo "$(date): Changes detected:" >> "$CHANGE_LOG"
    echo "$DIFF" >> "$CHANGE_LOG"
else
    echo "No changes found."
fi

echo "$NEW_CHECKSUMS" > "$CHECKSUM_FILE"

if [ "$UPDATE_BOOT" = true ]; then
    echo "Updating snapshots and remounting the subvolumes as rw"
    sudo umount /mnt
    sudo mount -o remount,rw "${DISKS[0]}" /mnt
    sudo btrfs subvolume snapshot /mnt/@ /mnt/@/.snapshots/root_updated_$(date +%Y%m%d_%H%M%S)
    echo "Snapshots have been updated."
fi

if [ $? -eq 0 ]; then
    echo "GRUB successfully installed on ${DISKS[*]}, snapshots created, and boot subvolume established."
else
    echo "Error during GRUB installation."
    exit 1
fi

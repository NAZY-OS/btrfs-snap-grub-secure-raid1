#!/bin/bash

# Script Name: install_grub2-raid.sh
# Version: v1.6-ALPHA
# Author: [NAZY-OS]
# License: GPL-2.0

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <disk1> <disk2> [<disk3> ... <diskN>]

This script sets up a Btrfs file system with RAID 1 and installs GRUB on specified disks. 
Additionally, it supports checksum testing and snapshot management.

Options:
  -h, --help                Show this help message and exit
  -u, --update-boot         Update boot entries and remount subvolumes as read-write
  -l, --lock                Lock the script to prevent modifications
  -u, --unlock              Unlock the script to allow modifications (note: this flag is the same as -u)
  -c, --checksum-test       Perform a checksum and file change test
  <disk1>, <disk2>, ...     Specify the disks for installation (e.g., /dev/sda /dev/sdb)

Examples:
  $0 /dev/sda /dev/sdb           Install on two disks
  $0 /dev/sda --update-boot      Update boot entries for an existing installation
  $0 /dev/sda --lock             Prevent modifications to the script
  $0 --checksum-test              Perform a checksum test on the installed volume

Important Notes:
- Ensure specified disks are unmounted before running the script.
- The script will create a 3096 MB partition on the first specified disk.
- Use caution when locking the script; modifications will not be saved.

EOF
}

# Check the number of parameters
if [ "$#" -lt 2 ] && [[ "$1" != "--checksum-test" && "$1" != "-c" ]]; then
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

# If script is locked, exit with a message
if [ "$LOCK" = true ]; then
    echo "The script is in lock mode. No modifications will be made."
    exit 0
fi

# Create a new partition on the first disk
create_partition() {
    echo "Creating a 3096 MB partition on ${DISKS[0]}..."
    
    PARTITION_CMD="parted ${DISKS[0]} mklabel gpt; parted -a opt ${DISKS[0]} mkpart primary btrfs 0% 3096MB"
    eval "$PARTITION_CMD"

    if [ $? -eq 0 ]; then
        echo "Partition created successfully."
    else
        echo "Error creating partition."
        exit 1
    fi
}

# Call the function to create a partition
create_partition

# Format the Btrfs file system with RAID 1, SHA256 checksums, and label
echo "Formatting the Btrfs file system in RAID 1 with SHA256 checksums and label 'SecureGrubRaid1'"
sudo mkfs.btrfs -d raid1 -m raid1 --label "SecureGrubRaid1" --checksum sha256 "${DISKS[@]}"

# Mount the Btrfs file system
echo "Mounting the Btrfs file system"
sudo mount "${DISKS[0]}" /mnt

# Check the total available size for the subvolume
TOTAL_SIZE=$(sudo btrfs filesystem df /mnt | grep 'Data' | awk '{print $2}' | sed 's/[A-Za-z]//g')
MAX_SIZE=3096  # Maximum size in MB

if [ "$TOTAL_SIZE" -gt "$MAX_SIZE" ]; then
    echo "Total available size exceeds maximum limit of ${MAX_SIZE} MB for the Btrfs volume."
    exit 1
fi

# Create the subvolumes
sudo btrfs subvolume create /mnt/@          # Root subvolume
sudo btrfs subvolume create /mnt/@boot      # Boot subvolume
sudo umount /mnt

# Mount the subvolumes with read-only option
sudo mount -o subvol=@,ro "${DISKS[0]}" /mnt        # Mount root subvolume as read-only
sudo mkdir -p /mnt/boot
sudo mount -o subvol=@boot,ro "${DISKS[0]}" /mnt/boot # Mount boot subvolume as read-only

# Install GRUB on all specified disks
for DISK in "${DISKS[@]}"; do
    echo "Installing GRUB on $DISK"
    sudo grub-install --target=i386-pc "$DISK"
done

# Generate GRUB configuration in the custom file
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

# Checksum and change logging
CHECKSUM_FILE="/var/log/btrfs_checksums_$(date +%Y%m%d_%H%M%S).log"  # Adding timestamp to checksum log
TARGET_DIR="/mnt/@"

# Initial checksum creation or load
if [[ ! -f $CHECKSUM_FILE ]]; then
    echo "Creating initial checksum file..."
    find "$TARGET_DIR" -type f -exec sha256sum {} \; > "$CHECKSUM_FILE"
    echo "Initial checksums saved to $CHECKSUM_FILE."
fi

# Load existing checksums into a new variable
OLD_CHECKSUMS=$(cat "$CHECKSUM_FILE")

# Calculate new checksums
NEW_CHECKSUMS=$(find "$TARGET_DIR" -type f -exec sha256sum {} \;)

# Compare and log changes
echo "Checking for changes..."
DIFF=$(diff <(echo "$OLD_CHECKSUMS") <(echo "$NEW_CHECKSUMS"))

if [[ -n "$DIFF" ]]; then
    echo "Changes detected:"
    echo "$DIFF"
    
    # Log changes with timestamps, creating a new log file for changes
    CHANGE_LOG="/var/log/btrfs_changes_$(date +%Y%m%d_%H%M%S).log"
    echo "$(date): Changes detected:" >> "$CHANGE_LOG"
    echo "$DIFF" >> "$CHANGE_LOG"
else
    echo "No changes found."
fi

# Update the checksum file for the next comparison
echo "$NEW_CHECKSUMS" > "$CHECKSUM_FILE"  # This will be done in a new timestamped file next run

# If the update boot flag is set
if [ "$UPDATE_BOOT" = true ]; then
    echo "Updating snapshots and remounting the subvolumes as rw"
    
    # Remount the root subvolume as rw and update the snapshots
    sudo umount /mnt
    sudo mount -o remount,rw "${DISKS[0]}" /mnt       # Remount root subvolume as rw
    
    # Update snapshots
    sudo btrfs subvolume snapshot /mnt/@ /mnt/@/.snapshots/root_updated_$(date +%Y%m%d_%H%M%S)
    
    echo "Snapshots have been updated."
fi

if [ $? -eq 0 ]; then
    echo "GRUB successfully installed on ${DISKS[*]}, snapshots created, and boot subvolume established."
else
    echo "Error during GRUB installation."
    exit 1
fi

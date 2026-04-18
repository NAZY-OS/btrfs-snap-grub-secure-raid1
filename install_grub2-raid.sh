#!/bin/bash

# Script Name: install_grub2-raid.sh
# Version: 1.2-ALPHA
# Author: [NAZY-OS]
# License: GPL-2.0
#!/bin/bash

# Function to show help
show_help() {
    echo "Usage: $0 <disk1> <disk2> [<disk3> ... <diskN>] [--update-boot | -u]"
    echo "Example: $0 /dev/sda /dev/sdb /dev/sdc"
    echo "         $0 /dev/sda /dev/sdb --update-boot or -u"
    echo "The script installs GRUB and creates Btrfs snapshots."
}

# Check the number of parameters
if [ "$#" -lt 2 ]; then
    show_help
    exit 1
fi

DISKS=("${@:1:$#-1}")  # Grab all disks except the last parameter
UPDATE_BOOT=false

# Check if the update parameter has been provided
if [[ "${!#}" == "--update-boot" || "${!#}" == "-u" ]]; then
    UPDATE_BOOT=true
fi

# Format the Btrfs file system with RAID 1
echo "Formatting the Btrfs file system in RAID 1"
sudo mkfs.btrfs -d raid1 -m raid1 "${DISKS[@]}"

# Mount the Btrfs file system
echo "Mounting the Btrfs file system"
sudo mount "${DISKS[0]}" /mnt

# Create the subvolumes
sudo btrfs subvolume create /mnt/@          # Root subvolume
sudo btrfs subvolume create /mnt/@boot      # Boot subvolume
sudo umount /mnt

# Mount the subvolumes
sudo mount -o subvol=@ "${DISKS[0]}" /mnt       # Mount root subvolume
sudo mkdir -p /mnt/boot
sudo mount -o subvol=@boot "${DISKS[0]}" /mnt/boot  # Mount boot subvolume

# Install GRUB on all specified disks
for DISK in "${DISKS[@]}"; do
    echo "Installing GRUB on $DISK"
    sudo grub-install --target=i386-pc --debug "$DISK"
done

# Generate GRUB configuration in the custom file
echo "Adding custom entry to GRUB configuration"
cat <<EOF | sudo tee /etc/grub.d/40_custom
set default=0
set timeout=5

menuentry "Linux" {
    linux /vmlinuz root=/dev/sda1 rootflags=subvol=@ rw
    initrd /initrd.img
}
EOF

# Generate the final GRUB configuration
echo "Generating GRUB configuration"
sudo grub-mkconfig -o /mnt/boot/grub/grub.cfg

# Create snapshots of the root subvolume
echo "Creating snapshots of the root subvolume"
sudo btrfs subvolume snapshot /mnt/@ /mnt/@/.snapshots/root_$(date +%Y%m%d_%H%M%S)

# Optionally, create a read-only version of the boot subvolume
echo "Creating read-only version of the boot subvolume"
sudo btrfs subvolume snapshot /mnt/@boot /mnt/@boot/.snapshots/boot_$(date +%Y%m%d_%H%M%S)
sudo umount /mnt/boot
sudo mount -o subvol=@boot,ro "${DISKS[0]}" /mnt/boot  # Mount in read-only mode

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

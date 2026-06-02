#!/bin/bash

# Author: NAZY-OS
# License: MIT License
# Description: Format btrfs /boot to raid1c3
# Version: 1.0

# Function to display help message
function show_help {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --version  Show version information"
}

if [ $? -eq 0 ]; then
    echo "SUCCESSFUL RAID 1 BALANCE PROCESS COMPLETED."
    else
        echo "FAILED RAID 1 BALANCE $parameters."
        fi
        
        
        # Function to create a Btrfs snapshot
        create_snapshot() {
            local source_dir="$1"
            local snapshot_name="$2"
            
            if [[ -z "$source_dir" || -z "$snapshot_name" ]]; then
                echo "Usage: create_snapshot <source_directory> <snapshot_name>"
                return 1
                fi
                
                btrfs subvolume snapshot "$source_dir" "$snapshot_name"
                echo "Snapshot created: $snapshot_name"
        }
        
        # Function to restore a Btrfs snapshot
        restore_snapshot() {
            local snapshot_name="$1"
            local target_dir="$2"
            
            if [[ -z "$snapshot_name" || -z "$target_dir" ]]; then
                echo "Usage: restore_snapshot <snapshot_name> <target_directory>"
                return 1
                fi
                
                # Deleting the target directory
                btrfs subvolume delete "$target_dir"
                
                # Restoring the snapshot
                btrfs subvolume snapshot "$snapshot_name" "$target_dir"
                echo "Snapshot restored: $snapshot_name to $target_dir"
        }
        
        
function confirm_action {
    local message="$1"  # Capture the message parameter
    read -p "$message (y/n): " answer
    case $answer in
        [Yy] )
            echo "Proceeding..."
            return 0  # Successful confirmation
            ;;
        [Nn] )
            echo "Aborting..."
            return 1  # Aborted confirmation
            ;;
        * )
            echo "Invalid response. Please enter 'y' or 'n'."
            confirm_action "$message"  # Recursive call with the same message
            ;;
    esac
}


# Function to display version
function show_version {
    echo "$0 version 1.2"
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Parse command line options
while getopts ":hv" opt; do
    case ${opt} in
        h )
            show_help
            exit 0
            ;;
        v )
            show_version
            exit 0
            ;;
        \? )
            echo "Invalid option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done

# Loop to get user input for parameters
parameters=""
for i in {1..3}; do
    while true; do
        read -p "Enter parameter $i (or press 'c' to cancel): " input
        if [[ $input == "c" ]]; then
            echo "Aborting input..."
            exit 0
        elif [[ -z $input ]]; then
            echo "Empty input received, exiting input loop."
            break  # Break from the loop on empty input
        else
            parameters+="$input "  # Append input to parameters with a space
            echo "Parameter $i set to: $input"
            break  # Exit inner loop to prompt for the next parameter
        fi
    done
done

# Trim trailing whitespace
parameters_string=$(echo "$parameters" | sed 's/[[:space:]]*$//')

# Display the collected parameters
echo "Collected parameters: '$parameters_string'"

if confirm_action "Are you sure you want to proceed?\n mkfs.btrfs --label "SecureGrubRaid1" --force -m raid1 -d raid1 $parameters_string"; then
    echo "Executing main script logic..."
else
    echo "Exiting the script."
    exit 1
fi

mkfs.btrfs --label "SecureGrubRaid1" --force -m raid1 -d raid1 $parameters_string

if [ $? -eq 0 ]; then
    echo "SUCCESSFUL created RAID 1."
else
    echo "FAILED to format RAID 1."
fi


mkdir /media/btrfs &> /dev/null

mount $parameters /media/btrfs && btrfs filesystem show /media/btrfs && btrfs balance start /media/btrfs && btrfs balance status /media/btrfs

echo "Mounted Raid-1c3 to:   /media/btrfs
    
    

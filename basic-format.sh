#!/bin/bash

# Check if at least two arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <disk1> <disk2> ..."
    exit 1
fi

# Array to store valid partitions and their sizes
partitions=()
sizes=()

# Iterate through all provided arguments
for disk in "$@"; do
    partition="${disk}1"
    
    # Get the size of the partition in MB
    size=$(lsblk -b -o SIZE "${partition}" | tail -n1)
    size_mb=$((size / 1024 / 1024))  # Convert bytes to MB

    # Check if the partition size is between 3095 MB and 4097 MB
    if [ "$size_mb" -gt 3095 ] && [ "$size_mb" -lt 4097 ]; then
        partitions+=("${partition}")  # Add the valid partition
        sizes+=("$size_mb")           # Store the size
    else
        echo "Partition ${partition} is not within the valid size range: ${size_mb} MB"
        exit 1
    fi
done

# Check if there are exactly two valid partitions found
if [ "${#partitions[@]}" -ne 2 ]; then
    echo "Invalid number of partitions found. Please provide exactly two valid partitions."
    exit 1
fi

# Check if both partitions have the same size
if [ "${sizes[0]}" -ne "${sizes[1]}" ]; then
    echo "The two partitions must be of the same size: ${sizes[0]} MB and ${sizes[1]} MB."
    exit 1
fi

# Create Btrfs with the valid partitions
mkfs.btrfs -d raid1 -m raid1 --label "SecureGrubRaid1" --force --compress LZ0 "${partitions[@]}"

# Confirmation of creation
echo "Btrfs filesystem created on ${partitions[@]}."

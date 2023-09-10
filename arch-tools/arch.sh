#!/bin/bash
VERSION=1.0
# Modular Arch Installer
# Uses GPT partition scheme and only works with UEFI

# Exit error numbers
FDISK_ERROR=1
MOUNT_ERROR=2

# Important filepaths
ARCH_MOUNT_PATH=/mnt
ARCH_MOUNT_BOOT_PATH=$ARCH_MOUNT_PATH/boot
FSTAB_PATH=/etc/fstab

# Package lists
BASE_PACKAGES=("base" "linux" "linux-firmware")
CLI_TOOL_PACKAGES=("nano" "reflector")

# Helper functions for disk related actions

# Check if a disk exists.
# Usage:
#     is_disk path_to_disk
#             (ie /dev/sda)
is_disk() {
    test -e $1
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: disk doesn't exist." >&2
        exit $FDISK_ERROR
    fi
}

# Check if a partition exists, returns either 0 or 1
# Usage:
#     is_part path_to_partition
#               (ie /dev/sda2)
is_part() {
    test -e $1
    local is_disk=$?

    if [[ $is_disk == 0 ]]; then
        echo "Error: partition already exists." >&2
        exit $FDISK_ERROR
    fi
}

# Clear a disk's partition table and set the partition table to gpt.
# Usage:
#     clear_disk path_to_disk
#                (ie /dev/sda)
# Example:
#     clear_disk /dev/sda
clear_disk() {
    # Make sure two arguments were passed
    if [[ $# != 2 ]]; then
        echo "Error: clear_disk requires 2 arguements, $# was given." >&2
        exit $FDISK_ERROR
    fi

    # Arguments
    local disk_name=$1

    is_disk $disk_name

    (
    echo g
    echo w
    ) | fdisk $disk_name
}

# Create a partition and set its type, size, and number.
# Usage:
#     create_partition path_to_disk  number          type                          size
#                      (ie /dev/sda) (ie 1) (uefi, swap, ext4, ntfs) (ie 10G, default is to fill drive)
# Example:
#     create_partition /dev/sda ext4
#     create_partition /dev/sda uefi 1G
create_partition() {
    if [[ $# != 3 ]] && [[ $# != 4 ]]; then
        echo "Error: clear_partition requires either 3 or 4 arguements, $# was given." >&2
        exit $FDISK_ERROR
    fi

    # Arguments
    local disk_name=$1
    local part_num=$2
    local partition_type=${3,,}
    local part_size=""
    if [[ $4 ]]; then
        part_size="+$4"
    fi

    local part_types=("uefi" "swap" "ext4" "ntfs")
    local part_type_args=("uefi" "swap" "linux" "linux")
    local part_type=""

    for ((type = 0; type < ${#part_types[@]}; type++)); do
        if [[ $partition_type == ${part_types[$type]} ]]; then
            part_type=${part_type_args[$type]}
        fi
    done

    if [[ ! $part_type ]]; then
        echo "Error: partion type must be one of the following: ${partition_types[@]}" >&2
        exit $FDISK_ERROR
    fi

    is_disk $disk_name
    is_part $disk_name$part_num

    (
    echo n          # Create a new partition
    echo $part_num  # Specify the partition number
    echo            # Always start at the default sector
    echo $part_size # Add the alloted space
    echo w          # Write changes to the drive
    ) | fdisk $disk_name

    if [[ $partition_type == ${part_types[0]} ]]; then
        mkfs.fat -F32 -F $disk_name$part_num
    elif [[ $partition_type == ${part_types[1]} ]]; then
        mkswap -F $disk_name$part_num
    elif [[ $partition_type == ${part_types[2]} ]]; then
        mkfs.ext4 -F $disk_name$part_num
    elif [[ $partition_type == ${part_types[3]} ]]; then
        mkfs.ntfs -F $disk_name$part_num
    fi
}

# Mount the partitions for root, boot, and swap respectively.
# Usage:
#     mount_disks root_partition boot_partition   swap_partition
#                   (/dev/sda3)    (/dev/sda1)  (/dev/sda2 or none)
# Example:
#     mount_disks /dev/sda2 /dev/sda1
#     mount_disks /dev/sda3 /dev/sda1 /dev/sda2
mount_disks() {
    if [[ $# != 2 ]] && [[ $# != 3 ]]; then
        echo "Error: clear_partition requires either 2 or 3 arguements, $# was given." >&2
        exit $MOUNT_ERROR
    fi

    local root_part=$1
    local boot_part=$2
    local swap_part=$3

    mount $root_part $ARCH_MOUNT_PATH
    mount --mkdir $boot_part $ARCH_MOUNT_BOOT_PATH

    if [[ $swap_part ]]; then
        swapon $swap_part
    fi
}

# Generate the fstab file.
# Usage:
#     create_fstab
create_fstab() {
    genfstab -U $ARCH_MOUNT_PATH >> $ARCH_MOUNT_PATH$FSTAB_PATH
}


# Helper functions for pacman

# Update the mirrorlist using reflector and update the package databases.
# Usage:
#     update_pacman_mirrors
update_pacman_mirrors() {
    reflector -c "US" -f 12 -l 10 -n 12 -p "https" --threads 4 --save /etc/pacman.d/mirrorlist
    pacman -Syy
}

# Packstrap basic packages into the arch install.
install_base_pkgs() {
    pacstrap -K $ARCH_MOUNT_PATH ${BASE_PACKAGES[@]}
}

# enter an arch install
enter_install() {
    arch-chroot $ARCH_MOUNT_PATH
}

# exit arch install
exit_install() {
    exit
}

clear_disk /dev/sda GPT
create_partition /dev/sda 1 uefi 1G
create_partition /dev/sda 2 swap 4G
create_partition /dev/sda 3 ext4
update_pacman_mirrors
mount_disks /dev/sda3 /dev/sda1 /dev/sda2
install_base_pkgs
create_fstab
enter_install
exit_install

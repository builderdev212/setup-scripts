#!/bin/bash
VERSION=1.0
# Modular Arch Installer
# Uses GPT partition scheme and only works with UEFI

# Exit error numbers
FDISK_ERROR=1
MOUNT_ERROR=2
LOCALE_ERROR=3

# Important filepaths
ARCH_MOUNT_PATH=/mnt
ARCH_MOUNT_BOOT_PATH=$ARCH_MOUNT_PATH/boot
FSTAB_PATH=/etc/fstab

ZONE_INFO_PATH=$ARCH_MOUNT_PATH/usr/share/zoneinfo/
LOCALTIME_PATH=$ARCH_MOUNT_PATH/etc/localtime

LOCALE_CONF_PATH=$ARCH_MOUNT_PATH/etc/locale.conf

HOSTNAME_PATH=$ARCH_MOUNT_PATH/etc/hostname
HOSTS_PATH=$ARCH_MOUNT_PATH/etc/hosts

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

# chroot helper functions

# enter an arch install
enter_install() {
    arch-chroot $ARCH_MOUNT_PATH
}

# locale setup functions

# Setup timezone locales.
# Usage:
#     setup_locales     time_zone
#                   (America/New-York)
setup_time_locales() {
    local user_timezone=$1

    #timedatectl set-timezone $user_timezone
    ln -sf $ZONE_INFO_PATH/$user_timezone $LOCALTIME_PATH
    hwclock --systohc
}

# Copy locale.conf before chrooting into the install.
# Usage:
#     copy_locale_conf path_to_locale.conf
#                       (ie locale.conf)
copy_locale_conf() {
    local locale_path=$1

    if [ -e "$locale_path" ]; then
        cp $locale_path $LOCALE_CONF_PATH
    else
        exit $LOCALE_ERROR
    fi
}

# Setup locales.
setup_locales() {
    echo >&2
    locale-gen >&2
}

# Network setup functions.

# Setup the hostname for the computer.
# Usage:
#     setup_hostname  hostname
#                    (ie archvm)
setup_hostname() {
    local hostname=$1

    touch $HOSTNAME_PATH
    echo $hostname > $HOSTNAME_PATH
}

# Setup hosts file.
# Usage:
#     setup_hosts  hostname
#                 (ie archvm)
setup_hosts() {
    local hostname=$1

    echo >> "$HOSTS_PATH"
    echo "127.0.0.1 localhost" >> "$HOSTS_PATH"
    echo "::1       localhost" >> "$HOSTS_PATH"
    echo "127.0.1.1 $hostname" >> "$HOSTS_PATH"
}

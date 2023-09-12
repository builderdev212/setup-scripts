#!/bin/bash
VERSION=1.0
# Modular Arch Installer
# Uses GPT partition scheme and only works with UEFI

# Exit error numbers
FDISK_ERROR=1
MOUNT_ERROR=2
LOCALE_ERROR=3
NETWORK_ERROR=4
USER_ERROR=5

## Important Filepaths ##

# Disk related filepaths
ARCH_MOUNT_PATH="/mnt"
ARCH_MOUNT_BOOT_PATH="$ARCH_MOUNT_PATH/boot"
FSTAB_PATH="$ARCH_MOUNT_PATH/etc/fstab"

# Pacman related filepaths
PACMAN_MIRRORLIST_PATH="$ARCH_MOUNT_PATH/etc/pacman.d/mirrorlist"

# Locale related filepaths
ZONE_INFO_PATH="$ARCH_MOUNT_PATH/usr/share/zoneinfo/"
LOCALTIME_PATH="$ARCH_MOUNT_PATH/etc/localtime"
LOCALE_CONF_PATH="$ARCH_MOUNT_PATH/etc/locale.conf"

# Network related filepaths
HOSTNAME_PATH="$ARCH_MOUNT_PATH/etc/hostname"
HOSTS_PATH="$ARCH_MOUNT_PATH/etc/hosts"

## Package Lists ##
BASE_PACKAGES=("base" "linux" "linux-firmware")
CLI_TOOL_PACKAGES=("nano" "reflector")

## Disk Related Functions ##

# Clear a disk's partition table and set the partition table to gpt.
# Usage:
#     clear_disk path_to_disk
#                (ie /dev/sda)
function clear_disk() {
    # Make sure two arguments were passed
    if [[ $# != 1 ]]; then
        echo "Error: clear_disk requires 1 arguements, $# was given." >&2
        exit $FDISK_ERROR
    fi

    # Arguments
    local disk_name=$1

    # Ensure the disk exists.
    test -e $disk_name
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: disk doesn't exist." >&2
        exit $FDISK_ERROR
    fi

    (
    echo "g"
    echo "w"
    ) | fdisk $disk_name
}

# Create a partition and set its type, size, and number.
# Usage:
#     create_partition path_to_disk  number          type                          size
#                      (ie /dev/sda) (ie 1) (uefi, swap, ext4, ntfs) (ie 10G, default is to fill drive)
function create_partition() {
    if [[ $# != 3 ]] && [[ $# != 4 ]]; then
        echo "Error: create_partition requires either 3 or 4 arguements, $# was given." >&2
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

    # Ensure the disk exists.
    test -e $disk_name
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: disk doesn't exist." >&2
        exit $FDISK_ERROR
    fi

    # Ensure the partition doesn't already exist.
    test -e $disk_name$part_num
    local is_disk=$?

    if [[ $is_disk == 0 ]]; then
        echo "Error: partition already exists." >&2
        exit $FDISK_ERROR
    fi

    (
    echo "n"          # Create a new partition
    echo "$part_num"  # Specify the partition number
    echo              # Always start at the default sector
    echo "$part_size" # Add the alloted space
    echo "w"          # Write changes to the drive
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
function mount_disks() {
    if [[ $# != 2 ]] && [[ $# != 3 ]]; then
        echo "Error: mount_disks requires either 2 or 3 arguements, $# was given." >&2
        exit $MOUNT_ERROR
    fi

    local root_part=$1
    local boot_part=$2
    local swap_part=$3

    # Ensure the partitions exist.
    test -e $root_part
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: root partition doesn't exist." >&2
        exit $FDISK_ERROR
    fi

    test -e $boot_part
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: boot partition doesn't exist." >&2
        exit $FDISK_ERROR
    fi

    mount $root_part $ARCH_MOUNT_PATH
    mount --mkdir $boot_part $ARCH_MOUNT_BOOT_PATH

    if [[ $swap_part ]]; then
        test -e $swap_part
        local is_disk=$?

        if [[ $is_disk != 0 ]]; then
            echo "Error: swap partition doesn't exist." >&2
            exit $FDISK_ERROR
        fi

        swapon $swap_part
    fi
}

# Generate the fstab file.
# Usage:
#     create_fstab
function create_fstab() {
    genfstab -U $ARCH_MOUNT_PATH >> $ARCH_MOUNT_PATH$FSTAB_PATH
}

## Pacman Helper Functions ##

# Update the mirrorlist using reflector and update the package databases.
# Usage:
#     update_pacman_mirrors
function update_pacman_mirrors() {
    reflector -c "US" -f 12 -l 10 -n 12 -p "https" --save $PACMAN_MIRRORLIST_PATH
    pacman -Syy
}

# Packstrap basic packages into the arch install.
# Usage:
#     install_base_pkgs
function install_base_pkgs() {
    pacstrap -K $ARCH_MOUNT_PATH ${BASE_PACKAGES[@]}
}

## Locale Setup Functions ##

# Setup timezone locales.
# Usage:
#     setup_locales     time_zone
#                   (America/New-York)
function setup_time_locales() {
    if [[ $# != 1 ]]; then
        echo "Error: setup_time_locales requires 1 arguement, $# was given." >&2
        exit $LOCALE_ERROR
    fi

    local user_timezone=$1

    (
    ln -sf $ZONE_INFO_PATH/$user_timezone $LOCALTIME_PATH
    hwclock --systohc
    ) | arch-chroot $ARCH_MOUNT_PATH
}

# Copy locale.conf before chrooting into the install.
# Usage:
#     copy_locale_conf path_to_locale.conf
#                       (ie locale.conf)
function copy_locale_conf() {
    if [[ $# != 1 ]]; then
        echo "Error: copy_locale_conf requires 1 arguement, $# was given." >&2
        exit $LOCALE_ERROR
    fi

    local locale_path=$1

    if [ -e "$locale_path" ]; then
        cp $locale_path $LOCALE_CONF_PATH
    else
        echo "Error: $locale_path doesn't exist." >&2
        exit $LOCALE_ERROR
    fi
}

# Setup locales.
# Usage:
#     setup_locales
function setup_locales() {
    locale-gen >&2 | arch-chroot $ARCH_MOUNT_PATH
}

## Network Setup Functions ##

# Setup the hostname for the computer.
# Usage:
#     setup_hostname  hostname
#                    (ie archvm)
function setup_hostname() {
    if [[ $# != 1 ]]; then
        echo "Error: setup_hostname requires 1 arguement, $# was given." >&2
        exit $NETWORK_ERROR
    fi

    local hostname=$1

    echo $hostname > $HOSTNAME_PATH
}

# Setup hosts file.
# Usage:
#     setup_hosts
function setup_hosts() {
    local hostname=$(<$HOSTNAME_PATH)

    if [[ ! $hostname ]]; then
        echo "Error: No valid hostname found." >&2
        exit $NETWORK_ERROR
    fi

    echo >> $HOSTS_PATH
    echo "127.0.0.1 localhost" >> $HOSTS_PATH
    echo "::1       localhost" >> $HOSTS_PATH
    echo "127.0.1.1 $hostname" >> $HOSTS_PATH
}

# User setup functions

# Set a user's password.
# Usage:
#     set_pass   user
#              (ie root)
function set_pass() {
    if [[ $# != 1 ]]; then
        echo "Error: set_pass requires 1 arguement, $# was given." >&2
        exit $USER_ERROR
    fi

    local username=$1

    id "$username"
    local is_user=$?

    if [[ $is_user != 0 ]]; then
        echo "Error: User $username doesn't exist." >&2
        exit $USER_ERROR
    fi

    read -srp "Password($username): " password
    echo "$username:$password" | arch-chroot $ARCH_MOUNT_PATH chpasswd
    unset password
}

#!/bin/bash
# Modular Arch Installer
# Uses GPT partition scheme and only works with UEFI

# Exit error numbers
fdisk_error=1
mount_error=2
locale_error=3
network_error=4
user_error=5

## Important Filepaths ##

# Disk related filepaths
arch_mount_path="/mnt"
arch_mount_boot_path="$arch_mount_path/boot"
fstab_path="$arch_mount_path/etc/fstab"

# Pacman related filepaths
pacman_mirrorlist_path="$arch_mount_path/etc/pacman.d/mirrorlist"

# Locale related filepaths
zone_info_path="$arch_mount_path/usr/share/zoneinfo/"
localtime_path="$arch_mount_path/etc/localtime"
locale_conf_path="$arch_mount_path/etc/locale.conf"

# Network related filepaths
hostname_path="$arch_mount_path/etc/hostname"
hosts_path="$arch_mount_path/etc/hosts"

## Package Lists ##
base_packages=("base" "linux" "linux-firmware")
cli_tool_packages=("nano" "reflector")

## Disk Related Functions ##

# Clear a disk's partition table and set the partition table to gpt.
# Usage:
#     clearDisk path_to_disk
#               (ie /dev/sda)
function clearDisk() {
    # Make sure two arguments were passed
    if [[ $# != 1 ]]; then
        echo "Error: clearDisk requires 1 arguements, $# was given." >&2
        exit $fdisk_error
    fi

    local disk_name=$1

    # Ensure the disk exists.
    test -e "${disk_name}"
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: disk doesn't exist." >&2
        exit $fdisk_error
    fi

    (
    echo "g"
    echo "w"
    ) | fdisk "${disk_name}"
}

# Create a partition and set its type, size, and number.
# Usage:
#     createPartition path_to_disk  number          type                          size
#                     (ie /dev/sda) (ie 1) (uefi, swap, ext4, ntfs) (ie 10G, default is to fill drive)
function createPartition() {
    if [[ $# != 3 ]] && [[ $# != 4 ]]; then
        echo "Error: createPartition requires either 3 or 4 arguements, $# was given." >&2
        exit $fdisk_error
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
        if [[ $partition_type == "${part_types[$type]}" ]]; then
            part_type=${part_type_args[$type]}
        fi
    done

    if [[ ! $part_type ]]; then
        echo "Error: partion type must be one of the following: ${part_types[*]}" >&2
        exit $fdisk_error
    fi

    # Ensure the disk exists.
    test -e "${disk_name}"
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: disk doesn't exist." >&2
        exit $fdisk_error
    fi

    # Ensure the partition doesn't already exist.
    test -e "${disk_name}${part_num}"
    local is_disk=$?

    if [[ $is_disk == 0 ]]; then
        echo "Error: partition already exists." >&2
        exit $fdisk_error
    fi

    (
    echo "n"          # Create a new partition
    echo "${part_num}"  # Specify the partition number
    echo              # Always start at the default sector
    echo "${part_size}" # Add the alloted space
    echo "w"          # Write changes to the drive
    ) | fdisk "${disk_name}"

    case "${partition_type}" in
        "${part_types[0]}") mkfs.fat -F32 -F "${disk_name}${part_num}";;
        "${part_types[1]}") mkswap -F "${disk_name}${part_num}";;
        "${part_types[2]}") mkfs.ext4 -F "${disk_name}${part_num}";;
        "${part_types[3]}") mkfs.ntfs -F "${disk_name}${part_num}";;
    esac
}

# Mount the partitions for root, boot, and swap respectively.
# Usage:
#     mountDisks root_partition boot_partition   swap_partition
#                 (/dev/sda3)    (/dev/sda1)   (/dev/sda2 or none)
function mountDisks() {
    if [[ $# != 2 ]] && [[ $# != 3 ]]; then
        echo "Error: mountDisks requires either 2 or 3 arguements, $# was given." >&2
        exit $mount_error
    fi

    local root_part=$1
    local boot_part=$2
    local swap_part=$3

    # Ensure the partitions exist.
    test -e "${root_part}"
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: root partition doesn't exist." >&2
        exit $fdisk_error
    fi

    test -e "${boot_part}"
    local is_disk=$?

    if [[ $is_disk != 0 ]]; then
        echo "Error: boot partition doesn't exist." >&2
        exit $fdisk_error
    fi

    mount "${root_part}" $arch_mount_path
    mount --mkdir "${boot_part}" $arch_mount_boot_path

    if [[ $swap_part ]]; then
        test -e "${swap_part}"
        local is_disk=$?

        if [[ $is_disk != 0 ]]; then
            echo "Error: swap partition doesn't exist." >&2
            exit $fdisk_error
        fi

        swapon "${swap_part}"
    fi
}

# Generate the fstab file.
# Usage:
#     createFstab
function createFstab() {
    genfstab -U $arch_mount_path >> $fstab_path
}

## Pacman Helper Functions ##

# Update the mirrorlist using reflector and update the package databases.
# Usage:
#     updatePacmanMirrors
function updatePacmanMirrors() {
    reflector -c "US" -f 12 -l 10 -n 12 -p "https" --save $pacman_mirrorlist_path
    pacman -Syy
}

# Packstrap basic packages into the arch install.
# Usage:
#     installBasePackages
function installBasePackages() {
    pacstrap -K $arch_mount_path "${base_packages[@]}"
}

## Locale Setup Functions ##

# Setup timezone locales.
# Usage:
#     setupLocales      time_zone
#                   (America/New-York)
function setupTimeLocales() {
    if [[ $# != 1 ]]; then
        echo "Error: setupTimeLocales requires 1 arguement, $# was given." >&2
        exit $locale_error
    fi

    local user_timezone=$1

    (
    ln -sf "${zone_info_path}/${user_timezone}" $localtime_path
    hwclock --systohc
    ) | arch-chroot $arch_mount_path
}

# Copy locale.conf before chrooting into the install.
# Usage:
#     copyLocaleConf path_to_locale.conf
#                     (ie locale.conf)
function copyLocaleConf() {
    if [[ $# != 1 ]]; then
        echo "Error: copyLocaleConf requires 1 arguement, $# was given." >&2
        exit $locale_error
    fi

    local locale_path=$1

    if [ -e "${locale_path}" ]; then
        cp "${locale_path}" $locale_conf_path
    else
        echo "Error: ${locale_path} doesn't exist." >&2
        exit $locale_error
    fi
}

# Setup locales.
# Usage:
#     setupLocales
function setupLocales() {
    locale-gen >&2 | arch-chroot $arch_mount_path
}

## Network Setup Functions ##

# Setup the hostname for the computer.
# Usage:
#     setupHostname   hostname
#                    (ie archvm)
function setupHostname() {
    if [[ $# != 1 ]]; then
        echo "Error: setupHostname requires 1 arguement, $# was given." >&2
        exit $network_error
    fi

    local hostname=$1

    echo "${hostname}" > $hostname_path
}

# Setup hosts file.
# Usage:
#     setupHosts
function setupHosts() {
    local hostname=""

    hostname=$(<$hostname_path)

    if [[ ! $hostname ]]; then
        echo "Error: No valid hostname found." >&2
        exit $network_error
    fi

    (
    echo
    echo "127.0.0.1 localhost"
    echo "::1       localhost"
    echo "127.0.1.1 ${hostname}"
    ) >> $hosts_path
}

# User setup functions


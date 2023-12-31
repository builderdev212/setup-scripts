#!/bin/bash
# Modular Arch Installer
# Uses GPT partition scheme and only works with UEFI

# Exit error numbers
fdisk_error=1
mount_error=2
locale_error=3
network_error=4
boot_error=5
mkinitcpio_error=6
user_error=7

## Important Filepaths ##

# Disk related filepaths
arch_mount_path="/mnt"
arch_mount_boot_path="${arch_mount_path}/boot"
fstab_path="${arch_mount_path}/etc/fstab"

# Pacman related filepaths
pacman_mirrorlist_path="/etc/pacman.d/mirrorlist"

# Locale related filepaths
zone_info_path="/usr/share/zoneinfo/"
localtime_path="/etc/localtime"
locale_conf_path="${arch_mount_path}/etc/locale.conf"

# Network related filepaths
hostname_path="${arch_mount_path}/etc/hostname"
hosts_path="${arch_mount_path}/etc/hosts"

# rEFInd filepaths
refind_conf_path="${arch_mount_path}/boot/refind_linux.conf"

# mkinitcpio filepaths
mkinitcpio_conf_path="${arch_mount_path}/etc/mkinitcpio.conf"

# User filepaths
sudoer_path="${arch_mount_path}/etc/sudoers"

## URLS ##

yay_url="https://aur.archlinux.org/yay.git"

## Package Lists ##
linux_kernel="linux"
base_packages=("base" "$linux_kernel" "linux-firmware" "linux-headers")
refind_packages=("refind" "efibootmgr")
network_packages=("networkmanager")
filesystem_tools_packages=("mtools" "dosfstools")
aur_install_packages=("base-devel" "git")
mkinitcpio_packages=("aic94xx-firmware" "ast-firmware" "linux-firmware-bnx2x" "linux-firmware-liquidio" "linux-firmware-mellanox" "linux-firmware-nfp" "linux-firmware-qlogic" "upd72020x-fw" "wd719x-firmware")
user_packages=("sudo")
cli_tool_packages=("nano" "reflector")

## Microcode args ##
intel_microcode_package="intel-ucode"
intel_cpu_name="Intel"
amd_microcode_package="amd-ucode"
amd_cpu_name="AMD"

## rEFInd boot args ##
boot_args=("rw" "add_efi_memmap")
intel_microcode_arg="initrd=${intel_microcode_package}.img"
amd_microcode_arg="initrd=${amd_microcode_package}.img"
default_boot_args=("initrd=initramfs-$linux_kernel.img")
fallback_boot_args=("initrd=initramfs-$linux_kernel-fallback.img")
terminal_boot_args=("systemd.unit=multi-user.target")

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

    # unmount any partitions
    mountpoint $arch_mount_boot_path
    local is_mounted=$?

    if [[ $is_mounted == 0 ]]; then
        umount $arch_mount_boot_path
    fi

    mountpoint $arch_mount_path
    local is_mounted=$?

    if [[ $is_mounted == 0 ]]; then
        umount $arch_mount_path
    fi

    swapoff -a

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

    # Create the partition
    (
    echo "n"          # Create a new partition
    echo "${part_num}"  # Specify the partition number
    echo              # Always start at the default sector
    echo "${part_size}" # Add the alloted space
    echo "w"          # Write changes to the drive
    ) | fdisk "${disk_name}"

    # Set the partition type
    if [[ $(partx -g "${disk_name}" | wc -l) == 1 ]]; then
        (
        echo "t"
        echo "${part_type}"
        echo "w"
        ) | fdisk "${disk_name}"
    else
        (
        echo "t"
        echo "${part_num}"
        echo "${part_type}"
        echo "w"
        ) | fdisk "${disk_name}"
    fi

    case "${partition_type}" in
        "${part_types[0]}") mkfs.fat -F32 "${disk_name}${part_num}";;
        "${part_types[1]}") mkswap -f "${disk_name}${part_num}";;
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

    mount "${root_part}" --mkdir $arch_mount_path
    mount "${boot_part}" --mkdir $arch_mount_boot_path

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
}

# Packstrap basic packages into the arch install.
# Usage:
#     installBasePackages
function installBasePackages() {
    pacstrap $arch_mount_path "${base_packages[@]}"
    echo "pacman -Syyu --noconfirm" | arch-chroot $arch_mount_path
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
    echo "ln -sf ${zone_info_path}/${user_timezone} $localtime_path"
    echo "hwclock --systohc"
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
    echo "locale-gen" | arch-chroot $arch_mount_path
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

# Setup network manager.
# Usage:
#     setupNetworkManager
function setupNetworkManager() {
    local network_manager_service="NetworkManager.service"

    (
    echo "pacman -S ${network_packages[*]} --noconfirm"
    echo "systemctl enable $network_manager_service"
    ) | arch-chroot $arch_mount_path
}

## Bootloader Setup Functions ##

# Setup rEFInd boot manager.
# Usage:
#     setupRefind
function setupRefind() {
    local boot_part=""

    boot_part=$(lsblk -no NAME,MOUNTPOINTS | grep -E "${arch_mount_boot_path}$" | grep -oE ".* ")
    boot_part=${boot_part:2:-1}

    (
    echo "pacman -Sy ${refind_packages[*]} ${filesystem_tools_packages[*]} --noconfirm"
    echo "refind-install"
    ) | arch-chroot $arch_mount_path

    installMicrocode
    generateRefindConf
}

# Dectect CPU brand and install proper microcode.
# Usage:
#     installMicrocode
function installMicrocode() {
    is_intel=$(lscpu | grep -E "Vendor ID" | grep -oE $intel_cpu_name)
    is_amd=$(lscpu | grep -E "Vendor ID" | grep -oE $amd_cpu_name)

    if [[ $is_intel == "${intel_cpu_name}" ]]; then
        (
        echo "pacman -Sy ${intel_microcode_package} --noconfirm"
        )  | arch-chroot $arch_mount_path
    elif [[ $is_amd == "${amd_cpu_name}" ]]; then
        (
        echo "pacman -Sy ${amd_microcode_package} --noconfirm"
        )  | arch-chroot $arch_mount_path
    else
        echo "Error: CPU Detected was neither AMD or Intel." >&2
        exit $boot_error
    fi
}

# Setup refind_linux.conf file
# Usage:
#     generateRefindConf
function generateRefindConf() {
    local root_part=""
    root_part=$(lsblk -no NAME,MOUNTPOINTS | grep -E "${arch_mount_path}$" | grep -oE ".* ")
    root_part=${root_part:2:-1}

    local root_uuid=""
    root_uuid=$(blkid -s UUID -o value "/dev/${root_part}")

    local microcode_arg=""

    is_intel=$(lscpu | grep -E "Vendor ID" | grep -oE $intel_cpu_name)
    is_amd=$(lscpu | grep -E "Vendor ID" | grep -oE $amd_cpu_name)

    if [[ $is_intel == "${intel_cpu_name}" ]]; then
        microcode_arg=$intel_microcode_arg
    elif [[ $is_amd == "${amd_cpu_name}" ]]; then
        microcode_arg=$amd_microcode_arg
    else
        echo "Error: CPU Detected was neither AMD or Intel." >&2
        exit $boot_error
    fi

    (
    echo "\"Boot with minimal options\"   \"root=UUID=${root_uuid} ${boot_args[*]} ${microcode_arg} ${default_boot_args[*]}\""
    echo "\"Boot with fallback options\"   \"root=UUID=${root_uuid} ${boot_args[*]} ${microcode_arg} ${fallback_boot_args[*]}\""
    echo "\"Boot to the terminal\"   \"root=UUID=${root_uuid} ${boot_args[*]} ${microcode_arg} ${default_boot_args[*]} ${terminal_boot_args[*]}\""
    ) > $refind_conf_path
}

## Base Setup Functions ##

# Setup yay AUR helper
# Usage:
#     installYay user
#                (ex. myuser)
function installYay() {
     if [[ $# != 1 ]]; then
        echo "Error: installYay requires 1 arguement, $# was given." >&2
        exit $user_error
    fi

    local username=$1

    if [[ -e $(id -u "${username}") ]] ; then
        echo "Error: \"${username}\" doesn't exist." >&2
        exit $user_error
    fi

    (
    echo "pacman -Sy --needed ${aur_install_packages[*]} --noconfirm"
    echo "su ${username}"
    echo "cd ~"
    echo "git clone ${yay_url}"
    echo "cd ~/yay"
    echo "makepkg -si --noconfirm"
    echo "cd .."
    echo "rm -rf yay"
    echo "exit"
    echo "cd /"
    ) | arch-chroot $arch_mount_path
}

## User Setup Functions ##

# Install packages needed for users
# Usage:
#     installUserPackages
function installUserPackages() {
    (
    echo "pacman -Sy --needed ${user_packages[*]} --noconfirm"
    ) | arch-chroot $arch_mount_path
}

# Setup a new user.
# Usage:
#     createUser username    --sudo
#                (ie myuser) (optional)
function createUser() {
    if [[ $# != 1 ]] && [[ $# != 2 ]]; then
        echo "Error: createUser requires either 1 or 2 arguements, $# was given." >&2
        exit $user_error
    fi

    local admin_arg="--sudo"

    if [[ $# == 1 ]] && [[ $1 == "${admin_arg}" ]]; then
        echo "Error: No username was given." >&2
        exit $user_error
    fi

    if [[ $# == 2 ]] && [[ $2 != "${admin_arg}" ]]; then
        echo "Error: Expected ${admin_arg}, got $2." >&2
        exit $user_error
    fi

    local username=$1
    local is_sudo=$2

    (
    echo "useradd -m ${username}"
    ) | arch-chroot $arch_mount_path

    if [[ $is_sudo == "${admin_arg}" ]]; then
        echo "${username}  ALL=(ALL:ALL) NOPASSWD: ALL" >> $sudoer_path
    fi
}

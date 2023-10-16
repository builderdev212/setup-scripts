#!/bin/bash
# Modular Arch Installer
# Uses GPT partition scheme and only works with UEFI

# Exit error numbers
mkinitcpio_error=6

## Important Filepaths ##

# mkinitcpio filepaths
mkinitcpio_conf_path="/etc/mkinitcpio.conf"

## Package Lists ##
mkinitcpio_packages=("aic94xx-firmware" "ast-firmware" "linux-firmware-bnx2x" "linux-firmware-liquidio" "linux-firmware-mellanox" "linux-firmware-nfp" "linux-firmware-qlogic" "upd72020x-fw" "wd719x-firmware")

# Setup the initramfs
# Usage:
#     setupmkinitcpio path_to_mkinitcpio.conf
#                      (ie mkinitcpio.conf)
function setupmkinitcpio() {
    if [[ $# != 1 ]]; then
        echo "Error: setupmkinitcpio requires 1 arguement, $# was given." >&2
        exit $mkinitcpio_error
    fi

    local conf_path=$1

    if [ -e "${conf_path}" ]; then
        sudo cp "${conf_path}" $mkinitcpio_conf_path
    else
        echo "Error: ${conf_path} doesn't exist." >&2
        exit $mkinitcpio_error
    fi

    yay -Sy "${mkinitcpio_packages[@]}" --noconfirm
    sudo mkinitcpio -P
}

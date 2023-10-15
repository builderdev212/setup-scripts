#!/bin/bash

# You still have to set passwords manually.

source "$(dirname "$0")/arch.sh"

# fix this later for nvme/usb for boot
clearDisk /dev/sda
createPartition /dev/sda 1 uefi 1G
createPartition /dev/sda 2 swap 4G
createPartition /dev/sda 3 ext4
mountDisks /dev/sda3 /dev/sda1 /dev/sda2
updatePacmanMirrors
installBasePackages
createFstab
copyLocaleConf locale.conf
setupTimeLocales "America/New-York"
setupLocales
setupHostname silencer
setupHosts
setupRefind
setupNetworkManager
installUserPackages
createUser builder --sudo
installYay builder


# Run these after this script finishes:
#     arch-chroot /mnt
#     passwd
#     passwd builder

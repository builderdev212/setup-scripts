#!/bin/bash

source "$(dirname "$0")/arch.sh"

clearDisk /dev/sda
createPartition /dev/sda 1 uefi 1G
createPartition /dev/sda 2 swap 4G
createPartition /dev/sda 3 ext4
updatePacmanMirrors
mountDisks /dev/sda3 /dev/sda1 /dev/sda2
installBasePackages
createFstab
copyLocaleConf locale.conf
setupTimeLocales "America/New-York"
setupLocales
setupHostname archvm
setupHosts

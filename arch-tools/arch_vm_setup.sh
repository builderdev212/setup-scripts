#!/bin/bash

source $(dirname $0)/arch.sh

clear_disk /dev/sda GPT
create_partition /dev/sda 1 uefi 1G
create_partition /dev/sda 2 swap 4G
create_partition /dev/sda 3 ext4
update_pacman_mirrors
mount_disks /dev/sda3 /dev/sda1 /dev/sda2
install_base_pkgs
create_fstab
copy_locale_conf locale.conf
(
setup_time_locales America/New-York
setup_locales
setup_hostname archvm
setup_hosts archvm
) | enter_install

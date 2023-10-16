#!/bin/bash

# I'm running this directly after I reboot into my arch vm and log in.

source "$(dirname "$0")/../../arch-tools/after_installer/arch_after_install.sh"

setupmkinitcpio mkinitcpio.conf

#!/bin/bash

source "$(dirname "$0")/../../arch-tools/after_installer/arch_after_install.sh"

setupmkinitcpio mkinitcpio.conf

#!/bin/bash

source "$(dirname "$0")/arch_after_install.sh"

setupmkinitcpio mkinitcpio.conf

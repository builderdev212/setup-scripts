#!/bin/bash
VERSION=1.0
# fdisk automation tools

get_disks() {
    readarray -d '' -t disks < <( fdisk -l | grep -zP 'Disk /dev/' )
    echo ${#disks[@]}
}

get_disks

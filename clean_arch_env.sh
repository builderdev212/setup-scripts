#!/bin/bash
# Simple tool to create a test arch virtual machine with QEMU.

# Script arguments
BUILD_ARG="-b"
RUN_ARG="-r"
RUN_INSTALLER_ARG="-ri"
CLEAN_ARG="-c"

# Path variables
IMAGE_NAME="clean_arch"
PATH_OF_SCRIPT="$PWD"
PATH_OF_INSTALLER="$PWD/installers/archlinux.iso"
TOOL_PATH="$PWD/arch-tools"

# UEFI Paths
UEFI_PATH="/usr/share/edk2-ovmf/x64"
OVMF_CODE="$UEFI_PATH/OVMF_CODE.fd"
OG_OVMF_VARS="$UEFI_PATH/OVMF_VARS.fd"
OVMF_VARS="$PATH_OF_SCRIPT/$IMAGE_NAME/OVMF_VARS.fd"

# VM Parameters
# All sizes are in GB
DRIVE_SIZE="30"
RAM_SIZE="32"
CORE_NUM="14"

# Helper functions

# Setup VM directory
setup_path() {
    echo "Creating directory..."

    if [[ -d $PATH_OF_SCRIPT/$IMAGE_NAME ]]; then
        echo "Error: directory \"$PATH_OF_SCRIPT/$IMAGE_NAME/\" already exists."
        exit 1
    else
        mkdir "$PATH_OF_SCRIPT/$IMAGE_NAME"
    fi

    echo "Copying UEFI vars..."
    cp $OG_OVMF_VARS "$OVMF_VARS"
    chmod u=rw,g=rw,o=rw "$OVMF_VARS"
#     cp $OG_OVMF "$OVMF"
}

# Create virtual drive
make_drive() {
    echo "Creating virtual ${DRIVE_SIZE}GB drive..."

    if [[ -e $PATH_OF_SCRIPT/$IMAGE_NAME/drive.cow ]]; then
        echo "Error: $PATH_OF_SCRIPT/$IMAGE_NAME/drive.cow already exists."
        exit 1
    else
        qemu-img create -f qcow2 "$PATH_OF_SCRIPT/$IMAGE_NAME/drive.cow" ${DRIVE_SIZE}G
    fi
}

# Option functions
build() {
    echo "Building..."
    setup_path
    make_drive
}

run() {
    echo "Running..."
    qemu-system-x86_64 -boot c \
                       -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
                       -drive if=pflash,format=raw,file="$OVMF_VARS" \
                       -drive file="$PATH_OF_SCRIPT/$IMAGE_NAME/drive.cow" \
                       -machine q35 \
                       -enable-kvm \
                       -device intel-iommu,caching-mode=on \
                       -cpu max \
                       -smp cores=$CORE_NUM \
                       -vga virtio \
                       -m ${RAM_SIZE}G
}

run_installer() {
    echo "Entering install environment..."
    qemu-system-x86_64 -boot d \
                       -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
                       -drive if=pflash,format=raw,file="$OVMF_VARS" \
                       -cdrom "$PATH_OF_INSTALLER" \
                       -drive file="$PATH_OF_SCRIPT/$IMAGE_NAME/drive.cow" \
                       -virtfs local,path="$TOOL_PATH",mount_tag=host0,security_model=passthrough,id=host0 \
                       -machine q35 \
                       -enable-kvm \
                       -device intel-iommu,caching-mode=on \
                       -cpu max \
                       -smp cores=$CORE_NUM \
                       -vga virtio \
                       -m ${RAM_SIZE}G
}
# Run mount -t 9p host0 --mkdir test

clean() {
    echo "Cleaning environment..."
    rm -r "${PATH_OF_SCRIPT:?}/$IMAGE_NAME"
}

# Make sure one and only one argument was passed.
if [[ -e $2 ]]; then
    echo "Error: more than one arguement was passed."
    exit 1
elif [[ -z $1 ]]; then
    echo "Error: either -b, -r, or -c must be passed."
    exit 1
fi

# Option runs
if [[ $1 == "$BUILD_ARG" ]]; then
    build
elif [[ $1 == "$RUN_ARG" ]]; then
    run
elif [[ $1 == "$RUN_INSTALLER_ARG" ]]; then
    run_installer
elif [[ $1 == "$CLEAN_ARG" ]]; then
    clean
else
    echo "Error: invalid arguement, either -b, -r, or -c must be passed."
    exit 1
fi

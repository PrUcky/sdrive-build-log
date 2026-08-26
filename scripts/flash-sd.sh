#!/usr/bin/env bash
# ==============================================================================
# flash-sd.sh — Safe MicroSD Flashing Script for Armbian on Radxa ROCK 3C
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$#" -ne 2 ]; then
    echo "Usage: sudo $0 <path_to_armbian_image.img> <target_block_device>"
    echo "Example: sudo $0 Armbian_24.5.1_Rock-3c_bookworm_current_6.6.x.img /dev/sdb"
    exit 1
fi

IMAGE_PATH=$1
TARGET_DEV=$2

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo $0 ...)${NC}"
    exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
    echo -e "${RED}Error: Image file not found at $IMAGE_PATH${NC}"
    exit 1
fi

if [ ! -b "$TARGET_DEV" ]; then
    echo -e "${RED}Error: Target device $TARGET_DEV is not a valid block device.${NC}"
    exit 1
fi

# Safety check: prevent overwriting primary NVMe or SDA root drive
if [[ "$TARGET_DEV" =~ nvme[0-9]n1$ ]] || [[ "$TARGET_DEV" =~ sda$ ]]; then
    echo -e "${RED}SAFETY ALERT: $TARGET_DEV appears to be a primary system disk! Refusing to flash.${NC}"
    exit 1
fi

echo "======================================================================"
echo -e "${YELLOW}WARNING: ALL DATA ON $TARGET_DEV WILL BE COMPLETELY DESTROYED!${NC}"
echo "Image Source: $IMAGE_PATH"
echo "Target Device: $TARGET_DEV"
lsblk "$TARGET_DEV"
echo "======================================================================"
read -rp "Type 'FLASH' in all caps to confirm and proceed: " CONFIRM

if [ "$CONFIRM" != "FLASH" ]; then
    echo "Aborted by user."
    exit 0
fi

echo -e "\n--> Unmounting any active partitions on $TARGET_DEV..."
umount "${TARGET_DEV}"* 2>/dev/null || true

if command -v bmaptool &>/dev/null && [ -f "${IMAGE_PATH}.bmap" ]; then
    echo -e "\n--> Flashing image using accelerated bmaptool..."
    bmaptool copy "$IMAGE_PATH" "$TARGET_DEV"
else
    echo -e "\n--> Flashing image using raw dd with status progress..."
    dd if="$IMAGE_PATH" of="$TARGET_DEV" bs=4M status=progress conv=fsync oflag=direct
fi

echo -e "\n--> Flushing disk buffers..."
sync

echo -e "\n======================================================================"
echo -e "${GREEN}SUCCESS: MicroSD card flashed successfully!${NC}"
echo "Insert the card into your Radxa ROCK 3C, connect serial UART, and apply power."
echo "======================================================================"

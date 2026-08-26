#!/usr/bin/env bash
# ==============================================================================
# serial-console.sh — Automated UART Serial Console Launcher for Rockchip RK3566
# ==============================================================================
set -euo pipefail

BAUD_RATE="1500000"

# Auto-detect serial USB adapter
SERIAL_DEV=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -n 1 || echo "")

if [ -z "$SERIAL_DEV" ]; then
    echo "Error: No USB-to-UART serial adapter detected on /dev/ttyUSB* or /dev/ttyACM*."
    echo "Please ensure your CP2102/FTDI bridge is plugged in."
    exit 1
fi

echo "======================================================================"
echo " Connecting to Rockchip UART Serial Console"
echo " Target Device: $SERIAL_DEV"
echo " Baud Rate:     $BAUD_RATE (8-N-1)"
echo " Exit shortcut: Ctrl+A followed by Ctrl+X (in picocom)"
echo "======================================================================"

if command -v picocom &>/dev/null; then
    exec picocom -b "$BAUD_RATE" "$SERIAL_DEV"
elif command -v minicom &>/dev/null; then
    exec minicom -D "$SERIAL_DEV" -b "$BAUD_RATE" -8 -N
elif command -v screen &>/dev/null; then
    exec screen "$SERIAL_DEV" "$BAUD_RATE"
else
    echo "Error: Neither picocom, minicom, nor screen is installed."
    echo "Install picocom via: sudo apt install picocom"
    exit 1
fi

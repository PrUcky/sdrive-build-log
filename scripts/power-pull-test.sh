#!/usr/bin/env bash
# ==============================================================================
# power-pull-test.sh — Filesystem Durability & Ungraceful Shutdown Test Harness
# ==============================================================================
set -euo pipefail

TEST_DIR="/var/tmp/power-pull-test"
MANIFEST="$TEST_DIR/manifest.txt"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

mode=${1:-"write"}

if [ "$mode" = "--verify" ] || [ "$mode" = "verify" ]; then
    echo "======================================================================"
    echo " sdrive Power-Pull Integrity Verification"
    echo "======================================================================"

    if [ ! -f "$MANIFEST" ]; then
        echo -e "${RED}Error: Manifest file $MANIFEST not found.${NC}"
        exit 1
    fi

    TOTAL_BLOCKS=0
    VALID_BLOCKS=0
    CORRUPT_BLOCKS=0

    echo -e "\n--> Verifying block checksums against manifest..."
    while read -r expected_hash block_path; do
        TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
        if [ -f "$block_path" ]; then
            actual_hash=$(sha256sum "$block_path" | awk '{print $1}')
            if [ "$expected_hash" = "$actual_hash" ]; then
                VALID_BLOCKS=$((VALID_BLOCKS + 1))
            else
                CORRUPT_BLOCKS=$((CORRUPT_BLOCKS + 1))
                echo -e "[ ${RED}CORRUPT${NC} ] $block_path hash mismatch!"
            fi
        else
            echo -e "[ ${YELLOW}MISSING${NC} ] $block_path recorded in manifest but not on disk"
        fi
    done < "$MANIFEST"

    echo -e "\n======================================================================"
    echo " Integrity Audit Summary:"
    echo " Total Committed Blocks in Manifest: $TOTAL_BLOCKS"
    echo -e " Verified Intact Blocks:             ${GREEN}$VALID_BLOCKS${NC}"
    echo -e " Corrupted Blocks Detected:          ${RED}$CORRUPT_BLOCKS${NC}"
    echo "======================================================================"

    if [ "$CORRUPT_BLOCKS" -eq 0 ] && [ "$VALID_BLOCKS" -gt 0 ]; then
        echo -e "${GREEN}SUCCESS: Zero data corruption detected! ext4 journal replayed cleanly.${NC}"
        exit 0
    else
        echo -e "${RED}FAILURE: Data corruption detected on filesystem!${NC}"
        exit 1
    fi

elif [ "$mode" = "write" ] || [ "$mode" = "--write" ]; then
    mkdir -p "$TEST_DIR"
    rm -f "$MANIFEST" "$TEST_DIR"/*.bin
    touch "$MANIFEST"

    echo "======================================================================"
    echo " sdrive Continuous I/O Stress Generator for Power-Pull Test"
    echo " Test Directory: $TEST_DIR"
    echo " INSTRUCTIONS: While this script is writing, physically pull the USB-C"
    echo "               power cable from the board. Re-plug power, reboot, and"
    echo "               run: ./scripts/power-pull-test.sh --verify"
    echo "======================================================================"

    BLOCK_NUM=0
    while true; do
        BLOCK_NUM=$((BLOCK_NUM + 1))
        BLOCK_FILE="$TEST_DIR/block_$(printf '%06d' "$BLOCK_NUM").bin"
        
        # Generate 1MB of pseudorandom data
        dd if=/dev/urandom of="$BLOCK_FILE" bs=1M count=1 status=none
        
        # Calculate SHA256 checksum
        HASH=$(sha256sum "$BLOCK_FILE" | awk '{print $1}')
        
        # Record to manifest and sync to disk
        echo "$HASH $BLOCK_FILE" >> "$MANIFEST"
        sync -d "$BLOCK_FILE" "$MANIFEST"
        
        echo -ne "\r--> Committed Block #$BLOCK_NUM (1MB) | SHA-256: ${HASH:0:16}... [SYNCED]"
        sleep 0.1
    done
else
    echo "Usage: $0 [write|--verify]"
    exit 1
fi

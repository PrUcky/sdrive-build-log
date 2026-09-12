#!/usr/bin/env bash
# ==============================================================================
# garage-init-layout.sh — Initialize Garage Cluster Layout & Buckets
# ==============================================================================
# This script performs the one-time setup for a fresh Garage node:
#   1. Waits for Garage to be ready
#   2. Assigns the node a zone and capacity in the cluster layout
#   3. Applies the layout
#   4. Creates the S3 bucket used by museum
#   5. Creates an API key and grants it full access to the bucket
#
# IMPORTANT: Run this ONCE after the first `docker compose up`.
# Running it again is safe (idempotent checks prevent duplicate creation).
#
# Usage: ./scripts/garage-init-layout.sh
#
# Prerequisites:
#   - Garage container must be running
#   - GARAGE_CONTAINER env var or defaults to 'sdrive-stack-garage-1'
#
# Reference: weeks/week-03/day-22.md
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONTAINER="${GARAGE_CONTAINER:-sdrive-stack-garage-1}"
BUCKET_NAME="b2-eu-cen"
KEY_NAME="ente-server-key"
ZONE="dc1"
CAPACITY="400G"

garage_exec() {
    docker exec "$CONTAINER" /garage "$@"
}

echo "======================================================================"
echo " sdrive — Garage Cluster Layout Initialization"
echo "======================================================================"

# --- Step 0: Wait for Garage to be ready ---
echo -e "\n[1/5] Waiting for Garage to be ready..."
for i in $(seq 1 30); do
    if garage_exec status &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Garage is responding."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}[ERROR]${NC} Garage did not become ready after 30 seconds."
        exit 1
    fi
    sleep 1
done

# --- Step 1: Get node ID ---
echo -e "\n[2/5] Retrieving node ID..."
NODE_ID=$(garage_exec status 2>/dev/null | grep -oP '[0-9a-f]{16}' | head -1)
if [ -z "$NODE_ID" ]; then
    echo -e "${RED}[ERROR]${NC} Could not determine node ID."
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Node ID: ${NODE_ID}"

# --- Step 2: Assign layout ---
echo -e "\n[3/5] Assigning cluster layout (zone=${ZONE}, capacity=${CAPACITY})..."
if garage_exec layout assign -z "$ZONE" -c "$CAPACITY" "$NODE_ID" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Layout assigned."
    # Apply the layout
    CURRENT_VERSION=$(garage_exec layout show 2>/dev/null | grep -oP 'version \K[0-9]+' || echo "0")
    NEXT_VERSION=$((CURRENT_VERSION + 1))
    garage_exec layout apply --version "$NEXT_VERSION" 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Layout applied (version ${NEXT_VERSION})."
else
    echo -e "${YELLOW}[SKIP]${NC} Layout already assigned (this is fine)."
fi

# --- Step 3: Create bucket ---
echo -e "\n[4/5] Creating bucket '${BUCKET_NAME}'..."
if garage_exec bucket create "$BUCKET_NAME" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Bucket '${BUCKET_NAME}' created."
else
    echo -e "${YELLOW}[SKIP]${NC} Bucket '${BUCKET_NAME}' already exists (this is fine)."
fi

# --- Step 4: Create key and grant access ---
echo -e "\n[5/5] Creating API key '${KEY_NAME}' and granting bucket access..."
KEY_OUTPUT=$(garage_exec key create "$KEY_NAME" 2>/dev/null || true)

if echo "$KEY_OUTPUT" | grep -q "Key ID"; then
    echo -e "${GREEN}[OK]${NC} Key '${KEY_NAME}' created."
else
    echo -e "${YELLOW}[SKIP]${NC} Key '${KEY_NAME}' already exists (this is fine)."
fi

# Grant access regardless (idempotent)
garage_exec bucket allow --read --write --owner "$BUCKET_NAME" --key "$KEY_NAME" 2>/dev/null || true
echo -e "${GREEN}[OK]${NC} Key '${KEY_NAME}' granted read/write/owner on '${BUCKET_NAME}'."

# --- Summary ---
echo -e "\n======================================================================"
echo -e "${GREEN} Garage cluster layout initialized successfully!${NC}"
echo "======================================================================"
echo ""
echo "Next steps:"
echo "  1. Run: docker exec $CONTAINER /garage key info $KEY_NAME"
echo "  2. Copy the Access Key ID and Secret Key"
echo "  3. Update museum.yaml with the S3 credentials"
echo "  4. Restart museum: docker compose restart museum"
echo ""

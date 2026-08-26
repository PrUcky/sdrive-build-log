#!/usr/bin/env bash
# ==============================================================================
# verify-env.sh — sdrive Toolchain and Environment Sanity Checker
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================================================"
echo " sdrive Build Environment Sanity Verification"
echo "======================================================================"

check_tool() {
    local tool=$1
    local required=$2
    if command -v "$tool" &>/dev/null; then
        local version
        version=$("$tool" --version 2>&1 | head -n 1 || echo "installed")
        echo -e "[ ${GREEN}OK${NC} ] $tool ($version)"
    else
        if [ "$required" = "true" ]; then
            echo -e "[ ${RED}MISSING${NC} ] $tool (REQUIRED)"
            exit 1
        else
            echo -e "[ ${YELLOW}OPTIONAL${NC} ] $tool (Recommended for future weeks)"
        fi
    fi
}

echo -e "\n--> Checking Host Administrative Toolchain..."
check_tool ssh true
check_tool ssh-keygen true
check_tool openssl true
check_tool curl true
check_tool git true
check_tool gitleaks false

echo -e "\n--> Checking Hardware Bring-up & Serial Utilities..."
check_tool picocom false
check_tool minicom false
check_tool bmaptool false

echo -e "\n--> Checking Benchmarking Utilities..."
check_tool fio false
check_tool iperf3 false
check_tool stress-ng false

echo -e "\n--> Checking SSH Keypair Status..."
if [ -f "$HOME/.ssh/id_ed25519" ]; then
    echo -e "[ ${GREEN}OK${NC} ] Local Ed25519 keypair found ($HOME/.ssh/id_ed25519)"
else
    echo -e "[ ${YELLOW}WARNING${NC} ] No Ed25519 keypair found at $HOME/.ssh/id_ed25519. Run ssh-keygen -t ed25519."
fi

echo -e "\n======================================================================"
echo -e "${GREEN}All critical environment prerequisites verified successfully!${NC}"
echo "======================================================================"

#!/usr/bin/env bash
# ==============================================================================
# setup-gitleaks-hook.sh - Installs a local pre-commit hook for Gitleaks
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOOK_FILE=".git/hooks/pre-commit"

echo "======================================================================"
echo " sdrive Gitleaks Pre-Commit Hook Installer"
echo "======================================================================"

if ! command -v gitleaks &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} gitleaks is not installed on this system."
    echo -e "Please install it first: https://github.com/gitleaks/gitleaks#install"
    exit 1
fi

cat << 'EOF' > "$HOOK_FILE"
#!/usr/bin/env bash
# Gitleaks pre-commit hook
echo "[gitleaks] Scanning staged changes for secrets..."
if ! gitleaks protect -v --staged; then
    echo "[gitleaks] FATAL: Secrets detected in staged changes! Commit aborted."
    echo "[gitleaks] If this is a false positive, use: git commit --no-verify"
    exit 1
fi
echo "[gitleaks] Scan passed."
EOF

chmod +x "$HOOK_FILE"

echo -e "${GREEN}[OK]${NC} Pre-commit hook installed at $HOOK_FILE"
echo "Gitleaks will now automatically scan all staged changes before allowing a commit."

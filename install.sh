#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Salesforce MCP Connector Installer for Claude Desktop
# ─────────────────────────────────────────────────────────────

REPO_URL="https://github.com/SponsorUnited-Vibez/MCP-Salesforce.git"
INSTALL_DIR="$HOME/Library/Application Support/Claude/MCP-Salesforce"

echo "=============================================="
echo "  Salesforce Connector Installer for Claude"
echo "=============================================="
echo ""

# ── Step 1: Check / Install Python ──────────────────────────
echo "[1/5] Checking Python installation..."

if ! command -v python3 &>/dev/null; then
    echo ""
    echo "Python 3 is not installed."
    echo "macOS will now prompt you to install Developer Tools."
    echo "This can take 10-15 minutes. Please wait for it to finish."
    echo ""
    xcode-select --install 2>/dev/null || true
    echo "Press Enter once the Developer Tools installation is complete..."
    read -r
    if ! command -v python3 &>/dev/null; then
        echo "ERROR: Python 3 still not found. Please install it manually and re-run this script."
        exit 1
    fi
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo "  Found: $PYTHON_VERSION"

# ── Step 1b: Check / Install Git ─────────────────────────────
echo ""
echo "[1b/5] Checking Git installation..."

if ! command -v git &>/dev/null; then
    echo ""
    echo "Git is not installed."
    echo "macOS will now prompt you to install Developer Tools (includes Git)."
    echo "This can take 10-15 minutes. Please wait for it to finish."
    echo ""
    xcode-select --install 2>/dev/null || true
    echo "Press Enter once the Developer Tools installation is complete..."
    read -r
    if ! command -v git &>/dev/null; then
        echo "ERROR: Git still not found. Please install it manually and re-run this script."
        exit 1
    fi
fi

echo "  Found: $(git --version 2>&1)"

# ── Step 2: Install uv ──────────────────────────────────────
echo ""
echo "[2/5] Installing uv..."

if command -v uv &>/dev/null; then
    echo "  uv is already installed: $(uv --version 2>&1)"
else
    if command -v curl &>/dev/null; then
        echo "  Installing uv via official installer..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    else
        echo "  Installing uv via pip3..."
        pip3 install uv
    fi

    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    if ! command -v uv &>/dev/null; then
        echo ""
        echo "ERROR: uv still not found after installation."
        echo "Try opening a new Terminal window and re-running this script."
        exit 1
    fi
    echo "  Installed: $(uv --version 2>&1)"
fi

# ── Step 3: Clone / update the fork ─────────────────────────
echo ""
echo "[3/5] Installing Salesforce MCP connector..."

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "  Existing installation found. Pulling latest changes..."
    git -C "$INSTALL_DIR" pull --ff-only
    echo "  Up to date."
else
    echo "  Cloning from $REPO_URL..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    echo "  Cloned to: $INSTALL_DIR"
fi

# ── Step 4: Collect Salesforce credentials ──────────────────
echo ""
echo "[4/5] Salesforce credentials"
echo ""
echo "You will need:"
echo "  - Your Salesforce username (email)"
echo "  - Your Salesforce password"
echo "  - Your Salesforce security token"
echo ""
echo "If you don't have a security token yet:"
echo "  1. Log in to Salesforce"
echo "  2. Click your profile icon (top right) -> Settings"
echo "  3. Go to My Personal Information -> Reset My Security Token"
echo "  4. Click 'Reset Security Token' — it will be emailed to you"
echo ""

read -rp "Salesforce username (email): " SF_USERNAME
if [[ -z "$SF_USERNAME" ]]; then
    echo "ERROR: Username cannot be empty."
    exit 1
fi

read -rsp "Salesforce password: " SF_PASSWORD
echo ""
if [[ -z "$SF_PASSWORD" ]]; then
    echo "ERROR: Password cannot be empty."
    exit 1
fi

read -rp "Salesforce security token: " SF_TOKEN
if [[ -z "$SF_TOKEN" ]]; then
    echo "ERROR: Security token cannot be empty."
    exit 1
fi

# ── Step 5: Update Claude Desktop config ────────────────────
echo ""
echo "[5/5] Configuring Claude Desktop..."

CONFIG_DIR="$HOME/Library/Application Support/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
    echo "  Existing config found. Merging Salesforce connector..."
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"
    echo "  (Backup saved as ${CONFIG_FILE}.backup.*)"
else
    echo "  No existing config found. Creating new one..."
fi

python3 - "$CONFIG_FILE" "$INSTALL_DIR" "$SF_USERNAME" "$SF_PASSWORD" "$SF_TOKEN" <<'PYEOF'
import json, sys

config_path = sys.argv[1]
install_dir = sys.argv[2]
username    = sys.argv[3]
password    = sys.argv[4]
token       = sys.argv[5]

try:
    with open(config_path, "r") as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

if "mcpServers" not in config:
    config["mcpServers"] = {}

uv_path = __import__("shutil").which("uv") or "uv"

config["mcpServers"]["salesforce"] = {
    "command": uv_path,
    "args": [
        "run",
        "--directory", install_dir,
        "python", "-m", "src.salesforce.server"
    ],
    "env": {
        "SALESFORCE_USERNAME":       username,
        "SALESFORCE_PASSWORD":       password,
        "SALESFORCE_SECURITY_TOKEN": token
    }
}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

PYEOF

echo "  Config updated at: $CONFIG_FILE"

# ── Restart Claude Desktop ───────────────────────────────────
echo ""
echo "=============================================="
echo "  Installation complete!"
echo "=============================================="
echo ""

if pgrep -xq "Claude"; then
    echo "Claude Desktop is currently running."
    read -rp "Restart it now? (y/n): " RESTART
    if [[ "$RESTART" =~ ^[Yy]$ ]]; then
        echo "  Quitting Claude Desktop..."
        osascript -e 'quit app "Claude"' 2>/dev/null || true
        sleep 2
        echo "  Reopening Claude Desktop..."
        open -a "Claude" 2>/dev/null || true
        echo "  Done! Ask Claude if it can connect to Salesforce."
    else
        echo "  Please quit and reopen Claude Desktop manually."
    fi
else
    echo "Claude Desktop is not running."
    read -rp "Open it now? (y/n): " OPEN_NOW
    if [[ "$OPEN_NOW" =~ ^[Yy]$ ]]; then
        open -a "Claude" 2>/dev/null || true
        echo "  Opening Claude Desktop. Ask Claude if it can connect to Salesforce."
    else
        echo "  Open Claude Desktop when you're ready and test the connector."
    fi
fi

echo ""
echo "If you run into issues, re-run this script or ask for help."

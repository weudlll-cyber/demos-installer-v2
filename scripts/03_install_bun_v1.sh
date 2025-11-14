#!/bin/bash
# This script installs Bun, a fast JavaScript runtime used by Demos Node.
# It ensures Bun is installed, added to PATH, and verified before continuing.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [03] Installing Bun JavaScript runtime...\e[0m"
echo -e "\e[91mBun is required to run and manage the Demos Node efficiently.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/03_install_bun.done"
mkdir -p "$MARKER_DIR"

# === Skip if already completed ===
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [03] Bun installation already completed. Skipping...\e[0m"
  exit 0
fi

# === Install unzip (required by Bun installer) ===
echo -e "\e[91m🔍 Checking for unzip (required by Bun installer)...\e[0m"
if ! command -v unzip &>/dev/null; then
  echo -e "\e[91m📦 unzip not found. Installing...\e[0m"
  apt-get update && apt-get install -y unzip || {
    echo -e "\e[91m❌ unzip installation failed.\e[0m"
    echo -e "\e[91mRun manually:\e[0m"
    echo -e "\e[91msudo apt-get install -y unzip\e[0m"
    exit 1
  }
fi
echo -e "\e[91m✅ unzip is installed.\e[0m"

# === Install Bun ===
echo -e "\e[91m📥 Downloading and installing Bun...\e[0m"
curl -fsSL https://bun.sh/install | bash || {
  echo -e "\e[91m❌ Bun installation failed.\e[0m"
  exit 1
}

# === Set BUN_INSTALL and PATH ===
export BUN_INSTALL="${HOME:-/root}/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# === Add to shell profile ===
echo 'export BUN_INSTALL="${HOME:-/root}/.bun"' >> ~/.bashrc
echo 'export PATH="${BUN_INSTALL}/bin:$PATH"' >> ~/.bashrc

# === Add to system-wide profile for services ===
echo 'export BUN_INSTALL="/root/.bun"' > /etc/profile.d/bun.sh
echo 'export PATH="/root/.bun/bin:$PATH"' >> /etc/profile.d/bun.sh
chmod +x /etc/profile.d/bun.sh

# === Verify Bun ===
echo -e "\e[91m🔍 Verifying Bun installation...\e[0m"
if command -v bun &>/dev/null; then
  echo -e "\e[91m✅ Bun is installed and available in PATH.\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Bun is not available in PATH after installation.\e[0m"
  exit 1
fi

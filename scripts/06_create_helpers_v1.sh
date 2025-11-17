#!/bin/bash
# Step 06: Install helper tools for Demos Node management
# Delegates to the unified install_helpers_v1.sh script in your GitHub repo.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [06] Installing helper tools for Demos Node management...\e[0m"
echo -e "\e[91mThese tools make it easier to check status, restart, stop, and back up keys.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/06_create_helpers.done"
mkdir -p "$MARKER_DIR"

# === Skip if already completed ===
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [06] Helper tools already installed. Skipping...\e[0m"
  exit 0
fi

# === Pre-check: ensure installer script exists in GitHub ===
HELPER_INSTALL_URL="https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/install_helpers_v1.sh"
echo -e "\e[91m🔍 Verifying installer script exists in GitHub...\e[0m"
if ! curl -sI "$HELPER_INSTALL_URL" | grep -q "^HTTP.* 200"; then
  echo -e "\e[91m❌ install_helpers_v1.sh not found in repo. Aborting.\e[0m"
  echo -e "\e[91mMake sure it's committed to:\e[0m"
  echo -e "\e[91m  $HELPER_INSTALL_URL\e[0m"
  exit 1
fi

# === Download and run unified installer ===
echo -e "\e[91m📥 Downloading unified helper installer...\e[0m"
curl -fsSL "$HELPER_INSTALL_URL" -o /tmp/install_helpers_v1.sh || {
  echo -e "\e[91m❌ Failed to download install_helpers_v1.sh\e[0m"
  echo -e "\e[91mCheck your internet connection or GitHub access.\e[0m"
  exit 1
}

chmod +x /tmp/install_helpers_v1.sh
echo -e "\e[91m🚀 Running unified helper installer...\e[0m"
bash /tmp/install_helpers_v1.sh

touch "$STEP_MARKER"
echo -e "\e[91m✅ [06] Helpers installed successfully via unified installer.\e[0m"

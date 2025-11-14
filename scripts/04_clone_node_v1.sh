#!/bin/bash
# This script clones the Demos Node repository and installs its dependencies using Bun.
# It ensures the repo is clean, trusted, and ready to run.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [04] Cloning Demos Node repository and installing dependencies...\e[0m"
echo -e "\e[91mThis step sets up the actual node codebase in /opt/demos-node.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/04_clone_repo.done"
mkdir -p "$MARKER_DIR"

# === Skip if already completed ===
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [04] Node repository already cloned. Skipping...\e[0m"
  exit 0
fi

# === Check for Bun ===
if ! command -v bun &>/dev/null; then
  echo -e "\e[91m❌ Bun is not available. Required for dependency installation.\e[0m"
  echo -e "\e[91mRun the installer again to complete Bun setup:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

# === Clone the repository ===
echo -e "\e[91m📥 Cloning Demos Node repository into /opt/demos-node...\e[0m"
if [ -d "/opt/demos-node/.git" ]; then
  echo -e "\e[91m⚠️ Repository already exists. Skipping clone.\e[0m"
else
  rm -rf /opt/demos-node 2>/dev/null || true
  git clone https://github.com/kynesyslabs/node.git /opt/demos-node || {
    echo -e "\e[91m❌ Git clone failed.\e[0m"
    echo -e "\e[91mCheck your internet connection or GitHub access.\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  }
fi

# === Install dependencies ===
echo -e "\e[91m📦 Installing dependencies with Bun...\e[0m"
cd /opt/demos-node
bun install || {
  echo -e "\e[91m❌ bun install failed.\e[0m"
  echo -e "\e[91mTry manually:\e[0m"
  echo -e "\e[91mcd /opt/demos-node && bun install\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
}

# === Trust dependencies ===
echo -e "\e[91m🔐 Trusting Bun dependencies...\e[0m"
bun pm trust || true

# === Verify run script ===
if [ -f "/opt/demos-node/run" ]; then
  echo -e "\e[91m✅ Node repository is ready.\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Missing run script in /opt/demos-node.\e[0m"
  echo -e "\e[91mCheck manually:\e[0m"
  echo -e "\e[91mls -l /opt/demos-node/run\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

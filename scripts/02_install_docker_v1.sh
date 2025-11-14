#!/bin/bash
# This script installs Docker if it's not already present and ensures it's running.
# Docker is required to run containerized services used by Demos Node.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [02] Installing Docker (required for container support)...\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/02_install_docker.done"
mkdir -p "$MARKER_DIR"

# === Skip if already completed ===
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [02] Docker installation already completed. Skipping...\e[0m"
  exit 0
fi

# === Check if Docker is already installed ===
if command -v docker &>/dev/null; then
  echo -e "\e[91m✅ Docker is already installed.\e[0m"
else
  echo -e "\e[91m📦 Docker not found. Installing via apt...\e[0m"

  # === Wait for dpkg and apt lock if held ===
  echo -e "\e[91m🔍 Checking for APT and dpkg locks...\e[0m"
  MAX_WAIT=60
  WAITED=0

  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
      echo -e "\e[91m❌ Package manager locks still held after $MAX_WAIT seconds. Aborting.\e[0m"
      echo -e "\e[91mPlease wait for other installations to finish, then rerun:\e[0m"
      echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
      exit 1
    fi
    echo -e "\e[91m⏳ Package manager is locked. Waiting... ($WAITED/$MAX_WAIT seconds)\e[0m"
    sleep 5
    WAITED=$((WAITED + 5))
  done

  echo -e "\e[91m✅ Locks released. Proceeding with Docker installation...\e[0m"

  apt-get update && apt-get install -y docker.io || {
    echo -e "\e[91m❌ Docker installation failed.\e[0m"
    echo -e "\e[91mRun manually:\e[0m"
    echo -e "\e[91msudo apt-get install -y docker.io\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  }
fi

# === Enable and start Docker service ===
echo -e "\e[91m🔧 Enabling and starting Docker service...\e[0m"
systemctl enable docker && systemctl start docker || {
  echo -e "\e[91m❌ Failed to start Docker service.\e[0m"
  echo -e "\e[91mRun manually:\e[0m"
  echo -e "\e[91msudo systemctl enable docker && sudo systemctl start docker\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
}

# === Verify Docker is running ===
echo -e "\e[91m🔍 Verifying Docker service status...\e[0m"
if systemctl is-active --quiet docker; then
  echo -e "\e[91m✅ Docker service is running.\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Docker service is not active.\e[0m"
  echo -e "\e[91mRun manually:\e[0m"
  echo -e "\e[91msudo systemctl restart docker\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🚀 Starting Demos Node Installer...\e[0m"

# === Root Check ===
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[91m❌ This script must be run as root.\e[0m"
  echo -e "\e[91mRun:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

# === Lock File ===
MARKER_DIR="/root/.demos_node_setup"
LOCK_FILE="$MARKER_DIR/installer.lock"
mkdir -p "$MARKER_DIR"

if [ -f "$LOCK_FILE" ]; then
  echo -e "\e[91m❌ Installer already running or was interrupted.\e[0m"
  echo -e "\e[91mTo resume, run:\e[0m"
  echo -e "\e[91mrm -f $LOCK_FILE && sudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# === Version Map ===
declare -A VERSION_MAP=(
  [01]="01_prepare_system_v1.sh"
  [02]="02_install_docker_v1.sh"
  [03]="03_install_bun_v1.sh"
  [04]="04_clone_node_v1.sh"
  [05]="05_setup_service_v1.sh"
  [06]="06_create_helpers_v1.sh"
  [07]="07_finalize_v1.sh"
)

# === Script Source URL ===
SCRIPT_BASE_URL="https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main"

# === Function: Fetch or Update Script ===
fetch_or_update_script() {
  local script="$1"
  local local_path="./$script"
  local remote_url="$SCRIPT_BASE_URL/$script"

  echo -e "\e[91m🔍 Checking $script...\e[0m"

  if [ -f "$local_path" ] && [ -s "$local_path" ]; then
    echo -e "\e[91m📦 Local copy found. Verifying freshness...\e[0m"
    local local_hash
    local remote_hash
    local_hash=$(sha256sum "$local_path" | cut -d' ' -f1)
    remote_hash=$(curl -fsSL "$remote_url" | sha256sum | cut -d' ' -f1)

    if [ "$local_hash" != "$remote_hash" ]; then
      echo -e "\e[91m🔄 New version detected. Updating $script...\e[0m"
      curl -fsSL "$remote_url" -o "$local_path"
    else
      echo -e "\e[91m✅ $script is up to date.\e[0m"
    fi
  else
    echo -e "\e[91m📥 Downloading $script...\e[0m"
    curl -fsSL "$remote_url" -o "$local_path" || {
      echo -e "\e[91m❌ Failed to download $script.\e[0m"
      echo -e "\e[91mCheck your internet connection or GitHub access.\e[0m"
      echo -e "\e[91mThen restart:\e[0m"
      echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
      exit 1
    }
  fi
}

# === Run Each Step ===
for STEP in {01..07}; do
  SCRIPT="${VERSION_MAP[$STEP]}"
  fetch_or_update_script "$SCRIPT"

  echo -e "\e[91m🔧 Running step $STEP: $SCRIPT\e[0m"
  if ! bash "$SCRIPT"; then
    echo -e "\e[91m❌ Step $STEP failed: $SCRIPT\e[0m"
    echo -e "\e[91mFix the issue above, then restart:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  fi

  echo -e "\e[91m✅ Step $STEP completed successfully.\e[0m"
done

# === Done ===
echo -e "\e[91m🎉 All steps completed. Demos Node is installed and running.\e[0m"
echo -e "\e[91mCheck status: check_demos_node --status\e[0m"
echo -e "\e[91mRestart node: restart_demos_node\e[0m"

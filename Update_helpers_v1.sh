#!/bin/bash
# Update Demos Node helper scripts from GitHub and refresh symlinks.
# Safe to run repeatedly; ensures helpers are current and executable.

set -euo pipefail
IFS=$'\n\t'

# --- Config ---
HELPER_DIR="/opt/demos-node/helpers"
GLOBAL_BIN="/usr/local/bin"

# Point this to your repo's raw helpers directory
REPO_BASE_URL="https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/helpers"

# List of helper filenames in the repo (no .sh extension if your files match that)
HELPERS=("check_demos_node" "restart_demos_node" "logs_demos_node" "backup_demos_keys" "stop_demos_node")

echo -e "\e[91m🔧 Updating Demos Node helpers...\e[0m"
mkdir -p "$HELPER_DIR" "$GLOBAL_BIN" || true

# --- Download latest helpers ---
for helper in "${HELPERS[@]}"; do
  src_url="${REPO_BASE_URL}/${helper}"
  dst_path="${HELPER_DIR}/${helper}"

  echo -e "\e[91m📥 Fetching: ${src_url}\e[0m"
  if ! curl -fsSL "$src_url" -o "$dst_path"; then
    echo -e "\e[91m❌ Failed to download ${helper} from ${src_url}\e[0m"
    exit 1
  fi

  chmod +x "$dst_path"
  ln -sf "$dst_path" "${GLOBAL_BIN}/${helper}"
  echo -e "\e[91m✅ Installed & linked: ${helper}\e[0m"
done

# --- Quick verification ---
FAILED=0
for helper in "${HELPERS[@]}"; do
  if command -v "$helper" &>/dev/null; then
    echo -e "\e[91m🧩 Verified in PATH: ${helper}\e[0m"
  else
    echo -e "\e[91m❌ Missing in PATH: ${helper}\e[0m"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo -e "\e[91m❌ One or more helpers failed verification.\e[0m"
  exit 1
fi

echo -e "\e[91m🎉 Helpers updated successfully.\e[0m"
echo -e "\e[91mTry:\e[0m"
echo -e "\e[91m  check_demos_node --status\e[0m"
echo -e "\e[91m  logs_demos_node --health\e[0m"
echo -e "\e[91m  restart_demos_node\e[0m"

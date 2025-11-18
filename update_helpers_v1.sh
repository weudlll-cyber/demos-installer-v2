#!/bin/bash
# Update Demos Node helper scripts from GitHub and refresh symlinks.
# Safe to run repeatedly; ensures helpers are current and executable.

set -euo pipefail
IFS=$'\n\t'

HELPER_DIR="/opt/demos-node/helpers"
GLOBAL_BIN="/usr/local/bin"
REPO_BASE_URL="https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/helpers"

# Only the three helpers that exist in your repo
HELPERS=("check_demos_node" "restart_demos_node" "stop_demos_node")

echo -e "\e[91m🔧 Updating Demos Node helpers...\e[0m"
mkdir -p "$HELPER_DIR" "$GLOBAL_BIN" || true

for helper in "${HELPERS[@]}"; do
  src_url="${REPO_BASE_URL}/${helper}"   # no .sh suffix in repo
  dst_path="${HELPER_DIR}/${helper}.sh"
  tmp="${dst_path}.tmp.$$"

  echo -e "\e[91m📥 Fetching: ${src_url}\e[0m"
  if ! curl -fsSL "$src_url" -o "$tmp"; then
    echo -e "\e[91m❌ Failed to download ${helper} from ${src_url}\e[0m"
    rm -f "$tmp" || true
    exit 1
  fi

  chmod +x "$tmp"
  mv -f "$tmp" "$dst_path"
  ln -sf "$dst_path" "${GLOBAL_BIN}/${helper}"
  echo -e "\e[91m✅ Installed & linked: ${helper}\e[0m"
done

echo -e "\e[91m🎉 Helpers updated successfully.\e[0m"
echo -e "\e[91mTry:\e[0m"
echo -e "\e[91m  check_demos_node --status\e[0m"
echo -e "\e[91m  stop_demos_node\e[0m"
echo -e "\e[91m  restart_demos_node\e[0m"

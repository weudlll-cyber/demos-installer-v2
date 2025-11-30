#!/bin/bash
# File: demos-installer-v2/helpers/install_helpers_v1.sh
# Directory (where this file should live): demos-installer-v2/helpers/
#
# Purpose:
# - Install helper commands by fetching them from the GitHub repo’s helpers/ directory.
# - Make each helper executable and symlink it into /usr/local/bin for easy use.
# - Keep behavior identical to the original script, while adding the new helper (restart_manual_flow)
#   and clarifying comments for maintainers.

set -euo pipefail
IFS=$'\n\t'

# Ensure bash is used (some shells handle arrays or pipefail differently)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "❌ This script must be run with bash. Try: bash install_helpers_v1.sh"
  exit 1
fi

# Base URL to the raw files in GitHub for the helpers directory (branch: main)
REPO_BASE="https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/helpers"

# Local directory where the helper files will be stored on the VPS
HELPER_DIR="/opt/demos-node/helpers"

# System-wide bin directory where we create symlinks so helpers can be run by name
GLOBAL_BIN="/usr/local/bin"

# List of helper names to install.
# Helpers in the repo are extensionless; we store them locally as .sh but link without the extension.
# Added: restart_manual_flow (new manual-run helper)
HELPERS=(check_demos_node restart_demos_node logs_demos_node restart_manual_flow)

# Create target directories if they don’t exist
mkdir -p "$HELPER_DIR" "$GLOBAL_BIN"

echo "📥 Downloading helper scripts from GitHub..."

# Loop through each helper, download, set executable, and symlink into PATH
for helper in "${HELPERS[@]}"; do
  src="${REPO_BASE}/${helper}"   # remote file has no .sh suffix
  dst="${HELPER_DIR}/${helper}.sh"  # store locally with .sh for clarity
  tmp="${dst}.tmp.$$"               # temp file to ensure atomic move
  bin="${GLOBAL_BIN}/${helper}"     # command name exposed in PATH (no .sh)

  echo "🔧 Installing $helper..."

  # Fetch the helper from GitHub
  if curl -fsSL "$src" -o "$tmp"; then
    # Make it executable and move into place
    chmod +x "$tmp"
    mv -f "$tmp" "$dst"

    # Create/refresh a symlink without the .sh so users run `helper` naturally
    ln -sf "$dst" "$bin"

    echo "✅ $helper installed and symlinked to $bin"
  else
    echo "❌ Failed to download $helper from $src"
    rm -f "$tmp" || true
  fi
done

# === Final verification ===
echo -e "\n🧪 Verifying helper installation..."
MISSING=()
for h in "${HELPERS[@]}"; do
  if command -v "$h" >/dev/null 2>&1; then
    echo "✅ $h is available in PATH"
  else
    echo "❌ $h is NOT available in PATH"
    MISSING+=("$h")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo -e "\n❌ Some helpers failed to install: ${MISSING[*]}"
  echo "Try re-running this script or check your GitHub repo for missing files."
  exit 1
fi

echo -e "\n🎉 All selected helpers installed successfully and symlinked to $GLOBAL_BIN"

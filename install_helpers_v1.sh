#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Ensure bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "❌ This script must be run with bash. Try: bash install_helpers_v1.sh"
  exit 1
fi

REPO_BASE="https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/helpers"
HELPER_DIR="/opt/demos-node/helpers"
GLOBAL_BIN="/usr/local/bin"
HELPERS=(check_demos_node restart_demos_node stop_demos_node)

mkdir -p "$HELPER_DIR" "$GLOBAL_BIN"

echo "📥 Downloading helper scripts from GitHub..."

for helper in "${HELPERS[@]}"; do
  src="${REPO_BASE}/${helper}.sh"
  dst="${HELPER_DIR}/${helper}.sh"
  tmp="${dst}.tmp.$$"
  bin="${GLOBAL_BIN}/${helper}"

  echo "🔧 Installing $helper..."

  if curl -fsSL "$src" -o "$tmp"; then
    chmod +x "$tmp"
    mv -f "$tmp" "$dst"
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

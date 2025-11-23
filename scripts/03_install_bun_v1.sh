#!/bin/bash
# [03] Install Bun (robust for systemd and non-interactive contexts)
# - Installs Bun into /root/.bun
# - Creates /usr/local/bin/bun symlink so non-login shells and systemd find it
# - Writes /etc/profile.d/bun.sh for interactive shells
# - Writes a demos-node systemd drop-in to expose BUN_INSTALL and PATH to the service
# - Verifies bun is runnable and executes a tiny test script
set -euo pipefail
IFS=$'\n\t'

# ---------- header and marker handling ----------
echo -e "\e[91m🔧 [03] Installing Bun JavaScript runtime...\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/03_install_bun.done"
mkdir -p "$MARKER_DIR"

# If this step already completed, skip
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[92m✅ [03] Bun installation already completed. Skipping...\e[0m"
  exit 0
fi

# ---------- ensure prerequisites ----------
# Some environments lack unzip which the Bun installer can require
if ! command -v unzip &>/dev/null; then
  echo -e "\e[93m🔍 unzip not found — installing (required by bun installer)...\e[0m"
  apt-get update && apt-get install -y unzip || {
    echo -e "\e[91m❌ Failed to install unzip. Please install unzip and re-run this step.\e[0m"
    exit 1
  }
fi

# ---------- run Bun installer ----------
# Use the official installer script; it places files under ${HOME:-/root}/.bun
echo -e "\e[93m📥 Running bun installer...\e[0m"
curl -fsSL https://bun.sh/install | bash || {
  echo -e "\e[91m❌ Bun installation script failed. Inspect installer output and retry.\e[0m"
  exit 1
}

# ---------- canonicalize install location ----------
# For predictable systemd/service behavior, canonicalize to /root/.bun
BUN_INSTALL="/root/.bun"
if [ -d "${HOME:-/root}/.bun" ] && [ ! -d "$BUN_INSTALL" ]; then
  # Copy or ensure the installed tree is available under /root/.bun
  # (safe-copy; if same path it's a no-op)
  cp -a "${HOME:-/root}/.bun" "$BUN_INSTALL" 2>/dev/null || true
fi

# ---------- create a stable global symlink ----------
# Symlink /usr/local/bin/bun -> the installed bun binary so non-interactive contexts find it
if [ -x "$BUN_INSTALL/bin/bun" ]; then
  echo -e "\e[93m🔗 Creating global symlink /usr/local/bin/bun -> $BUN_INSTALL/bin/bun\e[0m"
  ln -sf "$BUN_INSTALL/bin/bun" /usr/local/bin/bun
  chmod +x "$BUN_INSTALL/bin/bun" || true
fi

# ---------- write /etc/profile.d for interactive shells ----------
# Keeps interactive sessions working as before; does not replace service behavior
cat > /etc/profile.d/bun.sh <<'EOF'
# Bun environment for interactive shells
export BUN_INSTALL="/root/.bun"
export PATH="/root/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
chmod 0644 /etc/profile.d/bun.sh

# ---------- safely ensure PATH for systemd services ----------
# Instead of appending the live PATH into /etc/environment (which can be brittle),
# create a systemd drop-in for demos-node that sets BUN_INSTALL and PATH explicitly.
mkdir -p /etc/systemd/system/demos-node.service.d
cat > /etc/systemd/system/demos-node.service.d/env.conf <<'EOF'
[Service]
# Explicit environment so systemd-run and the demos-node unit can find bun
Environment=BUN_INSTALL=/root/.bun
Environment=PATH=/root/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
chmod 0644 /etc/systemd/system/demos-node.service.d/env.conf

# ---------- reload systemd units (safe) ----------
# Use daemon-reload rather than daemon-reexec — it's lighter and avoids re-exec semantics
systemctl daemon-reload

# ---------- resolve bun binary for verification ----------
# Prefer command -v (interactive path), then fallback to canonical symlink or direct binary
if command -v bun &>/dev/null; then
  BUN_BIN="$(command -v bun)"
elif [ -x "/usr/local/bin/bun" ]; then
  BUN_BIN="/usr/local/bin/bun"
elif [ -x "$BUN_INSTALL/bin/bun" ]; then
  ln -sf "$BUN_INSTALL/bin/bun" /usr/local/bin/bun
  BUN_BIN="/usr/local/bin/bun"
else
  echo -e "\e[91m❌ Bun executable not found after installation.\e[0m"
  echo -e "\e[91mCheck contents of $BUN_INSTALL/bin and rerun installer.\e[0m"
  ls -la "$BUN_INSTALL/bin" || true
  exit 1
fi

# ---------- check version and run a tiny functional test ----------
BUN_VERSION="$($BUN_BIN --version 2>/dev/null || echo "unknown")"
echo -e "\e[92m✅ Bun binary resolved: $BUN_BIN  version: $BUN_VERSION\e[0m"

# Run a minimal TypeScript test using the resolved bun binary
TEST_FILE="/tmp/bun_test.ts"
echo 'console.log("✅ Bun test script executed successfully!")' > "$TEST_FILE"
if ! "$BUN_BIN" "$TEST_FILE" &>/dev/null; then
  echo -e "\e[91m❌ Bun failed to execute the test script using $BUN_BIN.\e[0m"
  echo -e "\e[91mInspect $TEST_FILE and bun output; re-run installer if necessary.\e[0m"
  exit 1
fi

# ---------- finalization ----------
# Mark this step done so the installer doesn't repeat it
touch "$STEP_MARKER"
echo -e "\e[92m✅ Bun installed and available via $BUN_BIN\e[0m"

#!/bin/bash
# [03] Install Bun (robust for systemd and non-interactive contexts)
set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [03] Installing Bun JavaScript runtime...\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/03_install_bun.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [03] Bun installation already completed. Skipping...\e[0m"
  exit 0
fi

# Ensure unzip is present
if ! command -v unzip &>/dev/null; then
  apt-get update && apt-get install -y unzip || {
    echo -e "\e[91m❌ unzip installation failed.\e[0m"
    exit 1
  }
fi

# Run Bun installer (installs into ${HOME:-/root}/.bun)
curl -fsSL https://bun.sh/install | bash || {
  echo -e "\e[91m❌ Bun installation script failed.\e[0m"
  exit 1
}

# Canonicalize install location for root contexts
BUN_INSTALL="/root/.bun"
if [ -d "${HOME:-/root}/.bun" ] && [ ! -d "$BUN_INSTALL" ]; then
  # if installed into a different homedir, copy/ensure into /root/.bun
  cp -a "${HOME:-/root}/.bun" "$BUN_INSTALL" || true
fi

# Create a stable global symlink so bun is available in all contexts
if [ -x "$BUN_INSTALL/bin/bun" ]; then
  ln -sf "$BUN_INSTALL/bin/bun" /usr/local/bin/bun
  chmod +x "$BUN_INSTALL/bin/bun" || true
fi

# Write a safe /etc/profile.d entry (kept for interactive shells)
cat > /etc/profile.d/bun.sh <<'EOF'
export BUN_INSTALL="/root/.bun"
export PATH="/root/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
chmod 0644 /etc/profile.d/bun.sh

# Do NOT append the live $PATH into /etc/environment. Instead ensure /root/.bun/bin is present if file exists
if [ -f /etc/environment ]; then
  if ! grep -q '/root/.bun/bin' /etc/environment; then
    # Add a small safe PATH entry if file seems sane
    # This replaces any existing PATH= line with a safe variant including /root/.bun/bin
    if grep -q '^PATH=' /etc/environment; then
      sed -i 's|^PATH=.*|PATH="/root/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"|' /etc/environment || true
    else
      echo 'PATH="/root/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment
    fi
  fi
fi

# Create a systemd drop-in for demos-node service to make BUN_INSTALL and PATH explicit (won't error if service doesn't exist yet)
mkdir -p /etc/systemd/system/demos-node.service.d
cat > /etc/systemd/system/demos-node.service.d/env.conf <<'EOF'
[Service]
Environment=BUN_INSTALL=/root/.bun
Environment=PATH=/root/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
chmod 0644 /etc/systemd/system/demos-node.service.d/env.conf

# Reload systemd units (safe operation)
systemctl daemon-reload

# Verify bun availability: prefer command -v, fall back to absolute path
if command -v bun &>/dev/null; then
  BUN_BIN="$(command -v bun)"
elif [ -x "/usr/local/bin/bun" ]; then
  BUN_BIN="/usr/local/bin/bun"
elif [ -x "$BUN_INSTALL/bin/bun" ]; then
  ln -sf "$BUN_INSTALL/bin/bun" /usr/local/bin/bun
  BUN_BIN="/usr/local/bin/bun"
else
  echo -e "\e[91m❌ Bun executable not found after installation.\e[0m"
  echo -e "\e[91mCheck: ls -la $BUN_INSTALL/bin || true\e[0m"
  exit 1
fi

# Check version and run a small test using the resolved binary
BUN_VERSION="$($BUN_BIN --version 2>/dev/null || echo "unknown")"
echo -e "\e[91m✅ Bun binary: $BUN_BIN  version: $BUN_VERSION\e[0m"

echo 'console.log("✅ Bun test script executed successfully!")' > /tmp/bun_test.ts
if ! "$BUN_BIN" /tmp/bun_test.ts &>/dev/null; then
  echo -e "\e[91m❌ Bun failed to execute a test script using $BUN_BIN.\e[0m"
  exit 1
fi

# Mark done
touch "$STEP_MARKER"
echo -e "\e[91m✅ Bun installed and available via $BUN_BIN\e[0m"

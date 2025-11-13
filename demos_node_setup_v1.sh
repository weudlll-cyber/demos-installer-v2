#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91mStarting Demos Node Installer...\e[0m"

MARKER_DIR="/root/.demos_node_setup"
mkdir -p "$MARKER_DIR"

# === STEP 01: Wait for DNS and GitHub ===
if [ ! -f "$MARKER_DIR/01_dns_check.done" ]; then
  echo -e "\e[91m[STEP 01] Checking GitHub DNS...\e[0m"
  until ping -c1 github.com &>/dev/null; do
    echo -e "\e[91mWaiting for GitHub DNS resolution...\e[0m"
    sleep 5
  done
  touch "$MARKER_DIR/01_dns_check.done"
else
  echo -e "\e[91m[STEP 01] Already completed.\e[0m"
fi

# === STEP 02: Install Docker ===
if [ ! -f "$MARKER_DIR/02_install_docker.done" ]; then
  echo -e "\e[91m[STEP 02] Installing Docker...\e[0m"
  apt-get update
  apt-get install -y docker.io
  systemctl enable docker
  systemctl start docker
  touch "$MARKER_DIR/02_install_docker.done"
else
  echo -e "\e[91m[STEP 02] Already completed.\e[0m"
fi

# === STEP 03: Install Bun ===
if [ ! -f "$MARKER_DIR/03_install_bun.done" ]; then
  echo -e "\e[91m[STEP 03] Installing Bun...\e[0m"
  apt-get install -y unzip
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.bashrc
  echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.bashrc
  source ~/.bashrc
  touch "$MARKER_DIR/03_install_bun.done"
else
  echo -e "\e[91m[STEP 03] Already completed.\e[0m"
fi

# === STEP 04: Clone Testnet Node Repo ===
if [ ! -f "$MARKER_DIR/04_clone_repo.done" ]; then
  echo -e "\e[91m[STEP 04] Cloning Testnet Node repository...\e[0m"
  if [ -d "/opt/demos-node/.git" ]; then
    echo -e "\e[91m[STEP 04] Repo already exists at /opt/demos-node. Skipping clone.\e[0m"
  else
    rm -rf /opt/demos-node 2>/dev/null || true
    git clone https://github.com/kynesyslabs/node.git /opt/demos-node
  fi
  cd /opt/demos-node
  bun install
  touch "$MARKER_DIR/04_clone_repo.done"
else
  echo -e "\e[91m[STEP 04] Already completed.\e[0m"
fi

# === STEP 05: Create Systemd Service ===
if [ ! -f "$MARKER_DIR/05_systemd_service.done" ]; then
  echo -e "\e[91m[STEP 05] Creating systemd service...\e[0m"
  cat > /etc/systemd/system/demos-node.service <<EOF
[Unit]
Description=Demos Node Service
After=network.target

[Service]
ExecStart=/opt/demos-node/run
Restart=always
User=root
Environment=NODE_ENV=production
WorkingDirectory=/opt/demos-node

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable demos-node.service
  systemctl start demos-node.service
  touch "$MARKER_DIR/05_systemd_service.done"
else
  echo -e "\e[91m[STEP 05] Already completed.\e[0m"
fi

# === STEP 06: Install Helper Scripts ===
if [ ! -f "$MARKER_DIR/06_install_helpers.done" ]; then
  echo -e "\e[91m[STEP 06] Installing helper scripts...\e[0m"
  bash <(curl -fsSL https://raw.githubusercontent.com/weudl/demos-node-installer/main/scripts/install_helpers.sh)
  touch "$MARKER_DIR/06_install_helpers.done"
else
  echo -e "\e[91m[STEP 06] Already completed.\e[0m"
fi

# === STEP 07: Reboot Once ===
if [ ! -f "$MARKER_DIR/07_reboot_once.done" ]; then
  echo -e "\e[91m[STEP 07] Rebooting system to finalize setup...\e[0m"
  echo -e "\e[91mThis reboot is required to apply kernel updates and finalize installation.\e[0m"
  touch "$MARKER_DIR/07_reboot_once.done"
  reboot
else
  echo -e "\e[91m[STEP 07] Reboot already completed.\e[0m"
fi

echo -e "\e[92m✅ Demos Node installation complete.\e[0m"

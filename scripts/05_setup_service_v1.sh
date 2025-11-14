#!/bin/bash
# This script creates and enables a systemd service for Demos Node.
# It ensures the node runs in the background and restarts automatically on failure.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [05] Setting up Demos Node as a systemd service...\e[0m"
echo -e "\e[91mThis allows the node to run in the background and restart automatically if it crashes.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/05_setup_service.done"
mkdir -p "$MARKER_DIR"

# === Skip if already completed ===
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [05] Service already configured. Skipping...\e[0m"
  exit 0
fi

# === Check for systemd ===
if ! command -v systemctl &>/dev/null; then
  echo -e "\e[91m❌ systemd is not available. Cannot create service.\e[0m"
  echo -e "\e[91mMake sure you're using a full Ubuntu system (not WSL or minimal container).\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

# === Create systemd service file ===
SERVICE_FILE="/etc/systemd/system/demos-node.service"
echo -e "\e[91m📝 Creating service file at $SERVICE_FILE...\e[0m"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Demos Node Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/demos-node
ExecStart=/opt/demos-node/run
Restart=always
RestartSec=5
Environment=BUN_INSTALL=/root/.bun
Environment=PATH=/root/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

# === Reload systemd and enable service ===
echo -e "\e[91m🔄 Reloading systemd and enabling service...\e[0m"
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable demos-node || {
  echo -e "\e[91m❌ Failed to enable service.\e[0m"
  echo -e "\e[91mRun manually:\e[0m"
  echo -e "\e[91msudo systemctl enable demos-node\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
}

# === Start the service ===
echo -e "\e[91m🚀 Starting Demos Node service...\e[0m"
systemctl start demos-node || {
  echo -e "\e[91m❌ Failed to start service.\e[0m"
  echo -e "\e[91mRun manually:\e[0m"
  echo -e "\e[91msudo systemctl start demos-node\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
}

# === Verify service is running ===
echo -e "\e[91m🔍 Verifying service status...\e[0m"
if systemctl is-active --quiet demos-node; then
  echo -e "\e[91m✅ Demos Node service is active and running.\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Service is not running.\e[0m"
  echo -e "\e[91mCheck logs:\e[0m"
  echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"5 minutes ago\"\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

#!/bin/bash
# This script completes the Demos Node installation, configures .env and peer list, and backs up identity keys.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🎉 [07] Finalizing installation...\e[0m"
echo -e "\e[91mYou're almost done! Let's wrap things up.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/07_finalize.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [07] Finalization already completed. Skipping...\e[0m"
  exit 0
fi

# === Final messages ===
echo -e "\e[91m✅ Demos Node is now fully installed and running as a systemd service.\e[0m"
echo -e "\e[91mYou can manage it using the helper tools installed:\e[0m"
echo -e "\e[91m🔍 Check status:\e[0m"
echo -e "\e[91mcheck_demos_node --status\e[0m"
echo -e "\e[91m🔄 Restart node:\e[0m"
echo -e "\e[91mrestart_demos_node\e[0m"
echo -e "\e[91m📦 View logs:\e[0m"
echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"

# === Detect port conflicts ===
DEFAULT_NODE_PORT=53550
DEFAULT_DB_PORT=5332

echo -e "\e[91m🔍 Checking for port conflicts...\e[0m"
if ss -tuln | grep -q ":$DEFAULT_NODE_PORT "; then
  echo -e "\e[91m⚠️ Port $DEFAULT_NODE_PORT is already in use.\e[0m"
  read -p "👉 Enter a different port for the node: " CUSTOM_NODE_PORT
else
  CUSTOM_NODE_PORT=$DEFAULT_NODE_PORT
fi

if ss -tuln | grep -q ":$DEFAULT_DB_PORT "; then
  echo -e "\e[91m⚠️ Port $DEFAULT_DB_PORT is already in use.\e[0m"
  read -p "👉 Enter a different port for PostgreSQL: " CUSTOM_DB_PORT
else
  CUSTOM_DB_PORT=$DEFAULT_DB_PORT
fi

# === Configure .env ===
if [ ! -f .env ]; then
  echo -e "\e[91m🔧 Generating .env configuration...\e[0m"

  if [ -f /opt/demos-node/env.example ]; then
    cp /opt/demos-node/env.example .env
    echo -e "\e[91m✅ Loaded template from /opt/demos-node/env.example\e[0m"
  else
    echo -e "\e[91m⚠️ env.example not found. Creating a basic .env manually...\e[0m"
    touch .env
  fi

  PUBLIC_IP=$(curl -s ifconfig.me || echo "localhost")
  DEFAULT_URL="http://$PUBLIC_IP:$CUSTOM_NODE_PORT"

  echo -e "\e[91m🌐 Detected public IP: $PUBLIC_IP\e[0m"
  echo -e "\e[91m🔧 Setting EXPOSED_URL to: $DEFAULT_URL\e[0m"

  sed -i "s|^EXPOSED_URL=.*|EXPOSED_URL=$DEFAULT_URL|" .env || echo "EXPOSED_URL=$DEFAULT_URL" >> .env
  sed -i "s|^NODE_PORT=.*|NODE_PORT=$CUSTOM_NODE_PORT|" .env || echo "NODE_PORT=$CUSTOM_NODE_PORT" >> .env
  sed -i "s|^DB_PORT=.*|DB_PORT=$CUSTOM_DB_PORT|" .env || echo "DB_PORT=$CUSTOM_DB_PORT" >> .env
else
  echo -e "\e[91m✅ .env already exists. Skipping...\e[0m"
fi

# === Configure demos_peerlist.json ===
if [ ! -f demos_peerlist.json ]; then
  echo -e "\e[91m🔧 Creating default demos_peerlist.json...\e[0m"
  if [ -f /opt/demos-node/demos_peerlist.json.example ]; then
    cp /opt/demos-node/demos_peerlist.json.example demos_peerlist.json
    echo -e "\e[91m✅ Loaded template from /opt/demos-node/demos_peerlist.json.example\e[0m"
  else
    echo -e "\e[91m⚠️ demos_peerlist.json.example not found. Creating an empty peer list...\e[0m"
    echo "{}" > demos_peerlist.json
  fi
else
  echo -e "\e[91m✅ demos_peerlist.json already exists. Skipping...\e[0m"
fi

# === Peer list guidance ===
echo -e "\e[91m📡 To join a network, edit demos_peerlist.json and add known peers in this format:\e[0m"
echo -e "\e[91m  {\n    \"<publickey>\": \"http://<peer-url>:<port>\"\n  }\e[0m"
echo -e "\e[91mYou can add multiple peers separated by commas inside the JSON object.\e[0m"

# === Backup identity keys ===
echo -e "\e[91m📁 Backing up identity keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp .demos_identity "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No .demos_identity file found.\e[0m"
cp publickey_* "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No publickey_* file found.\e[0m"

echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

touch "$STEP_MARKER"

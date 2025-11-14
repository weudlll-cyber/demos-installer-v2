#!/bin/bash
# This script completes the Demos Node installation, configures .env and peer list, and backs up identity keys.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🎉 [07] Finalizing installation...\e[0m"
echo -e "\e[91mYou're almost done! Let's wrap things up.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/07_finalize.done"
mkdir -p "$MARKER_DIR"

# === Skip if already completed ===
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

# === Configure .env ===
if [ ! -f .env ]; then
  echo -e "\e[91m🔧 Generating .env configuration...\e[0m"
  cp env.example .env

  PUBLIC_IP=$(curl -s ifconfig.me || echo "localhost")
  DEFAULT_URL="http://$PUBLIC_IP:53550"

  echo -e "\e[91m🌐 Detected public IP: $PUBLIC_IP\e[0m"
  echo -e "\e[91m🔧 Setting EXPOSED_URL to: $DEFAULT_URL\e[0m"

  if grep -q '^EXPOSED_URL=' .env; then
    sed -i "s|^EXPOSED_URL=.*|EXPOSED_URL=$DEFAULT_URL|" .env
  else
    echo "EXPOSED_URL=$DEFAULT_URL" >> .env
  fi
else
  echo -e "\e[91m✅ .env already exists. Skipping...\e[0m"
fi

# === Configure demos_peerlist.json ===
if [ ! -f demos_peerlist.json ]; then
  echo -e "\e[91m🔧 Creating default demos_peerlist.json...\e[0m"
  cp demos_peerlist.json.example demos_peerlist.json
else
  echo -e "\e[91m✅ demos_peerlist.json already exists. Skipping...\e[0m"
fi

# === Optional peer entry ===
read -p "👉 Enter known peer public key (or leave blank to skip): " PEER_KEY
read -p "👉 Enter peer URL (e.g. http://peer.example.com): " PEER_URL

if [[ -n "$PEER_KEY" && -n "$PEER_URL" ]]; then
  echo -e "\e[91m🔗 Adding peer to demos_peerlist.json...\e[0m"
  jq --arg key "$PEER_KEY" --arg url "$PEER_URL" '. + {($key): $url}' demos_peerlist.json > tmp.json && mv tmp.json demos_peerlist.json
fi

# === Backup identity keys ===
echo -e "\e[91m📁 Backing up identity keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp .demos_identity "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No .demos_identity file found.\e[0m"
cp publickey_* "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No publickey_* file found.\e[0m"

echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

touch "$STEP_MARKER"

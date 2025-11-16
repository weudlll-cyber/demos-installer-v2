#!/bin/bash
# Step 07: Finalize Demos Node installation
# Configures .env in /opt/demos-node, resolves DB port conflicts, sets peer list, and backs up identity keys.

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

echo -e "\e[91m✅ Demos Node is now fully installed and running as a systemd service.\e[0m"
echo -e "\e[91mYou can manage it using the helper tools installed:\e[0m"
echo -e "\e[91m🔍 Check status: check_demos_node --status\e[0m"
echo -e "\e[91m🔄 Restart node: restart_demos_node\e[0m"
echo -e "\e[91m📦 View logs: sudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"

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
  CUSTOM_DB_PORT=$DEFAULT_DB_PORT
else
  CUSTOM_DB_PORT=$DEFAULT_DB_PORT
fi

# === Configure .env in /opt/demos-node ===
ENV_PATH="/opt/demos-node/.env"

if [ ! -f "$ENV_PATH" ]; then
  echo -e "\e[91m🔧 Generating .env configuration...\e[0m"

  if [ -f /opt/demos-node/env.example ]; then
    cp /opt/demos-node/env.example "$ENV_PATH"
    echo -e "\e[91m✅ Loaded template from /opt/demos-node/env.example\e[0m"
  else
    touch "$ENV_PATH"
    echo -e "\e[91m⚠️ env.example not found. Creating empty .env\e[0m"
  fi

  PUBLIC_IP=$(curl -s ifconfig.me || echo "localhost")
  DEFAULT_URL="http://$PUBLIC_IP:$CUSTOM_NODE_PORT"

  echo -e "\e[91m🌐 Detected public IP: $PUBLIC_IP\e[0m"
  echo -e "\e[91m🔧 Setting EXPOSED_URL to: $DEFAULT_URL\e[0m"

  sed -i "s|^EXPOSED_URL=.*|EXPOSED_URL=$DEFAULT_URL|" "$ENV_PATH" || echo "EXPOSED_URL=$DEFAULT_URL" >> "$ENV_PATH"
  sed -i "s|^NODE_PORT=.*|NODE_PORT=$CUSTOM_NODE_PORT|" "$ENV_PATH" || echo "NODE_PORT=$CUSTOM_NODE_PORT" >> "$ENV_PATH"
  sed -i "s|^DB_PORT=.*|DB_PORT=$CUSTOM_DB_PORT|" "$ENV_PATH" || echo "DB_PORT=$CUSTOM_DB_PORT" >> "$ENV_PATH"
else
  echo -e "\e[91m✅ .env already exists at $ENV_PATH. Skipping...\e[0m"
fi

# === Kill conflicting PostgreSQL process based on .env DB_PORT ===
if [ -f "$ENV_PATH" ]; then
  DB_PORT=$(grep "^DB_PORT=" "$ENV_PATH" | cut -d'=' -f2)
  echo -e "\e[91mℹ️ Using DB_PORT from .env: $DB_PORT\e[0m"

  if ss -tuln | grep -q ":$DB_PORT "; then
    echo -e "\e[91m⚠️ Port $DB_PORT is already in use by PostgreSQL.\e[0m"
    echo -e "\e[91m🔪 Killing PostgreSQL process bound to port $DB_PORT...\e[0m"
    sudo lsof -ti :$DB_PORT | xargs -r sudo kill -9 || true
    echo -e "\e[91m✅ PostgreSQL process on port $DB_PORT terminated.\e[0m"
  else
    echo -e "\e[91m✅ No PostgreSQL conflict detected on port $DB_PORT.\e[0m"
  fi
else
  echo -e "\e[91mℹ️ No .env found yet — skipping DB port check.\e[0m"
fi

# === Start node to trigger key generation ===
echo -e "\e[91m🚀 Starting Demos Node to generate identity keys...\e[0m"
systemctl restart demos-node

# === Wait for identity keys ===
echo -e "\e[91m⏳ Waiting for identity keys to be generated...\e[0m"
MAX_WAIT=120
INTERVAL=10
WAITED=0

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f /opt/demos-node/.demos_identity ] && ls /opt/demos-node/publickey_ed25519_* &>/dev/null; then
    echo -e "\e[91m✅ Identity keys detected.\e[0m"
    break
  fi
  echo -e "\e[91m⌛ Still waiting... ($WAITED/$MAX_WAIT seconds)\e[0m"
  sleep "$INTERVAL"
  WAITED=$((WAITED + INTERVAL))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  echo -e "\e[91m❌ Identity keys were not generated within 2 minutes.\e[0m"
  echo -e "\e[91m❌ Node setup is incomplete. demos_peerlist.json cannot be configured without keys.\e[0m"
  echo -e "\e[91mPlease check the node logs and restart manually:\e[0m"
  echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"
  exit 1
fi

# === Configure demos_peerlist.json ===
echo -e "\e[91m🔗 Configuring demos_peerlist.json with this node's public key...\e[0m"
cd /opt/demos-node
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls publickey_ed25519_* 2>/dev/null | head -n 1)

if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX=$(echo "$PUBKEY_FILE" | sed 's/publickey_ed25519_//')
  NODE_IP=$(hostname -I | awk '{print $1}')
  NODE_PORT=$(grep "^NODE_PORT=" "$ENV_PATH" | cut -d'=' -f2 2>/dev/null || echo "53550")
  NODE_URL="http://$NODE_IP:$NODE_PORT"

  echo "{ \"0x$PUBKEY_HEX\": \"$NODE_URL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peer list created with this node: 0x$PUBKEY_HEX\e[0m"

  echo -e "\e[91m🔄 Restarting node to apply peer list changes...\e[0m"
  systemctl restart demos-node
else
  echo -e "\e[91m⚠️ No public key found. Skipping peer list configuration.\e[0m"
fi

# === Backup identity keys ===
echo -e "\e[91m📁 Backing up identity keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp /opt/demos-node/.demos_identity "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No .demos_identity file found.\e[0m"
cp /opt/demos-node/publickey_ed25519_* "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No publickey file found.\e[0m"

echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

touch "$STEP_MARKER"ENV_PATH="/opt/demos-node/.env"
if [ -f "$ENV_PATH" ]; then
  DB_PORT=$(grep "^DB_PORT=" "$ENV_PATH" | cut -d'=' -f2)
  echo -e "\e[91mℹ️ Using DB_PORT from .env: $DB_PORT\e[0m"

  if ss -tuln | grep -q ":$DB_PORT "; then
    echo -e "\e[91m⚠️ Port $DB_PORT is already in use by PostgreSQL.\e[0m"
    echo -e "\e[91m🔪 Killing PostgreSQL process bound to port $DB_PORT...\e[0m"
    sudo lsof -ti :$DB_PORT | xargs -r sudo kill -9 || true
    echo -e "\e[91m✅ PostgreSQL process on port $DB_PORT terminated.\e[0m"
  else
    echo -e "\e[91m✅ No PostgreSQL conflict detected on port $DB_PORT.\e[0m"
  fi
else
  echo -e "\e[91mℹ️ No .env found yet — skipping DB port check.\e[0m"
fi

# === Start node to trigger key generation ===
echo -e "\e[91m🚀 Starting Demos Node to generate identity keys...\e[0m"
systemctl restart demos-node

# === Wait for key generation ===
echo -e "\e[91m⏳ Waiting for identity keys to be generated by the node...\e[0m"
MAX_WAIT=120
INTERVAL=10
WAITED=0

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f /opt/demos-node/.demos_identity ] && ls /opt/demos-node/publickey_ed25519_* &>/dev/null; then
    echo -e "\e[91m✅ Identity keys detected.\e[0m"
    break
  fi
  echo -e "\e[91m⌛ Still waiting... ($WAITED/$MAX_WAIT seconds)\e[0m"
  sleep "$INTERVAL"
  WAITED=$((WAITED + INTERVAL))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  echo -e "\e[91m❌ Identity keys were not generated within 2 minutes.\e[0m"
  echo -e "\e[91m❌ Node setup is incomplete. demos_peerlist.json cannot be configured without keys.\e[0m"
  echo -e "\e[91mPlease check the node logs and restart manually:\e[0m"
  echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"
  exit 1
fi

# === Configure demos_peerlist.json automatically ===
echo -e "\e[91m🔗 Configuring demos_peerlist.json with this node's public key...\e[0m"
cd /opt/demos-node
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls publickey_ed25519_* 2>/dev/null | head -n 1)

if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX=$(echo "$PUBKEY_FILE" | sed 's/publickey_ed25519_//')
  NODE_IP=$(hostname -I | awk '{print $1}')
  NODE_URL="http://$NODE_IP:$CUSTOM_NODE_PORT"

  echo "{ \"0x$PUBKEY_HEX\": \"$NODE_URL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peer list created with this node: 0x$PUBKEY_HEX\e[0m"

  echo -e "\e[91m🔄 Restarting node to apply peer list changes...\e[0m"
  systemctl restart demos-node
else
  echo -e "\e[91m⚠️ No public key found. Skipping peer list configuration.\e[0m"
fi

# === Backup identity keys ===
echo -e "\e[91m📁 Backing up identity keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp /opt/demos-node/.demos_identity "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No .demos_identity file found.\e[0m"
cp /opt/demos-node/publickey_ed25519_* "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No publickey file found.\e[0m"

echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

touch "$STEP_MARKER"fi

# === Kill conflicting PostgreSQL process based on .env DB_PORT ===
DB_PORT=$(grep "^DB_PORT=" /opt/demos-node/.env | cut -d'=' -f2)

if ss -tuln | grep -q ":$DB_PORT "; then
  echo -e "\e[91m⚠️ Port $DB_PORT is already in use by PostgreSQL.\e[0m"
  echo -e "\e[91m🔪 Killing PostgreSQL process bound to port $DB_PORT...\e[0m"
  sudo lsof -ti :$DB_PORT | xargs -r sudo kill -9 || true
  echo -e "\e[91m✅ PostgreSQL process on port $DB_PORT terminated.\e[0m"
else
  echo -e "\e[91m✅ No PostgreSQL conflict detected on port $DB_PORT.\e[0m"
fi

# === Start node to trigger key generation ===
echo -e "\e[91m🚀 Starting Demos Node to generate identity keys...\e[0m"
systemctl restart demos-node

# === Wait for key generation ===
echo -e "\e[91m⏳ Waiting for identity keys to be generated by the node...\e[0m"
MAX_WAIT=120
INTERVAL=10
WAITED=0

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f /opt/demos-node/.demos_identity ] && ls /opt/demos-node/publickey_ed25519_* &>/dev/null; then
    echo -e "\e[91m✅ Identity keys detected.\e[0m"
    break
  fi
  echo -e "\e[91m⌛ Still waiting... ($WAITED/$MAX_WAIT seconds)\e[0m"
  sleep "$INTERVAL"
  WAITED=$((WAITED + INTERVAL))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  echo -e "\e[91m❌ Identity keys were not generated within 2 minutes.\e[0m"
  echo -e "\e[91m❌ Node setup is incomplete. demos_peerlist.json cannot be configured without keys.\e[0m"
  echo -e "\e[91mPlease check the node logs and restart manually:\e[0m"
  echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"
  exit 1
fi

# === Configure demos_peerlist.json automatically ===
echo -e "\e[91m🔗 Configuring demos_peerlist.json with this node's public key...\e[0m"

cd /opt/demos-node
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls publickey_ed25519_* 2>/dev/null | head -n 1)

if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX=$(echo "$PUBKEY_FILE" | sed 's/publickey_ed25519_//')
  NODE_IP=$(hostname -I | awk '{print $1}')
  NODE_URL="http://$NODE_IP:$CUSTOM_NODE_PORT"

  echo "{ \"0x$PUBKEY_HEX\": \"$NODE_URL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peer list created with this node: 0x$PUBKEY_HEX\e[0m"

  echo -e "\e[91m🔄 Restarting node to apply peer list changes...\e[0m"
  systemctl restart demos-node
else
  echo -e "\e[91m⚠️ No public key found. Skipping peer list configuration.\e[0m"
fi

# === Backup identity keys ===
echo -e "\e[91m📁 Backing up identity keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp /opt/demos-node/.demos_identity "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No .demos_identity file found.\e[0m"
cp /opt/demos-node/publickey_ed25519_* "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No publickey file found.\e[0m"

echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

touch "$STEP_MARKER"
# === Start node to trigger key generation ===
echo -e "\e[91m🚀 Starting Demos Node to generate identity keys...\e[0m"
systemctl restart demos-node

# === Wait for key generation ===
echo -e "\e[91m⏳ Waiting for identity keys to be generated by the node...\e[0m"
MAX_WAIT=120
INTERVAL=10
WAITED=0

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f /opt/demos-node/.demos_identity ] && ls /opt/demos-node/publickey_ed25519_* &>/dev/null; then
    echo -e "\e[91m✅ Identity keys detected.\e[0m"
    break
  fi
  echo -e "\e[91m⌛ Still waiting... ($WAITED/$MAX_WAIT seconds)\e[0m"
  sleep "$INTERVAL"
  WAITED=$((WAITED + INTERVAL))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  echo -e "\e[91m❌ Identity keys were not generated within 2 minutes.\e[0m"
  echo -e "\e[91m❌ Node setup is incomplete. demos_peerlist.json cannot be configured without keys.\e[0m"
  echo -e "\e[91mPlease check the node logs and restart manually:\e[0m"
  echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"
  exit 1
fi

# === Configure demos_peerlist.json automatically ===
echo -e "\e[91m🔗 Configuring demos_peerlist.json with this node's public key...\e[0m"

cd /opt/demos-node
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls publickey_ed25519_* 2>/dev/null | head -n 1)

if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX=$(echo "$PUBKEY_FILE" | sed 's/publickey_ed25519_//')
  NODE_IP=$(hostname -I | awk '{print $1}')
  NODE_URL="http://$NODE_IP:$CUSTOM_NODE_PORT"

  echo "{ \"0x$PUBKEY_HEX\": \"$NODE_URL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peer list created with this node: 0x$PUBKEY_HEX\e[0m"

  echo -e "\e[91m🔄 Restarting node to apply peer list changes...\e[0m"
  systemctl restart demos-node
else
  echo -e "\e[91m⚠️ No public key found. Skipping peer list configuration.\e[0m"
fi

# === Backup identity keys ===
echo -e "\e[91m📁 Backing up identity keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp /opt/demos-node/.demos_identity "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No .demos_identity file found.\e[0m"
cp /opt/demos-node/publickey_ed25519_* "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No publickey file found.\e[0m"

echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

touch "$STEP_MARKER"

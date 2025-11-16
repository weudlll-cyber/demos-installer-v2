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
  CUSTOM_NODE_PORT=${CUSTOM_NODE_PORT:-$DEFAULT_NODE_PORT}
else
  CUSTOM_NODE_PORT=$DEFAULT_NODE_PORT
fi

if ss -tuln | grep -q ":$DEFAULT_DB_PORT "; then
  echo -e "\e[91m⚠️ Port $DEFAULT_DB_PORT is already in use.\e[0m"
  read -p "👉 Enter a different port for the DB (default $DEFAULT_DB_PORT): " CUSTOM_DB_PORT
  CUSTOM_DB_PORT=${CUSTOM_DB_PORT:-$DEFAULT_DB_PORT}
else
  CUSTOM_DB_PORT=$DEFAULT_DB_PORT
fi

# === Helpers ===
ENV_PATH="/opt/demos-node/.env"

safe_set_env() {
  local key="$1"
  local val="$2"
  if [ -f "$ENV_PATH" ] && grep -q "^${key}=" "$ENV_PATH"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_PATH"
  else
    echo "${key}=${val}" >> "$ENV_PATH"
  fi
}

detect_public_ip() {
  # Prefer IPv4, fallback IPv6, then localhost
  local ip
  ip="$(curl -4 -s ifconfig.co || true)"
  if [ -z "$ip" ]; then
    ip="$(curl -6 -s ifconfig.co || true)"
  fi
  echo "${ip:-localhost}"
}

url_from_ip_port() {
  local ip="$1"
  local port="$2"
  if [[ "$ip" == *:* ]]; then
    echo "http://[$ip]:$port"
  else
    echo "http://$ip:$port"
  fi
}

# === Configure .env in /opt/demos-node ===
if [ ! -f "$ENV_PATH" ]; then
  echo -e "\e[91m🔧 Generating .env configuration...\e[0m"

  if [ -f /opt/demos-node/env.example ]; then
    cp /opt/demos-node/env.example "$ENV_PATH"
    echo -e "\e[91m✅ Loaded template from /opt/demos-node/env.example\e[0m"
  else
    touch "$ENV_PATH"
    echo -e "\e[91m⚠️ env.example not found. Creating empty .env\e[0m"
  fi
fi

PUBLIC_IP="$(detect_public_ip)"
DEFAULT_URL="$(url_from_ip_port "$PUBLIC_IP" "$CUSTOM_NODE_PORT")"

echo -e "\e[91m🌐 Detected public IP: $PUBLIC_IP\e[0m"
echo -e "\e[91m🔧 Setting EXPOSED_URL to: $DEFAULT_URL\e[0m"

safe_set_env "EXPOSED_URL" "$DEFAULT_URL"
safe_set_env "NODE_PORT" "$CUSTOM_NODE_PORT"
safe_set_env "DB_PORT" "$CUSTOM_DB_PORT"

# === Kill conflicting PostgreSQL process based on .env DB_PORT ===
DB_PORT=$(grep "^DB_PORT=" "$ENV_PATH" | cut -d'=' -f2)
DB_PORT=${DB_PORT:-$DEFAULT_DB_PORT}
echo -e "\e[91mℹ️ Using DB_PORT from .env: $DB_PORT\e[0m"

if ss -tuln | grep -q ":$DB_PORT "; then
  echo -e "\e[91m⚠️ Port $DB_PORT appears to be in use.\e[0m"
  OWNER=$(sudo lsof -iTCP -sTCP:LISTEN -P -n | awk -v p=":$DB_PORT" '$9 ~ p {print $1}' | head -n1)
  echo -e "\e[91m🔎 Detected process: ${OWNER:-unknown} on $DB_PORT\e[0m"
  echo -e "\e[91m🔪 Attempting to stop process on port $DB_PORT...\e[0m"
  sudo lsof -ti :$DB_PORT | xargs -r sudo kill -9 || true
  sleep 1
  if ss -tuln | grep -q ":$DB_PORT "; then
    echo -e "\e[91m❌ Could not free DB port $DB_PORT. Please resolve manually and re-run.\e[0m"
    exit 1
  else
    echo -e "\e[91m✅ Port $DB_PORT is now free.\e[0m"
  fi
else
  echo -e "\e[91m✅ No conflict detected on DB port $DB_PORT.\e[0m"
fi

# === Start node to trigger key generation ===
echo -e "\e[91m🚀 Starting Demos Node to generate identity keys...\e[0m"
systemctl restart demos-node

# === Wait for identity keys ===
echo -e "\e[91m⏳ Waiting for identity keys to be generated...\e[0m"
MAX_WAIT=180
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
  echo -e "\e[91m❌ Identity keys were not generated within $(($MAX_WAIT/60)) minutes.\e[0m"
  echo -e "\e[91m❌ Node setup is incomplete. demos_peerlist.json cannot be configured without keys.\e[0m"
  echo -e "\e[91mPlease check the node logs and restart manually:\e[0m"
  echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"
  exit 1
fi

# === Configure demos_peerlist.json from EXPOSED_URL ===
echo -e "\e[91m🔗 Configuring demos_peerlist.json with this node's public key...\e[0m"
cd /opt/demos-node
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls publickey_ed25519_* 2>/dev/null | head -n 1)

if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX=$(echo "$PUBKEY_FILE" | sed 's/publickey_ed25519_//')
  EXPOSED_URL=$(grep "^EXPOSED_URL=" "$ENV_PATH" | cut -d'=' -f2)
  if [ -z "$EXPOSED_URL" ]; if missing
    EXPOSED_URL="$(url_from_ip_port "$PUBLIC_IP" "$CUSTOM_NODE_PORT")"
  fi

  echo "{ \"0x$PUBKEY_HEX\": \"$EXPOSED_URL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peer list created for 0x$PUBKEY_HEX\e[0m"
  echo -e "\e[91m🌐 Advertised URL: $EXPOSED_URL\e[0m"

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

# === Final health checks ===
echo -e "\e[91m🔎 Running final health checks...\e[0m"
if systemctl is-active --quiet demos-node; then
  echo -e "\e[91m✅ Service active.\e[0m"
else
  echo -e "\e[91m❌ Service not active.\e[0m"
  sudo journalctl -u demos-node --no-pager --since "5 minutes ago" || true
  exit 1
fi

# === Done ===
touch "$STEP_MARKER"
echo -e "\e[91m✅ [07] Finalization completed successfully.\e[0m"
echo -e "\e[91m🎉 Your Demos Node is configured, keys backed up, and peer list set.\e[0m"

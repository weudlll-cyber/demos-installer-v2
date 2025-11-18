#!/bin/bash
# Step 07: Finalize Demos Node installation
# Configures .env, resolves DB port issues, sets peer list, backs up keys, verifies helpers, and runs a smoke test.

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

# === Defaults ===
DEFAULT_NODE_PORT=53550
DEFAULT_DB_PORT=5332
ENV_PATH="/opt/demos-node/.env"

# === Port conflict check (node port) ===
echo -e "\e[91m🔍 Checking for port conflicts...\e[0m"
if ss -tuln | grep -q ":$DEFAULT_NODE_PORT[[:space:]]"; then
  echo -e "\e[91m⚠️ Port $DEFAULT_NODE_PORT is already in use.\e[0m"
  read -p "👉 Enter a different port for the node (press Enter to keep $DEFAULT_NODE_PORT): " CUSTOM_NODE_PORT
  CUSTOM_NODE_PORT=${CUSTOM_NODE_PORT:-$DEFAULT_NODE_PORT}
else
  CUSTOM_NODE_PORT=$DEFAULT_NODE_PORT
fi

# === Helper functions ===
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
  local ip
  ip="$(curl -4 -s ifconfig.me || true)"
  if [ -z "$ip" ]; then
    ip="$(curl -6 -s ifconfig.me || true)"
  fi
  echo "${ip:-127.0.0.1}"
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

kill_port_if_listening() {
  local port="$1"
  sudo lsof -ti :"$port" | xargs -r sudo kill -9 || true
  sleep 2
  ss -tuln | grep -q ":$port[[:space:]]" && return 1 || return 0
}

# === Configure .env in /opt/demos-node ===
echo -e "\e[91m🔧 Generating .env configuration...\e[0m"
if [ ! -f "$ENV_PATH" ]; then
  if [ -f /opt/demos-node/env.example ]; then
    cp /opt/demos-node/env.example "$ENV_PATH"
    echo -e "\e[91m✅ Loaded template from /opt/demos-node/env.example\e[0m"
  else
    touch "$ENV_PATH"
    echo -e "\e[91m⚠️ env.example not found. Created empty .env\e[0m"
  fi
else
  echo -e "\e[91mℹ️ .env exists. Updating critical keys...\e[0m"
fi

PUBLIC_IP="$(detect_public_ip)"
EXPOSED_URL="$(url_from_ip_port "$PUBLIC_IP" "$CUSTOM_NODE_PORT")"

echo -e "\e[91m🌐 Detected public IP: $PUBLIC_IP\e[0m"
echo -e "\e[91m🔧 Setting EXPOSED_URL to: $EXPOSED_URL\e[0m"

safe_set_env "EXPOSED_URL" "$EXPOSED_URL"
safe_set_env "NODE_PORT" "$CUSTOM_NODE_PORT"

ENV_DB_PORT="$(grep "^DB_PORT=" "$ENV_PATH" | cut -d'=' -f2 || true)"
DB_PORT="${ENV_DB_PORT:-$DEFAULT_DB_PORT}"
safe_set_env "DB_PORT" "$DB_PORT"
echo -e "\e[91mℹ️ Using DB_PORT: $DB_PORT\e[0m"

# === Ensure DB port is free BEFORE first restart ===
echo -e "\e[91m🔪 Ensuring PostgreSQL on port $DB_PORT is stopped before restart...\e[0m"
if ! kill_port_if_listening "$DB_PORT"; then
  echo -e "\e[91m❌ Port $DB_PORT is still occupied. Attempting to stop system PostgreSQL service...\e[0m"
  sudo systemctl stop postgresql >/dev/null 2>&1 || true
  if ! kill_port_if_listening "$DB_PORT"; then
    echo -e "\e[91m❌ PostgreSQL still bound to port $DB_PORT. Please stop it manually and re-run.\e[0m"
    exit 1
  fi
fi
echo -e "\e[91m✅ Port $DB_PORT is free.\e[0m"

# === Start node to trigger key generation ===
echo -e "\e[91m🚀 Starting Demos Node to generate identity keys...\e[0m"
systemctl restart demos-node || true

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
  echo -e "\e[91mPlease check logs:\e[0m"
  echo -e "\e[91msudo journalctl -u demos-node --no-pager --since \"10 minutes ago\"\e[0m"
  exit 1
fi

# === Configure demos_peerlist.json from EXPOSED_URL ===
echo -e "\e[91m🔗 Configuring demos_peerlist.json with this node's public key...\e[0m"
cd /opt/demos-node || true
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls publickey_ed25519_* 2>/dev/null | head -n 1 || true)

if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX="${PUBKEY_FILE#publickey_ed25519_}"
  PUBKEY_HEX="${PUBKEY_HEX#0x}"
  EXPOSED_URL_VAL="$(grep "^EXPOSED_URL=" "$ENV_PATH" | cut -d'=' -f2 || true)"
  [ -z "$EXPOSED_URL_VAL" ] && EXPOSED_URL_VAL="$EXPOSED_URL"
  echo "{ \"0x$PUBKEY_HEX\": \"$EXPOSED_URL_VAL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peer list created for 0x$PUBKEY_HEX\e[0m"
  echo -e "\e[91m🌐 Advertised URL: $EXPOSED_URL_VAL\e[0m"
  echo -e "\e[91m🔄 Restarting node to apply peer list changes...\e[0m"
  systemctl restart demos-node || true
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

# === Final health check ===
echo -e "\e[91m🔎 Running final health checks...\e[0m"
if systemctl is-active --quiet demos-node; then
  echo -e "\e[91m✅ Service active.\e[0m"
else
  echo -e "\e[91m❌ Service not active.\e[0m"
  sudo journalctl -u demos-node --no-pager --since "5 minutes ago" || true
  exit 1
fi

# === Helper verification ===
echo -e "\e[91m🧰 Verifying helper scripts...\e[0m"
HELPERS=("check_demos_node" "restart_demos_node" "logs_demos_node")
MISSING=()

for helper in "${HELPERS[@]}"; do
  if command -v "$helper" &>/dev/null; then
    echo -e "\e[91m✅ $helper is installed and in PATH.\e[0m"
  else
    echo -e "\e[91m❌ $helper not found.\e[0m"
    MISSING+=("$helper")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo -e "\e[91m❌ Step 07 failed: Missing helpers: ${MISSING[*]}\e[0m"
  echo -e "\e[91mFix by running the updater manually:\e[0m"
  echo -e "\e[91m  curl -fsSL https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/update_helpers_v1.sh -o /usr/local/bin/update_helpers && chmod +x /usr/local/bin/update_helpers\e[0m"
  echo -e "\e[91m  update_helpers\e[0m"
  echo -e "\e[91mThen restart:\e[0m"
  echo -e "\e[91m  sudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

# === Smoke test: show status and health ===
echo -e "\e[91m🚦 Smoke test: helper outputs\e[0m"
if command -v check_demos_node &>/dev/null; then
  check_demos_node --status || true
fi
if command -v logs_demos_node &>/dev/null; then
  logs_demos_node --health || true
fi

# === Done ===
touch "$STEP_MARKER"
echo -e "\e[91m✅ [07] Finalization completed successfully.\e[0m"
echo -e "\e[91m🎉 Your Demos Node is configured, keys backed up, peer list set, and helpers verified.\e[0m"

#!/bin/bash
# Step 07a: Configure .env, ensure DB port is free, set public EXPOSED_URL, run node once to generate keys, then stop for edits

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🎛️ [07a] Finalizing env and ports...\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/07a_finalize_env_ports.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [07a] Already completed. Skipping.\e[0m"
  exit 0
fi

# Defaults
DEFAULT_NODE_PORT=53550
DEFAULT_DB_PORT=5332
ENV_PATH="/opt/demos-node/.env"

# Helpers
safe_set_env() {
  local key="$1"; local val="$2"
  if [ -f "$ENV_PATH" ] && grep -q "^${key}=" "$ENV_PATH"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_PATH"
  else
    echo "${key}=${val}" >> "$ENV_PATH"
  fi
}
detect_public_ip() {
  local ip; ip="$(curl -4 -s ifconfig.me || true)"
  [ -z "$ip" ] && ip="$(curl -6 -s ifconfig.me || true)"
  echo "${ip:-127.0.0.1}"
}
url_from_ip_port() {
  local ip="$1"; local port="$2"
  [[ "$ip" == *:* ]] && echo "http://[$ip]:$port" || echo "http://$ip:$port"
}
kill_port_if_listening() {
  local port="$1"
  sudo lsof -ti :"$port" | xargs -r sudo kill -9 || true
  sleep 2
  ss -tuln | grep -q ":$port[[:space:]]" && return 1 || return 0
}

# Node port selection (keep default unless user overrides)
CUSTOM_NODE_PORT=$DEFAULT_NODE_PORT
echo -e "\e[91m🔧 Using NODE_PORT: $CUSTOM_NODE_PORT\e[0m"

# Ensure .env exists and set keys
echo -e "\e[91m🔧 Preparing .env...\e[0m"
if [ ! -f "$ENV_PATH" ]; then
  if [ -f /opt/demos-node/env.example ]; then
    cp /opt/demos-node/env.example "$ENV_PATH"
    echo -e "\e[91m✅ Loaded template from env.example\e[0m"
  else
    touch "$ENV_PATH"
    echo -e "\e[91m⚠️ env.example not found. Created empty .env\e[0m"
  fi
else
  echo -e "\e[91mℹ️ .env exists. Updating critical keys...\e[0m"
fi

PUBLIC_IP="$(detect_public_ip)"
EXPOSED_URL="$(url_from_ip_port "$PUBLIC_IP" "$CUSTOM_NODE_PORT")"

echo -e "\e[91m🌐 Public IP: $PUBLIC_IP\e[0m"
echo -e "\e[91m🔧 EXPOSED_URL: $EXPOSED_URL\e[0m"

safe_set_env "EXPOSED_URL" "$EXPOSED_URL"
safe_set_env "NODE_PORT" "$CUSTOM_NODE_PORT"

ENV_DB_PORT="$(grep "^DB_PORT=" "$ENV_PATH" | cut -d'=' -f2 || true)"
DB_PORT="${ENV_DB_PORT:-$DEFAULT_DB_PORT}"
safe_set_env "DB_PORT" "$DB_PORT"
echo -e "\e[91mℹ️ Using DB_PORT: $DB_PORT\e[0m"

# === Ensure services stopped and port free before starting node to generate keys ===
echo -e "\e[91m🛑 Stopping demos-node and preventing automatic restart while preparing DB port...\e[0m"
sudo systemctl stop demos-node >/dev/null 2>&1 || true
sudo systemctl mask demos-node >/dev/null 2>&1 || true

echo -e "\e[91m🛑 Stopping system PostgreSQL to free port $DB_PORT...\e[0m"
sudo systemctl stop postgresql >/dev/null 2>&1 || true
sudo systemctl disable postgresql >/dev/null 2>&1 || true

if ! kill_port_if_listening "$DB_PORT"; then
  echo -e "\e[91m❌ Port $DB_PORT still occupied after stopping postgresql. Inspect:\e[0m"
  echo -e "\e[91m  ss -tuln | grep $DB_PORT\e[0m"
  echo -e "\e[91m  sudo lsof -i :$DB_PORT\e[0m"
  echo -e "\e[91mAborting to avoid restart loop.\e[0m"
  exit 1
fi
echo -e "\e[91m✅ DB port $DB_PORT is free.\e[0m"

# Start node once to trigger key generation
echo -e "\e[91m🔁 Temporarily enabling and starting demos-node to generate identity keys...\e[0m"
sudo systemctl unmask demos-node >/dev/null 2>&1 || true
sudo systemctl start demos-node || true

# Wait for identity keys to be generated
echo -e "\e[91m⏳ Waiting for identity keys to be generated (up to 3 minutes)...\e[0m"
MAX_WAIT=180
INTERVAL=5
WAITED=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f /opt/demos-node/.demos_identity ] && ls /opt/demos-node/publickey_ed25519_* &>/dev/null; then
    echo -e "\e[91m✅ Identity keys detected.\e[0m"
    break
  fi
  sleep "$INTERVAL"
  WAITED=$((WAITED + INTERVAL))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  echo -e "\e[91m❌ Identity keys not generated within $((MAX_WAIT/60)) minutes. Check logs:\e[0m"
  echo -e "\e[91m  sudo journalctl -u demos-node --no-pager -n 200\e[0m"
  # leave node running for debugging, but mark failure
  exit 1
fi

# After keys generated, stop node and mask it so operator can safely edit .env / peerlist
echo -e "\e[91m🛑 Stopping demos-node to allow .env/peerlist edits...\e[0m"
sudo systemctl stop demos-node || true
sudo systemctl mask demos-node >/dev/null 2>&1 || true

echo -e "\e[91mℹ️ demos-node stopped and masked. You may now edit /opt/demos-node/.env or /opt/demos-node/demos_peerlist.json before unmasking and starting the service.\e[0m"
echo -e "\e[91mExample: sudo nano /opt/demos-node/.env ; sudo systemctl unmask demos-node ; sudo systemctl start demos-node\e[0m"

touch "$STEP_MARKER"
echo -e "\e[91m✅ [07a] Env and ports finalized. Keys generated and node stopped for edits.\e[0m"

#!/bin/bash
# Step 07a: Configure .env, ensure DB port is free, set public EXPOSED_URL, restart node to trigger keys

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🎛️ [07a] Finalizing env and ports...\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/07a_finalize_env_ports.done"
mkdir -p "$MARKER_DIR"

[ -f "$STEP_MARKER" ] && { echo -e "\e[91m✅ [07a] Already completed. Skipping.\e[0m"; exit 0; }

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

# Node port selection
echo -e "\e[91m🔍 Checking node port conflicts...\e[0m"
CUSTOM_NODE_PORT=$DEFAULT_NODE_PORT
if ss -tuln | grep -q ":$DEFAULT_NODE_PORT[[:space:]]"; then
  echo -e "\e[91m⚠️ Port $DEFAULT_NODE_PORT in use. You can adjust later in .env.\e[0m"
fi

# Ensure .env exists and set keys
echo -e "\e[91m🔧 Preparing .env...\e[0m"
[ -f "$ENV_PATH" ] || { [ -f /opt/demos-node/env.example ] && cp /opt/demos-node/env.example "$ENV_PATH" || touch "$ENV_PATH"; }

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

# Stop PostgreSQL first, then free port
echo -e "\e[91m🛑 Stopping system PostgreSQL to free port $DB_PORT...\e[0m"
sudo systemctl stop postgresql >/dev/null 2>&1 || true
sudo systemctl disable postgresql >/dev/null 2>&1 || true

if ! kill_port_if_listening "$DB_PORT"; then
  echo -e "\e[91m❌ Port $DB_PORT still occupied. Check:\e[0m"
  echo -e "\e[91m  ss -tuln | grep $DB_PORT\e[0m"
  echo -e "\e[91m  sudo lsof -i :$DB_PORT\e[0m"
  exit 1
fi
echo -e "\e[91m✅ DB port $DB_PORT is free.\e[0m"

# Restart node to trigger key generation
echo -e "\e[91m🚀 Restarting Demos Node to trigger key generation...\e[0m"
systemctl restart demos-node || true

touch "$STEP_MARKER"
echo -e "\e[91m✅ [07a] Env and ports finalized.\e[0m"

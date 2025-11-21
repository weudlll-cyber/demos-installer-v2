#!/bin/bash
# Step 07b: Configure peerlist, back up keys, ensure public binding,
# unmask/start node, probe endpoints, verify helpers, smoke tests

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🧩 [07b] Finalizing peerlist, backups, and health...\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/07b_finalize_v1.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [07b] Already completed. Skipping.\e[0m"
  exit 0
fi

# Defaults
ENV_PATH="/opt/demos-node/.env"
DEFAULT_NODE_PORT=53550

# Helpers
detect_public_ip() {
  local ip; ip="$(curl -4 -s ifconfig.me || true)"
  [ -z "$ip" ] && ip="$(curl -6 -s ifconfig.me || true)"
  echo "${ip:-127.0.0.1}"
}
url_from_ip_port() {
  local ip="$1"; local port="$2"
  [[ "$ip" == *:* ]] && echo "http://[$ip]:$port" || echo "http://$ip:$port"
}
safe_set_env() {
  local key="$1"; local val="$2"
  if [ -f "$ENV_PATH" ] && grep -q "^${key}=" "$ENV_PATH"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_PATH"
  else
    echo "${key}=${val}" >> "$ENV_PATH"
  fi
}
port_bound_addresses() {
  local port="$1"
  ss -tuln | awk -v p=":$port" '$0 ~ p {print $5}' | sed -E 's/:[0-9]+$//' | sort -u || true
}
http_probe() {
  local url="$1"
  curl -fsS --max-time 5 "$url" >/dev/null 2>&1
}

# Read current ports/URL
NODE_PORT="$(grep '^NODE_PORT=' "$ENV_PATH" | cut -d'=' -f2 || echo "$DEFAULT_NODE_PORT")"
PUBLIC_IP="$(detect_public_ip)"
EXPOSED_URL="$(grep '^EXPOSED_URL=' "$ENV_PATH" | cut -d'=' -f2 || true)"
[ -z "$EXPOSED_URL" ] && EXPOSED_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")" && safe_set_env "EXPOSED_URL" "$EXPOSED_URL"

# Wait briefly for keys (if not already present)
echo -e "\e[91m⏳ Checking for identity keys...\e[0m"
MAX_WAIT=120; INTERVAL=10; WAITED=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f /opt/demos-node/.demos_identity ] && ls /opt/demos-node/publickey_ed25519_* &>/dev/null; then
    echo -e "\e[91m✅ Identity keys detected.\e[0m"; break
  fi
  echo -e "\e[91m⌛ Still waiting... ($WAITED/$MAX_WAIT)\e[0m"
  sleep "$INTERVAL"; WAITED=$((WAITED + INTERVAL))
done

# Configure peerlist
echo -e "\e[91m🔗 Configuring demos_peerlist.json...\e[0m"
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls /opt/demos-node/publickey_ed25519_* 2>/dev/null | head -n 1 || true)
if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX="${PUBKEY_FILE#publickey_ed25519_}"
  echo "{ \"0x$PUBKEY_HEX\": \"$EXPOSED_URL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peerlist set for 0x$PUBKEY_HEX -> $EXPOSED_URL\e[0m"
else
  echo -e "\e[91m⚠️ No public key found. Skipping peerlist.\e[0m"
fi

# Backup keys
echo -e "\e[91m📁 Backing up keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /opt/demos-node/.demos_identity "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No .demos_identity file.\e[0m"
cp /opt/demos-node/publickey_ed25519_* "$BACKUP_DIR/" 2>/dev/null || echo -e "\e[91m⚠️ No public key files.\e[0m"
echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

# Unmask and start node service
echo -e "\e[91m🔁 Unmasking and starting demos-node service...\e[0m"
sudo systemctl unmask demos-node >/dev/null 2>&1 || true
sudo systemctl restart demos-node || true

# Service health
echo -e "\e[91m🔎 Service health...\e[0m"
if ! systemctl is-active --quiet demos-node; then
  echo -e "\e[91m❌ Service not active.\e[0m"
  sudo journalctl -u demos-node --no-pager -n 50 || true
  exit 1
fi
echo -e "\e[91m✅ Service active.\e[0m"

# Binding check and endpoint probes (public IP)
echo -e "\e[91m🌐 Binding check on port $NODE_PORT...\e[0m"
BOUND_ADDRS="$(port_bound_addresses "$NODE_PORT" | tr '\n' ' ')"
echo -e "\e[91mℹ️ Bound addresses: $BOUND_ADDRS\e[0m"

if echo "$BOUND_ADDRS" | grep -q "127.0.0.1"; then
  echo -e "\e[91m⚠️ Bound to localhost. Setting BIND_ADDRESS=0.0.0.0 and restarting.\e[0m"
  safe_set_env "BIND_ADDRESS" "0.0.0.0"
  systemctl restart demos-node || true
  sleep 2
  BOUND_ADDRS="$(port_bound_addresses "$NODE_PORT" | tr '\n' ' ')"
  echo -e "\e[91mℹ️ New bound addresses: $BOUND_ADDRS\e[0m"
fi

HEALTH_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/health"
STATUS_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/status"
METRICS_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/metrics"

echo -e "\e[91m🌐 Probing: $HEALTH_URL\e[0m"
if http_probe "$HEALTH_URL"; then
  echo -e "\e[91m✅ /health responded.\e[0m"
else
  echo -e "\e[91m⚠️ /health did not respond. Checking /status and /metrics...\e[0m"
  if http_probe "$STATUS_URL"; then
    echo -e "\e[91m✅ /status responded.\e[0m"
  elif http_probe "$METRICS_URL"; then
    echo -e "\e[91m✅ /metrics responded.\e[0m"
  else
    echo -e "\e[91m❌ No public endpoint responded.\e[0m"
    sudo journalctl -u demos-node --no-pager -n 50 || true
  fi
fi

# Helper verification
echo -e "\e[91m🧰 Verifying helpers...\e[0m"
HELPERS=("check_demos_node" "restart_demos_node" "logs_demos_node")
MISSING=()
for h in "${HELPERS[@]}"; do
  if command -v "$h" &>/dev/null; then
    echo -e "\e[91m✅ $h in PATH.\e[0m"
  else
    echo -e "\e[91m❌ $h missing.\e[0m"; MISSING+=("$h")
  fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo -e "\e[91m❌ Missing helpers: ${MISSING[*]}\e[0m"; exit 1
fi

# Smoke test
echo -e "\e[91m🚦 Smoke test outputs...\e[0m"
check_demos_node --status || true
logs_demos_node --health || true

touch "$STEP_MARKER"
echo -e "\e[91m✅ [07b] Peerlist, backups, and health finalized. Node unmasked and running.\e[0m"

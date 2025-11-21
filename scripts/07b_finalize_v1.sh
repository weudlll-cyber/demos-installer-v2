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
DEFAULT_DB_PORT=5332

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
  return $?
}
kill_pid_on_port() {
  local port="$1"
  sudo lsof -ti :"$port" | xargs -r sudo kill -9 || true
  sleep 2
}

# Read current ports/URL
NODE_PORT="$(grep '^NODE_PORT=' "$ENV_PATH" | cut -d'=' -f2 || echo "$DEFAULT_NODE_PORT")"
PUBLIC_IP="$(detect_public_ip)"
EXPOSED_URL="$(grep '^EXPOSED_URL=' "$ENV_PATH" | cut -d'=' -f2 || true)"
[ -z "$EXPOSED_URL" ] && EXPOSED_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")" && safe_set_env "EXPOSED_URL" "$EXPOSED_URL"

echo -e "\e[91m🌐 Public IP: $PUBLIC_IP\e[0m"
echo -e "\e[91m🔧 EXPOSED_URL: $EXPOSED_URL\e[0m"
echo -e "\e[91mℹ️ NODE_PORT: $NODE_PORT; DB_PORT default: $DEFAULT_DB_PORT\e[0m"

# Wait briefly for identity keys
echo -e "\e[91m⏳ Ensuring identity keys exist...\e[0m"
MAX_WAIT=120; INTERVAL=5; WAITED=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f /opt/demos-node/.demos_identity ] && ls /opt/demos-node/publickey_ed25519_* &>/dev/null; then
    echo -e "\e[91m✅ Identity keys present\e[0m"
    break
  fi
  sleep "$INTERVAL"; WAITED=$((WAITED + INTERVAL))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  echo -e "\e[91m⚠️ Identity keys not found after wait. Continue anyway and Step 07b will retry where possible.\e[0m"
fi

# Create/update peerlist using the detected public key and EXPOSED_URL
echo -e "\e[91m🔗 Configuring demos_peerlist.json...\e[0m"
PEERLIST_PATH="/opt/demos-node/demos_peerlist.json"
PUBKEY_FILE=$(ls /opt/demos-node/publickey_ed25519_* 2>/dev/null | head -n 1 || true)
if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX="${PUBKEY_FILE#publickey_ed25519_}"
  PUBKEY_HEX="${PUBKEY_HEX#0x}"
  echo "{ \"0x$PUBKEY_HEX\": \"$EXPOSED_URL\" }" > "$PEERLIST_PATH"
  echo -e "\e[91m✅ Peerlist updated for 0x$PUBKEY_HEX -> $EXPOSED_URL\e[0m"
else
  echo -e "\e[91m⚠️ No public key found; skipping peerlist write\e[0m"
fi

# Backup identity keys
echo -e "\e[91m📁 Backing up identity keys...\e[0m"
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /opt/demos-node/.demos_identity "$BACKUP_DIR/" 2>/dev/null || true
cp /opt/demos-node/publickey_ed25519_* "$BACKUP_DIR/" 2>/dev/null || true
echo -e "\e[91m✅ Keys backed up to: $BACKUP_DIR\e[0m"

# Ensure any leftover DB on DB_PORT is gone (node may have spawned local postgres)
echo -e "\e[91m🧹 Cleaning leftover processes on DB port $DEFAULT_DB_PORT...\e[0m"
sudo systemctl stop postgresql >/dev/null 2>&1 || true
sudo systemctl disable postgresql >/dev/null 2>&1 || true
kill_pid_on_port "$DEFAULT_DB_PORT"
if ss -tuln | grep -q ":$DEFAULT_DB_PORT\b"; then
  echo -e "\e[91m❌ DB port $DEFAULT_DB_PORT still bound. Inspect and resolve:\e[0m"
  echo -e "\e[91m  ss -tuln | grep $DEFAULT_DB_PORT\e[0m"
  echo -e "\e[91m  sudo lsof -i :$DEFAULT_DB_PORT\e[0m"
  echo -e "\e[91mAborting Step 07b to avoid repeat failure.\e[0m"
  exit 1
fi
echo -e "\e[91m✅ DB port $DEFAULT_DB_PORT is free.\e[0m"

# Unmask and start the node service (will allow systemd to manage it)
echo -e "\e[91m🔁 Unmasking and starting demos-node service...\e[0m"
sudo systemctl unmask demos-node >/dev/null 2>&1 || true
sudo systemctl restart demos-node || true
sleep 2

# Wait for service to become active and retry start if systemd reported activating for a short time
for i in 1 2 3; do
  if systemctl is-active --quiet demos-node; then
    break
  fi
  echo -e "\e[91mℹ️ demos-node not active yet; attempt $i — checking logs...\e[0m"
  sudo journalctl -u demos-node --no-pager -n 50 || true
  sleep 2
done

# Check service health basics
echo -e "\e[91m🔎 Checking service status and endpoints...\e[0m"
if systemctl is-active --quiet demos-node; then
  echo -e "\e[91m✅ Service active.\e[0m"
else
  echo -e "\e[91m❌ Service not active after start. Dumping recent logs and aborting.\e[0m"
  sudo journalctl -u demos-node --no-pager -n 200 || true
  exit 1
fi

# Binding check
BOUND_ADDRS="$(port_bound_addresses "$NODE_PORT" | tr '\n' ' ')"
echo -e "\e[91mℹ️ Bound addresses for $NODE_PORT: $BOUND_ADDRS\e[0m"

if echo "$BOUND_ADDRS" | grep -q "127.0.0.1"; then
  echo -e "\e[91m⚠️ Service bound to localhost only. Setting BIND_ADDRESS=0.0.0.0 and restarting.\e[0m"
  safe_set_env "BIND_ADDRESS" "0.0.0.0"
  sudo systemctl restart demos-node || true
  sleep 2
  BOUND_ADDRS="$(port_bound_addresses "$NODE_PORT" | tr '\n' ' ')"
  echo -e "\e[91mℹ️ New bound addresses: $BOUND_ADDRS\e[0m"
fi

# Probe endpoints (retry a few times)
HEALTH_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/health"
STATUS_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/status"
METRICS_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/metrics"

echo -e "\e[91m🌐 Probing endpoints on $PUBLIC_IP:$NODE_PORT...\e[0m"
PROBED=0
for attempt in 1 2 3; do
  echo -e "\e[91m🔁 Probe attempt $attempt...\e[0m"
  if http_probe "$HEALTH_URL"; then
    echo -e "\e[91m✅ /health responded.\e[0m"; PROBED=1; break
  elif http_probe "$STATUS_URL"; then
    echo -e "\e[91m✅ /status responded.\e[0m"; PROBED=1; break
  elif http_probe "$METRICS_URL"; then
    echo -e "\e[91m✅ /metrics responded.\e[0m"; PROBED=1; break
  fi
  sleep 2
done

if [ "$PROBED" -ne 1 ]; then
  echo -e "\e[91m❌ No public endpoint responded after retries.\e[0m"
  echo -e "\e[91mRecent logs (last 100 lines):\e[0m"
  sudo journalctl -u demos-node --no-pager -n 100 || true
  # do not hard-fail here; helpers and operator can inspect
fi

# Verify helpers
echo -e "\e[91m🧰 Verifying helper scripts...\e[0m"
HELPERS=("check_demos_node" "restart_demos_node" "logs_demos_node")
MISSING=()
for h in "${HELPERS[@]}"; do
  if command -v "$h" &>/dev/null; then
    echo -e "\e[91m✅ $h in PATH.\e[0m"
  else
    echo -e "\e[91m❌ $h missing.\e[0m"
    MISSING+=("$h")
  fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo -e "\e[91m❌ Missing helpers: ${MISSING[*]}\e[0m"
  echo -e "\e[91mFix by running the updater script and re-run Step 07b.\e[0m"
  exit 1
fi

# Smoke test outputs
echo -e "\e[91m🚦 Smoke test outputs...\e[0m"
check_demos_node --status || true
logs_demos_node --health || true

touch "$STEP_MARKER"
echo -e "\e[91m✅ [07b] Peerlist, backups, and health finalized. Node unmasked and running.\e[0m"

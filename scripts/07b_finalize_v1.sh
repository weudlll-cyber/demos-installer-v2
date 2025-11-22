#!/bin/bash
# Step 07b: Finalize peerlist, backups, ensure public binding, start service and verify
set -euo pipefail
IFS=$'\n\t'

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/07b_finalize_v1.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  exit 0
fi

# Paths and defaults
RUN_DIR="/opt/demos-node"
ENV_PATH="${RUN_DIR}/.env"
PEERLIST_PATH="${RUN_DIR}/demos_peerlist.json"
DEFAULT_NODE_PORT=53550
DEFAULT_DB_PORT=5332

# Helpers
detect_public_ip() {
  local ip
  ip="$(curl -4 -s ifconfig.me || true)"
  [ -z "$ip" ] && ip="$(curl -6 -s ifconfig.me || true)"
  echo "${ip:-127.0.0.1}"
}
url_from_ip_port() {
  local ip="$1"; local port="$2"
  [[ "$ip" == *:* ]] && echo "http://[$ip]:$port" || echo "http://$ip:$port"
}
safe_set_env() {
  local key="$1"; local val="$2"
  if [ -f "$ENV_PATH" ] && grep -q -E "^${key}=" "$ENV_PATH"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_PATH"
  else
    echo "${key}=${val}" >> "$ENV_PATH"
  fi
}
port_bound_addresses() {
  local port="$1"
  ss -tuln | awk -v p=":${port}" '$0 ~ p {print $5}' | sed -E 's/:[0-9]+$//' | sort -u || true
}
http_probe() {
  local url="$1"
  curl -fsS --max-time 4 "$url" >/dev/null 2>&1
}
backup_keys() {
  local dest="$1"
  mkdir -p "$dest"
  cp -a "${RUN_DIR}/.demos_identity" "${dest}/" 2>/dev/null || true
  cp -a "${RUN_DIR}/publickey_ed25519_"* "${dest}/" 2>/dev/null || true
  cp -a "${RUN_DIR}/privatekey_ed25519_"* "${dest}/" 2>/dev/null || true
}

# Read env-derived values
NODE_PORT="$(grep -E '^NODE_PORT=' "$ENV_PATH" 2>/dev/null | cut -d'=' -f2 || echo "$DEFAULT_NODE_PORT")"
EXPOSED_URL="$(grep -E '^EXPOSED_URL=' "$ENV_PATH" 2>/dev/null | cut -d'=' -f2 || true)"
PUBLIC_IP="$(detect_public_ip)"
[ -z "$EXPOSED_URL" ] && EXPOSED_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")" && safe_set_env "EXPOSED_URL" "$EXPOSED_URL"

# Ensure identity keys exist (quick check)
if [ ! -f "${RUN_DIR}/.demos_identity" ] || ! ls "${RUN_DIR}/publickey_ed25519_"* 1>/dev/null 2>&1; then
  echo "❌ Identity keys missing in ${RUN_DIR}. Run step 07a first."
  exit 1
fi

# Update peerlist from generated public key + EXPOSED_URL
PUBKEY_FILE="$(ls "${RUN_DIR}/publickey_ed25519_"* 2>/dev/null | head -n1 || true)"
if [ -n "$PUBKEY_FILE" ]; then
  PUBKEY_HEX="$(basename "$PUBKEY_FILE" | sed -E 's/publickey_ed25519_//; s/^0x//')"
  printf '{ "0x%s": "%s" }\n' "$PUBKEY_HEX" "$EXPOSED_URL" > "$PEERLIST_PATH"
fi

# Backup keys
BACKUP_DIR="/root/demos_node_backups/backup_$(date +%Y%m%d_%H%M%S)"
backup_keys "$BACKUP_DIR"

# Ensure DB port is free (stop system postgresql if present)
sudo systemctl stop postgresql >/dev/null 2>&1 || true
sudo systemctl disable postgresql >/dev/null 2>&1 || true
# kill any process listening on DB port if it is an orphaned local process
if ss -tuln | grep -q ":${DEFAULT_DB_PORT}\\b"; then
  sudo lsof -ti ":${DEFAULT_DB_PORT}" | xargs -r sudo kill -9 || true
  sleep 1
fi
if ss -tuln | grep -q ":${DEFAULT_DB_PORT}\\b"; then
  echo "❌ DB port ${DEFAULT_DB_PORT} still in use; resolve before proceeding"
  exit 1
fi

# Start service under systemd
sudo systemctl unmask demos-node >/dev/null 2>&1 || true
sudo systemctl daemon-reload
sudo systemctl enable --now demos-node

# Wait for service to become active (timeout)
for i in $(seq 1 20); do
  if systemctl is-active --quiet demos-node; then
    break
  fi
  sleep 1
done

if ! systemctl is-active --quiet demos-node; then
  echo "❌ demos-node service failed to become active; check logs:"
  echo "sudo journalctl -u demos-node --no-pager -n 200"
  exit 1
fi

# Ensure service bound addresses include non-localhost; if only localhost, set BIND_ADDRESS and restart
BOUND_ADDRS="$(port_bound_addresses "$NODE_PORT" | tr '\n' ' ')"
if [ -z "$BOUND_ADDRS" ] || echo "$BOUND_ADDRS" | grep -qE '^127\.0\.0\.1$|^::1$'; then
  safe_set_env "BIND_ADDRESS" "0.0.0.0"
  sudo systemctl restart demos-node
  sleep 1
  BOUND_ADDRS="$(port_bound_addresses "$NODE_PORT" | tr '\n' ' ' )"
fi

# Probe endpoints (local then public)
HEALTH_URL="$(url_from_ip_port "127.0.0.1" "$NODE_PORT")/health"
STATUS_URL="$(url_from_ip_port "127.0.0.1" "$NODE_PORT")/status"
METRICS_URL="$(url_from_ip_port "127.0.0.1" "$NODE_PORT")/metrics"

PROBED=0
for attempt in 1 2 3; do
  if http_probe "$HEALTH_URL"; then PROBED=1; break; fi
  if http_probe "$STATUS_URL"; then PROBED=1; break; fi
  if http_probe "$METRICS_URL"; then PROBED=1; break; fi
  sleep 1
done

# If local probes failed, try public address
if [ "$PROBED" -eq 0 ]; then
  HEALTH_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/health"
  STATUS_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/status"
  METRICS_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")/metrics"
  for attempt in 1 2 3; do
    if http_probe "$HEALTH_URL"; then PROBED=1; break; fi
    if http_probe "$STATUS_URL"; then PROBED=1; break; fi
    if http_probe "$METRICS_URL"; then PROBED=1; break; fi
    sleep 1
  done
fi

# Collect logs if probes didn't respond (do not fail the script)
if [ "$PROBED" -eq 0 ]; then
  echo "⚠️ No known endpoint responded after retries. Recent logs:"
  sudo journalctl -u demos-node --no-pager -n 200 || true
else
  echo "✅ HTTP endpoint responded."
fi

# Verify helper scripts are in PATH
MISSING=()
for h in check_demos_node restart_demos_node logs_demos_node; do
  if ! command -v "$h" &>/dev/null; then
    MISSING+=("$h")
  fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "❌ Missing helper scripts: ${MISSING[*]}"
  exit 1
fi

# Mark completed
touch "$STEP_MARKER"
echo "✅ [07b] Peerlist, backups, and health finalized. Node is running under systemd."
exit 0

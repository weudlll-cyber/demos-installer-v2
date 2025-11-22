#!/bin/bash
# Step 07a: Prepare .env, ensure DB port free, run node once to generate keys, then stop (no systemd start)
set -euo pipefail
IFS=$'\n\t'

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/07a_finalize_v1.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo "✅ [07a] Already completed. Skipping."
  exit 0
fi

# Defaults and paths
DEFAULT_NODE_PORT=53550
DEFAULT_DB_PORT=5332
ENV_PATH="/opt/demos-node/.env"
RUN_DIR="/opt/demos-node"
LOGFILE="/var/log/demos-node-first-run.log"

# Helpers
safe_set_env() {
  local key="$1"; local val="$2"
  if [ -f "$ENV_PATH" ] && grep -q -E "^${key}=" "$ENV_PATH"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_PATH"
  else
    echo "${key}=${val}" >> "$ENV_PATH"
  fi
}
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
kill_port_if_listening() {
  local port="$1"
  sudo lsof -ti :"$port" | xargs -r sudo kill -9 || true
  sleep 2
  ss -tuln | grep -q ":${port}\\b" && return 1 || return 0
}

# Choose ports (can be overridden by env before running this script)
NODE_PORT=${NODE_PORT:-$DEFAULT_NODE_PORT}
DB_PORT=${DB_PORT:-$DEFAULT_DB_PORT}

echo "🔧 Using NODE_PORT=${NODE_PORT}, DB_PORT=${DB_PORT}"

# Ensure .env exists (seed from env.example if present)
if [ ! -f "$ENV_PATH" ]; then
  if [ -f "${RUN_DIR}/env.example" ]; then
    cp "${RUN_DIR}/env.example" "$ENV_PATH"
  else
    touch "$ENV_PATH"
  fi
fi

# Detect public IP and set EXPOSED_URL
PUBLIC_IP="$(detect_public_ip)"
EXPOSED_URL="$(url_from_ip_port "$PUBLIC_IP" "$NODE_PORT")"
safe_set_env "EXPOSED_URL" "$EXPOSED_URL"
safe_set_env "NODE_PORT" "$NODE_PORT"
safe_set_env "DB_PORT" "$DB_PORT"

echo "🌐 EXPOSED_URL set to $EXPOSED_URL"
echo "🔧 .env updated at $ENV_PATH"

# Stop system postgresql if present to free DB port
echo "🛑 Stopping system postgresql (if present) to free port ${DB_PORT}..."
sudo systemctl stop postgresql >/dev/null 2>&1 || true
sudo systemctl disable postgresql >/dev/null 2>&1 || true

if ! kill_port_if_listening "$DB_PORT"; then
  echo "❌ Port ${DB_PORT} still in use after attempting to stop postgresql."
  echo "Inspect with: ss -tuln | grep ${DB_PORT}  and sudo lsof -i :${DB_PORT}"
  exit 1
fi
echo "✅ DB port ${DB_PORT} is free."

# Start the node directly (background), capture PID, wait for keys, then stop it
echo "▶️ Starting node once (foreground run in background) to generate keys; logs -> $LOGFILE"
mkdir -p "$(dirname "$LOGFILE")"
cd "$RUN_DIR"

# Ensure clean previous logfile
sudo rm -f "$LOGFILE" || true
sudo touch "$LOGFILE"
sudo chown root:root "$LOGFILE"
sudo chmod 644 "$LOGFILE"

# Run the node script in background (preserve environment)
# NOTE: This runs the same run script but NOT under systemd
sudo -E bash -c "nohup ./run >> '$LOGFILE' 2>&1 & echo \$! > /var/run/demos-node-first-run.pid"

PID_FILE="/var/run/demos-node-first-run.pid"
if [ -f "$PID_FILE" ]; then
  RUN_PID="$(cat "$PID_FILE")"
  echo "Started run (PID $RUN_PID)."
else
  echo "Failed to start run process; check $LOGFILE"
  exit 1
fi

# Wait for identity keys to appear (or timeout)
echo "⏳ Waiting up to 180s for identity keys..."
MAX_WAIT=180
INTERVAL=5
WAITED=0
KEY_DETECTED=0

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if [ -f "${RUN_DIR}/.demos_identity" ] && ls "${RUN_DIR}/publickey_ed25519_"* 1>/dev/null 2>&1; then
    KEY_DETECTED=1
    echo "✅ Identity keys created."
    break
  fi
  # Also watch logfile for a likely "generated" hint
  if grep -qiE "identity|publickey|generated|private key" "$LOGFILE" 2>/dev/null; then
    # give a short grace for files to land
    sleep 2
    if ls "${RUN_DIR}/publickey_ed25519_"* 1>/dev/null 2>&1; then
      KEY_DETECTED=1
      echo "✅ Identity keys detected via logfile."
      break
    fi
  fi
  sleep "$INTERVAL"
  WAITED=$((WAITED + INTERVAL))
done

if [ "$KEY_DETECTED" -ne 1 ]; then
  echo "❌ Identity keys not detected within $((MAX_WAIT/60)) minutes. Check $LOGFILE and journalctl."
  echo "sudo journalctl -u demos-node --no-pager -n 200"
  # attempt to stop the background run to avoid stray process
  if [ -n "${RUN_PID:-}" ]; then
    sudo kill "$RUN_PID" >/dev/null 2>&1 || true
    sudo rm -f "$PID_FILE" || true
  fi
  exit 1
fi

# Stop the background run gracefully
echo "🛑 Stopping the temporary run (PID $RUN_PID)..."
sudo kill "$RUN_PID" >/dev/null 2>&1 || true
sleep 2
# Force kill if still present
if ps -p "$RUN_PID" >/dev/null 2>&1; then
  sudo kill -9 "$RUN_PID" >/dev/null 2>&1 || true
fi
sudo rm -f "$PID_FILE" || true

echo "✅ Node stopped. Keys are ready. Edit ${ENV_PATH} or demos_peerlist.json as needed before finalizing."

# Mark step done
touch "$STEP_MARKER"
exit 0

#!/bin/bash
set -e
IFS=$'\n\t'

# Ensure we're using Bash
if [ -z "$BASH_VERSION" ]; then
  echo "❌ This script must be run with bash. Try: bash install_helpers_v1.sh"
  exit 1
fi

HELPER_DIR="/opt/demos-node/helpers"
GLOBAL_BIN="/usr/local/bin"
MONITOR_LOG="/var/log/demos_node_monitor.log"

mkdir -p "$HELPER_DIR" "$GLOBAL_BIN" || true

# restart helper
cat > "$HELPER_DIR/restart_demos_node.sh" <<'EOF'
#!/bin/bash
set -e
SERVICE="demos-node.service"
echo "🔄 Restarting $SERVICE..."
systemctl restart "$SERVICE"
sleep 2
systemctl status "$SERVICE" --no-pager -l
EOF
chmod 755 "$HELPER_DIR/restart_demos_node.sh"

# backup keys
cat > "$HELPER_DIR/backup_demos_keys.sh" <<'EOF'
#!/bin/bash
set -e
mkdir -p ~/demos-keys
cp /opt/demos-node/.demos_identity ~/demos-keys/.demos_identity 2>/dev/null || true
cp /opt/demos-node/publickey_ed25519_* ~/demos-keys/ 2>/dev/null || true
chmod 600 ~/demos-keys/.demos_identity 2>/dev/null || true
ls -l ~/demos-keys || true
EOF
chmod 700 "$HELPER_DIR/backup_demos_keys.sh"

# stop helper
cat > "$HELPER_DIR/stop_demos_node.sh" <<'EOF'
#!/bin/bash
set -e
SERVICE="demos-node.service"
echo "🛑 Stopping $SERVICE..."
systemctl stop "$SERVICE" || true
systemctl disable --now "$SERVICE" || true
pgrep -f "/opt/demos-node" | xargs -r sudo kill -9 || true
pkill -f "/opt/demos-node/run" || true
lsof -ti :5332 | xargs -r sudo kill -9 || true
lsof -ti :53550 | xargs -r sudo kill -9 || true
docker ps -q --filter "name=demos" | xargs -r docker stop || true
rm -f /run/demos-node.pid /var/run/demos-node.pid /root/.demos_node_setup/installer.lock || true
systemctl status "$SERVICE" --no-pager -l || true
echo "✅ Stop sequence complete"
EOF
chmod 755 "$HELPER_DIR/stop_demos_node.sh"

# health-check script
cat > "$HELPER_DIR/check_demos_node.sh" <<'EOF'
#!/bin/bash
set -e
SERVICE="demos-node.service"
MON_LOG="/var/log/demos_node_monitor.log"

# Load .env for NODE_PORT and EXPOSED_URL
ENV_FILE="/opt/demos-node/.env"
if [ -f "$ENV_FILE" ]; then
  NODE_PORT=$(grep "^NODE_PORT=" "$ENV_FILE" | cut -d'=' -f2)
  EXPOSED_URL=$(grep "^EXPOSED_URL=" "$ENV_FILE" | cut -d'=' -f2)
  [ -z "$EXPOSED_URL" ] && EXPOSED_URL="http://127.0.0.1:$NODE_PORT"
else
  NODE_PORT=53550
  EXPOSED_URL="http://127.0.0.1:$NODE_PORT"
fi
HEALTH_URL="${EXPOSED_URL}/health"

AUTORESTART=0
TAIL_LINES=50

usage(){ echo "Usage: $0 [--status] [--logs=N] [--health] [--autorestart] [--restart]"; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --status) ACTION_STATUS=1 ;;
    --logs=*) ACTION_LOGS=1; TAIL_LINES="${arg#*=}" ;;
    --health) ACTION_HEALTH=1 ;;
    --autorestart) AUTORESTART=1 ;;
    --restart) ACTION_RESTART=1 ;;
    --help) usage ;;
    *) ;;
  esac
done

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$MON_LOG"; }

if [ "${ACTION_STATUS:-0}" = "1" ]; then systemctl status "$SERVICE" --no-pager -l; fi
if [ "${ACTION_LOGS:-0}" = "1" ]; then journalctl -u "$SERVICE" -n "$TAIL_LINES" --no-pager; fi
if [ "${ACTION_RESTART:-0}" = "1" ]; then log "Manual restart requested"; systemctl restart "$SERVICE"; sleep 2; systemctl is-active --quiet "$SERVICE" && log "Service active after restart" || log "Service not active after restart"; exit 0; fi

HEALTH_OK=0
if systemctl is-active --quiet "$SERVICE"; then log "systemd reports $SERVICE running"; HEALTH_OK=1; else log "systemd reports $SERVICE NOT running"; HEALTH_OK=0; fi
if pgrep -f "/opt/demos-node" >/dev/null 2>&1; then log "Process referencing /opt/demos-node exists"; HEALTH_OK=$((HEALTH_OK+1)); else log "No process referencing /opt/demos-node"; fi
if command -v curl >/dev/null 2>&1; then
  if curl -sSf --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then log "HTTP health endpoint OK: $HEALTH_URL"; HEALTH_OK=$((HEALTH_OK+1)); else log "HTTP health endpoint failed or not present: $HEALTH_URL"; fi
else log "curl not present, skipped HTTP health check"; fi

if [ "$HEALTH_OK" -ge 2 ]; then log "Node appears HEALTHY (score=$HEALTH_OK)"; exit 0; else log "Node UNHEALTHY (score=$HEALTH_OK)"; if [ "$AUTORESTART" -eq 1 ]; then log "Auto-restart enabled"; systemctl restart "$SERVICE"; sleep 3; systemctl is-active --quiet "$SERVICE" && log "Service active after auto-restart" && exit 0 || log "Still not active" && exit 2; fi; exit 2; fi
EOF
chmod 755 "$HELPER_DIR/check_demos_node.sh"

# Symlink helpers to /usr/local/bin
ln -sf "$HELPER_DIR/restart_demos_node.sh" "$GLOBAL_BIN/restart_demos_node"
ln -sf "$HELPER_DIR/backup_demos_keys.sh" "$GLOBAL_BIN/backup_demos_keys"
ln -sf "$HELPER_DIR/stop_demos_node.sh" "$GLOBAL_BIN/stop_demos_node"
ln -sf "$HELPER_DIR/check_demos_node.sh" "$GLOBAL_BIN/check_demos_node"
chmod 755 "$GLOBAL_BIN/restart_demos_node" "$GLOBAL_BIN/backup_demos_keys" "$GLOBAL_BIN/stop_demos_node" "$GLOBAL_BIN/check_demos_node" || true

# Ensure monitor log exists
touch "$MONITOR_LOG" || true
chown root:root "$MONITOR_LOG" || true
chmod 644 "$MONITOR_LOG" || true

echo "✅ Helpers installed to $HELPER_DIR and symlinked to $GLOBAL_BIN"

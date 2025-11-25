#!/bin/bash
# stop_demos_node_v1.sh
# - Mask demos-node.service to prevent automated restarts
# - Stop the demos-node.service (graceful stop)
# - Detect container(s) publishing DB port, set restart=no and stop them
# - Wait for host ports to be freed (docker-proxy exit)
# - Create a timestamped clone of /opt/demos-node
set -euo pipefail
IFS=$'\n\t'

UNIT="demos-node.service"
NODE_DIR="/opt/demos-node"
CLONE_BASE="/opt"
DB_PORT=5332
NODE_PORT=53550
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
CLONE_DIR="${CLONE_BASE}/demos-node.clone.${TIMESTAMP}"
WAIT_STOP=20    # seconds to wait for service stop
WAIT_PORT=30    # seconds to wait for ports to free

# red output helpers
info(){ printf "\e[91m%s\e[0m\n" "$*"; }
err(){ printf "\e[91m%s\e[0m\n" "$*" >&2; }

# require root
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (sudo)."
  exit 1
fi

# sanity check node dir
if [ ! -d "$NODE_DIR" ]; then
  err "Node directory not found at $NODE_DIR. Aborting."
  exit 1
fi

# record previous enablement state
PRE_ENABLED=0
if systemctl list-unit-files --type=service --all | grep -q "^${UNIT}"; then
  if systemctl is-enabled --quiet "${UNIT}" 2>/dev/null; then PRE_ENABLED=1; fi
fi

# 1) Mask the unit to prevent automated restarts
info "Masking ${UNIT} to prevent automated restarts"
systemctl mask "${UNIT}" >/dev/null 2>&1 || true

# 2) Stop the service gracefully
info "Stopping ${UNIT} (waiting up to ${WAIT_STOP}s)"
if systemctl list-unit-files --type=service --all | grep -q "^${UNIT}"; then
  systemctl stop "${UNIT}" || info "systemctl stop returned non-zero; continuing"
  for i in $(seq 1 $WAIT_STOP); do
    PID=$(systemctl show -p MainPID --value "${UNIT}" 2>/dev/null || echo 0)
    if [ -z "$PID" ] || [ "$PID" = "0" ]; then
      info "${UNIT} stopped."
      break
    fi
    sleep 1
  done
  PID=$(systemctl show -p MainPID --value "${UNIT}" 2>/dev/null || echo 0)
  if [ -n "$PID" ] && [ "$PID" != "0" ]; then
    err "Service did not exit within ${WAIT_STOP}s (MainPID=${PID}). Attempting to kill PID."
    kill "$PID" 2>/dev/null || true
    sleep 1
  fi
else
  info "Unit ${UNIT} not found; skipping systemd stop."
fi

# 3) Detect Docker container(s) publishing DB_PORT and disable restart + stop them
detect_db_cids(){
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.ID}}\t{{.Ports}}\t{{.Names}}' | awk -v p=":${DB_PORT}->" '$0 ~ p { print $1 }'
}

CIDS="$(detect_db_cids || true)"
if [ -n "$CIDS" ]; then
  info "Found container(s) publishing host port ${DB_PORT}:"
  echo "$CIDS" | while read -r cid; do
    info "  - $cid : setting restart=no and stopping"
    docker update --restart=no "$cid" >/dev/null 2>&1 || err "docker update failed for $cid"
    docker stop --time 10 "$cid" >/dev/null 2>&1 || err "docker stop failed for $cid"
  done
else
  info "No container publishing host port ${DB_PORT} detected; skipping container stop."
fi

# 4) Wait for host ports to free (docker-proxy should exit)
info "Waiting up to ${WAIT_PORT}s for host ports ${DB_PORT} and ${NODE_PORT} to be free"
for i in $(seq 1 $WAIT_PORT); do
  ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" >/dev/null || break
  sleep 1
done

# show final socket state
info "Listening sockets (5332 and 53550):"
ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" || info "none — ports appear free"

# 5) Create a clone of the node directory
info "Creating clone of ${NODE_DIR} at ${CLONE_DIR} (preserves ownership and permissions)"
if command -v rsync >/dev/null 2>&1; then
  rsync -aHAX --numeric-ids --exclude 'node_modules' "$NODE_DIR/" "$CLONE_DIR/" || {
    err "rsync failed while cloning; aborting clone step."
    exit 1
  }
else
  cp -a "$NODE_DIR" "$CLONE_DIR" || {
    err "cp -a failed while cloning; aborting clone step."
    exit 1
  }
fi

# 6) Summary and next steps
if [ -d "$CLONE_DIR" ]; then
  info "Clone completed: ${CLONE_DIR}"
  info "Service ${UNIT} is masked and stopped."
  if [ -n "$CIDS" ]; then
    echo "$CIDS" | while read -r cid; do
      info "To restore Docker restart policy for container ${cid}, run:"
      info "  sudo docker update --restart=unless-stopped ${cid}"
    done
  fi
  if [ "${PRE_ENABLED}" -eq 1 ]; then
    info "Note: the unit was enabled before masking. After unmasking you may want to re-enable it:"
    info "  sudo systemctl enable --now ${UNIT}"
  fi
else
  err "Clone directory not found after copy; something went wrong."
  exit 1
fi

exit 0

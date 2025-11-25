#!/bin/bash
# stop_demos_node_v1.sh
# - Mask demos-node.service to prevent automated restarts
# - Stop the demos-node.service (graceful stop)
# - Disable Docker restart for DB container if detected
# - Create a timestamped clone of /opt/demos-node (no restart)
set -euo pipefail
IFS=$'\n\t'

UNIT="demos-node.service"
NODE_DIR="/opt/demos-node"
CLONE_BASE="/opt"
DB_PORT=5332
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
CLONE_DIR="${CLONE_BASE}/demos-node.clone.${TIMESTAMP}"
WAIT_STOP=15   # seconds to wait for service to stop

# red output helpers
info(){ printf "\e[91m%s\e[0m\n" "$*"; }
err(){ printf "\e[91m%s\e[0m\n" "$*" >&2; }

# require root
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (sudo)."
  exit 1
fi

# sanity checks
if [ ! -d "$NODE_DIR" ]; then
  err "Node directory not found at $NODE_DIR. Aborting."
  exit 1
fi

# record previous enablement state (for operator awareness)
PRE_ENABLED=0
if systemctl list-unit-files --type=service --all | grep -q "^${UNIT}"; then
  if systemctl is-enabled --quiet "${UNIT}" 2>/dev/null; then PRE_ENABLED=1; fi
fi

# 1) Mask the unit to prevent automated restarts
info "Masking ${UNIT} to prevent automated restarts (service may remain running until stopped)"
systemctl mask "${UNIT}" >/dev/null 2>&1 || true

# 2) Stop the service gracefully
info "Stopping ${UNIT} (graceful stop, waiting up to ${WAIT_STOP}s)"
if systemctl list-unit-files --type=service --all | grep -q "^${UNIT}"; then
  systemctl stop "${UNIT}" || {
    err "systemctl stop returned non-zero; continuing to ensure process termination."
  }
  # wait for MainPID to exit
  for i in $(seq 1 $WAIT_STOP); do
    PID=$(systemctl show -p MainPID --value "${UNIT}" 2>/dev/null || echo 0)
    if [ -z "$PID" ] || [ "$PID" = "0" ]; then
      info "${UNIT} stopped."
      break
    fi
    sleep 1
  done
  # final check
  PID=$(systemctl show -p MainPID --value "${UNIT}" 2>/dev/null || echo 0)
  if [ -n "$PID" ] && [ "$PID" != "0" ]; then
    err "Service did not exit within ${WAIT_STOP}s (MainPID=${PID}). Attempting to kill PID."
    kill "$PID" 2>/dev/null || true
    sleep 1
  fi
else
  info "Unit ${UNIT} not found; skipping systemd stop."
fi

# 3) Detect DB container publishing DB_PORT and disable its restart policy
detect_db_cid(){
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.ID}}\t{{.Ports}}' | awk -v p=":${DB_PORT}->" '$0 ~ p { print $1; exit }'
}
CID="$(detect_db_cid || true)"
if [ -n "$CID" ]; then
  info "Detected Docker container ${CID} publishing host port ${DB_PORT}; setting restart policy to 'no'"
  docker update --restart=no "${CID}" >/dev/null 2>&1 || {
    err "docker update --restart=no failed for ${CID}; you may need to adjust manually."
  }
else
  info "No Docker container publishing host port ${DB_PORT} detected; skipping docker restart policy change."
fi

# 4) Create a clone of the node directory without stopping or restarting anything else
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

# 5) Summary and next steps
if [ -d "$CLONE_DIR" ]; then
  info "Clone completed: ${CLONE_DIR}"
  info "Service ${UNIT} is masked and stopped. To allow systemd to manage it again, run:"
  info "  sudo systemctl unmask ${UNIT}"
  if [ -n "$CID" ]; then
    info "To restore Docker restart policy for container ${CID}, run (example):"
    info "  sudo docker update --restart=unless-stopped ${CID}"
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

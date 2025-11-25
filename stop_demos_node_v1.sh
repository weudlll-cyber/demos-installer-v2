#!/bin/bash
# stop_demos_node_v1.sh
# - If demos-node.service is not running, exit immediately
# - If running: mask unit, stop service, disable+stop DB container(s), wait for ports to free
set -euo pipefail
IFS=$'\n\t'

UNIT="demos-node.service"
DB_PORT=5332
NODE_PORT=53550
WAIT_STOP=20
WAIT_PORT=30

info(){ printf "\e[91m%s\e[0m\n" "$*"; }
err(){ printf "\e[91m%s\e[0m\n" "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (sudo)."
  exit 1
fi

# Check service existence and active state
if ! systemctl list-unit-files --type=service --all | grep -q "^${UNIT}"; then
  info "Unit ${UNIT} not found. Nothing to stop. Exiting."
  exit 0
fi

if ! systemctl is-active --quiet "${UNIT}"; then
  info "${UNIT} is not running. No stop or clone required. Exiting."
  exit 0
fi

info "${UNIT} is running. Proceeding to mask and stop."

# Record previous enablement state for operator awareness
PRE_ENABLED=0
if systemctl is-enabled --quiet "${UNIT}" 2>/dev/null; then PRE_ENABLED=1; fi

# Mask to prevent automated restarts
info "Masking ${UNIT} to prevent automated restarts"
systemctl mask "${UNIT}" >/dev/null 2>&1 || true

# Stop the service gracefully
info "Stopping ${UNIT} (waiting up to ${WAIT_STOP}s)"
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

# Detect Docker container(s) publishing DB_PORT and disable restart + stop them
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

# Wait for host ports to free
info "Waiting up to ${WAIT_PORT}s for host ports ${DB_PORT} and ${NODE_PORT} to be free"
for i in $(seq 1 $WAIT_PORT); do
  ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" >/dev/null || break
  sleep 1
done

info "Listening sockets for ${DB_PORT} and ${NODE_PORT}:"
ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" || info "none — ports appear free"

# Final summary and guidance
info "Stop sequence complete. Service ${UNIT} is masked and stopped."
if [ -n "$CIDS" ]; then
  echo "$CIDS" | while read -r cid; do
    info "To restore Docker restart policy for container ${cid}, run:"
    info "  sudo docker update --restart=unless-stopped ${cid}"
  done
fi
if [ "${PRE_ENABLED}" -eq 1 ]; then
  info "Note the unit was enabled before masking. After unmasking you may want to re-enable it:"
  info "  sudo systemctl enable --now ${UNIT}"
fi

exit 0

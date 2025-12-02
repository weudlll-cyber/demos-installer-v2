#!/usr/bin/env bash
# stop_demos_node_v2.sh
# - Stop node (systemd-managed or stray process)
# - Mask/disable/stop and remove systemd unit and drop-ins
# - Stop, set restart=no, and remove DB container(s) publishing DB_PORT
# - Wait for ports to free and print restore guidance
set -euo pipefail
IFS=$'\n\t'

UNIT="demos-node.service"
UNIT_PATH="/etc/systemd/system/${UNIT}"
DROPIN_DIR="/etc/systemd/system/${UNIT}.d"
DB_PORT=5332
NODE_PORT=53550
WAIT_STOP=20
WAIT_PORT=30

info(){ printf "\e[32m%s\e[0m\n" "$*"; }
warn(){ printf "\e[33m%s\e[0m\n" "$*"; }
err(){ printf "\e[91m%s\e[0m\n" "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (sudo)."
  exit 1
fi

# Helper: find containers publishing DB_PORT
detect_db_cids(){
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.ID}}\t{{.Ports}}\t{{.Names}}' | awk -v p=":${DB_PORT}->" '$0 ~ p { print $1 }'
}

# 1) Stop node whether systemd-managed or started manually
info "Stopping node process (systemd-managed or stray)..."

# If unit exists and is active, stop and mask it first
if systemctl list-unit-files --type=service --all | grep -q "^${UNIT}"; then
  PRE_ENABLED=0
  if systemctl is-enabled --quiet "${UNIT}" 2>/dev/null; then PRE_ENABLED=1; fi

  if systemctl is-active --quiet "${UNIT}"; then
    info "Systemd unit ${UNIT} is active: stopping..."
    systemctl stop "${UNIT}" || warn "systemctl stop returned non-zero; continuing"
  else
    info "Systemd unit ${UNIT} is not active."
  fi

  info "Masking and disabling ${UNIT} to prevent any automatic restarts"
  systemctl mask "${UNIT}" >/dev/null 2>&1 || true
  systemctl disable "${UNIT}" >/dev/null 2>&1 || true
else
  info "Systemd unit ${UNIT} not found on this host."
  PRE_ENABLED=0
fi

# Wait for systemd MainPID to exit (if any)
for i in $(seq 1 $WAIT_STOP); do
  PID=$(systemctl show -p MainPID --value "${UNIT}" 2>/dev/null || echo 0)
  if [ -z "$PID" ] || [ "$PID" = "0" ]; then
    break
  fi
  sleep 1
done

# If a stray bun/node process is still running, kill it
# Look for bun or the run script
STRAY_PIDS="$(pgrep -f 'bun -r tsconfig-paths/register src/index.ts' || true) $(pgrep -f '/opt/demos-node/run' || true) $(pgrep -f 'bun start:bun' || true)"
STRAY_PIDS="$(echo "$STRAY_PIDS" | tr ' ' '\n' | awk 'NF' | sort -u || true)"
if [ -n "$STRAY_PIDS" ]; then
  info "Found stray node process(es):"
  echo "$STRAY_PIDS" | while read -r p; do
    info "  - killing PID $p"
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 2
  # force kill if still present
  echo "$STRAY_PIDS" | while read -r p; do
    if kill -0 "$p" 2>/dev/null; then
      warn "PID $p still alive; forcing kill"
      kill -KILL "$p" 2>/dev/null || true
    fi
  done
else
  info "No stray node processes found."
fi

# 2) Remove systemd unit files and drop-ins (complete cleanup)
if [ -f "${UNIT_PATH}" ] || [ -d "${DROPIN_DIR}" ]; then
  info "Removing systemd unit file and drop-ins for ${UNIT} (this deletes ${UNIT_PATH} and ${DROPIN_DIR})"
  rm -f "${UNIT_PATH}" || true
  rm -rf "${DROPIN_DIR}" || true
  systemctl daemon-reload || true
  systemctl reset-failed || true
  info "Systemd unit files removed and daemon reloaded."
else
  info "No unit file or drop-in directory to remove."
fi

# 3) Detect and stop/remove DB container(s)
CIDS="$(detect_db_cids || true)"
if [ -n "$CIDS" ]; then
  info "Found container(s) publishing host port ${DB_PORT}:"
  echo "$CIDS" | while read -r cid; do
    info "  - $cid : setting restart=no, stopping and removing"
    docker update --restart=no "$cid" >/dev/null 2>&1 || warn "docker update failed for $cid"
    docker stop --time 10 "$cid" >/dev/null 2>&1 || warn "docker stop failed for $cid"
    docker rm -f "$cid" >/dev/null 2>&1 || warn "docker rm failed for $cid"
  done
else
  info "No container publishing host port ${DB_PORT} detected; skipping container stop/removal."
fi

# 4) Wait for host ports to free
info "Waiting up to ${WAIT_PORT}s for host ports ${DB_PORT} and ${NODE_PORT} to be free"
for i in $(seq 1 $WAIT_PORT); do
  if ! ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" >/dev/null; then
    break
  fi
  sleep 1
done

info "Listening sockets for ${DB_PORT} and ${NODE_PORT}:"
ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" || info "none — ports appear free"

# 5) Final summary and restore guidance
info "Stop/cleanup sequence complete."
if [ -n "$CIDS" ]; then
  info "Containers removed: "
  echo "$CIDS" | while read -r cid; do info "  - ${cid}"; done
  info "To recreate Postgres later, run (from the compose dir):"
  info "  cd /opt/demos-node/postgres_5332 && sudo docker compose up -d"
fi

if [ "${PRE_ENABLED:-0}" -eq 1 ]; then
  warn "Note: the unit ${UNIT} was enabled before. To restore the original unit file and re-enable it, place the unit file back at ${UNIT_PATH} and run:"
  warn "  sudo systemctl daemon-reload && sudo systemctl enable --now ${UNIT}"
fi

info "If you want me to also generate a start script that will recreate the systemd unit and bring Postgres back under docker-compose, say: generate start script."

exit 0

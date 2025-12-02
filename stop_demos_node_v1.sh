#!/usr/bin/env bash
# stop_demos_node_v1.sh
# Location: demos-installer-v2/
#
# Purpose:
#   - Stop the node (whether managed by systemd or running as a stray process).
#   - Remove systemd unit and drop-ins completely so the system looks like it never had a unit.
#   - Stop, disable autostart, and remove Postgres Docker container(s) publishing DB_PORT.
#   - Wait for ports to free.
#   - Print clear guidance for restoring later.
#
# Notes:
#   - All user-facing messages are printed in red for consistency with other scripts.
#   - This script is idempotent: safe to run multiple times.
#   - Run with sudo/root privileges.

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Configuration variables
# -----------------------------
DIRNAME="demos-installer-v2/"                # Base directory where this script is located
UNIT="demos-node.service"                    # Name of the systemd unit
UNIT_PATH="/etc/systemd/system/${UNIT}"      # Path to the unit file
DROPIN_DIR="/etc/systemd/system/${UNIT}.d"   # Path to unit drop-ins
DB_PORT=5332                                 # Host port used by Postgres container
NODE_PORT=53550                              # Host port used by node RPC
WAIT_STOP=20                                 # Seconds to wait for processes to stop
WAIT_PORT=30                                 # Seconds to wait for ports to free

# -----------------------------
# Helper functions
# -----------------------------
msg(){ printf "\e[91m%s\e[0m\n" "$*"; }      # Print all messages in red
err(){ printf "\e[91m%s\e[0m\n" "$*" >&2; }  # Print errors in red to stderr

# -----------------------------
# Root check
# -----------------------------
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (sudo)."
  exit 1
fi

# -----------------------------
# Helper: detect DB containers publishing DB_PORT
# -----------------------------
detect_db_cids(){
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.ID}}\t{{.Ports}}\t{{.Names}}' | awk -v p=":${DB_PORT}->" '$0 ~ p { print $1 }'
}

# -----------------------------
# 1) Stop node (systemd-managed or stray)
# -----------------------------
msg "Stopping node process (systemd-managed or stray)..."

# If systemd unit exists, stop it
if systemctl list-unit-files --type=service --all | grep -q "^${UNIT}"; then
  if systemctl is-active --quiet "${UNIT}"; then
    msg "Systemd unit ${UNIT} is active: stopping..."
    systemctl stop "${UNIT}" || msg "systemctl stop returned non-zero; continuing"
  else
    msg "Systemd unit ${UNIT} is not active."
  fi
fi

# Wait for systemd MainPID to exit
for i in $(seq 1 $WAIT_STOP); do
  PID=$(systemctl show -p MainPID --value "${UNIT}" 2>/dev/null || echo 0)
  if [ -z "$PID" ] || [ "$PID" = "0" ]; then
    break
  fi
  sleep 1
done

# Kill stray node processes (bun or run script)
STRAY_PIDS="$(pgrep -f '/opt/demos-node/run' || true) $(pgrep -f 'bun -r tsconfig-paths/register src/index.ts' || true) $(pgrep -f 'bun start:bun' || true)"
STRAY_PIDS="$(echo "$STRAY_PIDS" | tr ' ' '\n' | awk 'NF' | sort -u || true)"
if [ -n "$STRAY_PIDS" ]; then
  msg "Found stray node process(es):"
  echo "$STRAY_PIDS" | while read -r p; do
    msg "  - killing PID $p"
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 2
  echo "$STRAY_PIDS" | while read -r p; do
    if kill -0 "$p" 2>/dev/null; then
      msg "PID $p still alive; forcing kill"
      kill -KILL "$p" 2>/dev/null || true
    fi
  done
else
  msg "No stray node processes found."
fi

# -----------------------------
# 2) Remove systemd unit files and drop-ins completely
# -----------------------------
if [ -f "${UNIT_PATH}" ] || [ -d "${DROPIN_DIR}" ]; then
  msg "Removing systemd unit file and drop-ins for ${UNIT}"
  rm -f "${UNIT_PATH}" || true
  rm -rf "${DROPIN_DIR}" || true
  systemctl daemon-reload || true
  systemctl reset-failed || true
  msg "Systemd unit files removed. Now 'systemctl status ${UNIT}' will show 'Unit not found'."
else
  msg "No unit file or drop-in directory to remove."
fi

# -----------------------------
# 3) Detect and stop/remove DB container(s)
# -----------------------------
CIDS="$(detect_db_cids || true)"
if [ -n "$CIDS" ]; then
  msg "Found container(s) publishing host port ${DB_PORT}:"
  echo "$CIDS" | while read -r cid; do
    msg "  - $cid : setting restart=no, stopping and removing"
    docker update --restart=no "$cid" >/dev/null 2>&1 || msg "docker update failed for $cid"
    docker stop --time 10 "$cid" >/dev/null 2>&1 || msg "docker stop failed for $cid"
    docker rm -f "$cid" >/dev/null 2>&1 || msg "docker rm failed for $cid"
  done
else
  msg "No container publishing host port ${DB_PORT} detected; skipping container stop/removal."
fi

# -----------------------------
# 4) Wait for host ports to free
# -----------------------------
msg "Waiting up to ${WAIT_PORT}s for host ports ${DB_PORT} and ${NODE_PORT} to be free..."
for i in $(seq 1 $WAIT_PORT); do
  if ! ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" >/dev/null; then
    break
  fi
  sleep 1
done

msg "Listening sockets for ${DB_PORT} and ${NODE_PORT}:"
ss -ltnp | grep -E ":${DB_PORT}|:${NODE_PORT}" || msg "none — ports appear free"

# -----------------------------
# 5) Final summary
# -----------------------------
msg "Stop/cleanup sequence complete."
if [ -n "$CIDS" ]; then
  msg "Containers removed:"
  echo "$CIDS" | while read -r cid; do msg "  - ${cid}"; done
  msg "To recreate Postgres later, run (from the compose dir):"
  msg "  cd /opt/demos-node/postgres_5332 && sudo docker compose up -d"
fi

msg "System now looks like there was never a systemd unit for ${UNIT}."
msg "Check with: systemctl status ${UNIT}  # should say 'Unit ${UNIT} could not be found'"

exit 0

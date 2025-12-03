#!/usr/bin/env bash
# change_pubkey.sh
#
# Purpose:
#   - Stop the node cleanly using the existing stop script.
#   - Prompt the user for a peer public key and connection string.
#   - Add that peer entry to demos_peerlist.json.
#   - Restart the node under systemd and wait for it to bind.
#
# Notes:
#   - All output is printed in RED for consistency.
#   - Script is idempotent: safe to run multiple times.
#   - Run with sudo/root privileges.

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Configuration variables
# -----------------------------
STOP_SCRIPT="/opt/demos-node/helpers/stop_demos_node.sh"   # Path to your stop script
WORKDIR="/opt/demos-node"                                  # Node working directory
PEERLIST_PATH="${WORKDIR}/demos_peerlist.json"             # Peerlist file
UNIT="demos-node.service"                                  # Systemd unit name
NODE_PORT=53550                                            # Node RPC port
WAIT_BIND=40                                               # Seconds to wait for bind

# -----------------------------
# Helper functions
# -----------------------------
msg(){  printf "\e[31m%s\e[0m\n" "$*"; }     # Print messages in RED
err(){  printf "\e[31m%s\e[0m\n" "$*" >&2; } # Print errors in RED to stderr

# -----------------------------
# Root check
# -----------------------------
if [ "$(id -u)" -ne 0 ]; then
  err "❌ Run this script as root (sudo)."
  exit 1
fi

# -----------------------------
# 1) Stop node using stop script
# -----------------------------
msg "STEP 1: Stopping node using ${STOP_SCRIPT}"
if [ -x "${STOP_SCRIPT}" ]; then
  "${STOP_SCRIPT}"
else
  err "❌ Stop script not found or not executable at ${STOP_SCRIPT}"
  exit 2
fi

# -----------------------------
# 2) Prompt user for peer info
# -----------------------------
msg "STEP 2: Please enter the peer's public key (e.g. 0xd0b2be2cb6d...)"
read -r PUBKEY
if [ -z "${PUBKEY}" ]; then
  err "❌ No public key entered. Aborting."
  exit 3
fi

msg "STEP 2: Please enter the peer's connection string (e.g. http://peer.example:53550)"
read -r CONNSTR
if [ -z "${CONNSTR}" ]; then
  err "❌ No connection string entered. Aborting."
  exit 4
fi

# -----------------------------
# 3) Update demos_peerlist.json
# -----------------------------
msg "STEP 3: Updating ${PEERLIST_PATH} with new peer entry"

# If file exists, merge entry; if not, create new JSON object
if [ -f "${PEERLIST_PATH}" ]; then
  # Use jq if available for safe JSON update
  if command -v jq >/dev/null 2>&1; then
    tmpfile="$(mktemp)"
    jq --arg k "${PUBKEY}" --arg v "${CONNSTR}" '. + {($k): $v}' "${PEERLIST_PATH}" > "$tmpfile"
    mv "$tmpfile" "${PEERLIST_PATH}"
  else
    # Fallback: overwrite with single-entry JSON (not ideal, but ensures peerlist exists)
    echo "{ \"${PUBKEY}\": \"${CONNSTR}\" }" > "${PEERLIST_PATH}"
  fi
else
  echo "{ \"${PUBKEY}\": \"${CONNSTR}\" }" > "${PEERLIST_PATH}"
fi

msg "✅ Added peer ${PUBKEY} -> ${CONNSTR}"

# -----------------------------
# 4) Restart node under systemd
# -----------------------------
msg "STEP 4: Restarting node under systemd"
systemctl unmask "${UNIT}" >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl restart "${UNIT}"

# Wait for bind
msg "Waiting up to ${WAIT_BIND}s for node to bind ${NODE_PORT}..."
for i in $(seq 1 ${WAIT_BIND}); do
  if ss -ltnp | grep -q ":${NODE_PORT}"; then
    msg "✅ Node is listening on ${NODE_PORT}."
    break
  fi
  sleep 1
done

if ! ss -ltnp | grep -q ":${NODE_PORT}"; then
  err "❌ Node did not bind ${NODE_PORT} within ${WAIT_BIND}s. Check /var/log/demos-node.out"
  exit 5
fi

# -----------------------------
# 5) Final summary
# -----------------------------
msg "CHANGE PUBKEY SEQUENCE COMPLETE"
msg "✅ Node restarted with new peer entry: ${PUBKEY} -> ${CONNSTR}"

exit 0

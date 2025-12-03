#!/usr/bin/env bash
# change_pubkey.sh
#
# Purpose:
#   - Stop the node by fetching and executing the official stop script.
#   - Prompt ONLY for the peer public key (address).
#   - Add that peer entry to demos_peerlist.json using the address itself as the connection string.
#   - Restart the node under systemd and wait for bind.
#
# Notes:
#   - All output is printed in RED for consistency.
#   - Run with sudo/root privileges.

set -euo pipefail
IFS=$'\n\t'

STOP_URL="https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/stop_demos_node_v1.sh"
WORKDIR="/opt/demos-node"
PEERLIST_PATH="${WORKDIR}/demos_peerlist.json"
UNIT="demos-node.service"
NODE_PORT=53550
WAIT_BIND=40

msg(){  printf "\e[31m%s\e[0m\n" "$*"; }
err(){  printf "\e[31m%s\e[0m\n" "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  err "❌ Run this script as root (sudo)."
  exit 1
fi

# 1) Stop node
msg "STEP 1: Stopping node using remote stop script"
curl -fsSL "$STOP_URL" | bash || {
  err "❌ Failed to execute stop script from $STOP_URL"
  exit 2
}

# 2) Prompt ONLY for peer public key/address
msg "STEP 2: Enter the peer's public key/address (e.g. http://peer.example:53550)"
read -r PUBKEY
if [ -z "${PUBKEY}" ]; then
  err "❌ No address entered. Aborting."
  exit 3
fi

# Use the entered address directly as the connection string
CONNSTR="${PUBKEY}"

# 3) Update demos_peerlist.json
msg "STEP 3: Updating ${PEERLIST_PATH} with new peer entry"
if [ -f "${PEERLIST_PATH}" ]; then
  if command -v jq >/dev/null 2>&1; then
    tmpfile="$(mktemp)"
    jq --arg k "${PUBKEY}" --arg v "${CONNSTR}" '. + {($k): $v}' "${PEERLIST_PATH}" > "$tmpfile"
    mv "$tmpfile" "${PEERLIST_PATH}"
  else
    echo "{ \"${PUBKEY}\": \"${CONNSTR}\" }" > "${PEERLIST_PATH}"
  fi
else
  echo "{ \"${PUBKEY}\": \"${CONNSTR}\" }" > "${PEERLIST_PATH}"
fi
msg "✅ Added peer ${PUBKEY} -> ${CONNSTR}"

# 4) Restart node under systemd
msg "STEP 4: Restarting node under systemd"
systemctl unmask "${UNIT}" >/dev/null 2>&1 || true
systemctl enable --now "${UNIT}" >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl restart "${UNIT}"

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

# 5) Final summary
msg "CHANGE PUBKEY SEQUENCE COMPLETE"
msg "✅ Node restarted with new peer entry: ${PUBKEY} -> ${CONNSTR}"

exit 0

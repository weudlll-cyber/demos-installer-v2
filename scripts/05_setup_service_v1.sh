#!/bin/bash
# [05] Write systemd unit for Demos Node (do not enable or start)
set -euo pipefail
IFS=$'\n\t'

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/05_setup_service.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  exit 0
fi

if ! command -v systemctl &>/dev/null; then
  # systemd not available; write files but still mark as done
  echo "systemd not detected; unit file will be written if systemd becomes available"
fi

SERVICE_FILE="/etc/systemd/system/demos-node.service"
ENV_DIR="/etc/demos-node"
ENV_FILE="$ENV_DIR/env"

mkdir -p "$ENV_DIR"

cat > "$ENV_FILE" <<'EOF'
# /etc/demos-node/env
# Populate before enabling the service.
# Example:
# PG_PORT=5332
# PORT=53550
# BIND_ADDR=0.0.0.0
# DEMOS_SECRET=replace-with-generated-key
EOF

chmod 640 "$ENV_FILE"
chown root:root "$ENV_FILE"

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Demos Node Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/demos-node
ExecStart=/opt/demos-node/run
Restart=always
RestartSec=5
EnvironmentFile=/etc/demos-node/env
Environment=BUN_INSTALL=/root/.bun
Environment=PATH=/root/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"
chown root:root "$SERVICE_FILE"

# mark this step done (installer will not enable/start service here)
touch "$STEP_MARKER"
exit 0

#!/bin/bash

# Helper script to install global node management commands

set -e

echo -e "\e[91mInstalling helper scripts...\e[0m"

# Define install path
INSTALL_PATH="/usr/local/bin"

# Create helper: restart-node
cat << 'EOF' > "$INSTALL_PATH/restart-node"
#!/bin/bash
echo -e "\e[91mRestarting Demos node...\e[0m"
systemctl restart demos-node.service
systemctl status demos-node.service --no-pager
EOF

# Create helper: stop-node
cat << 'EOF' > "$INSTALL_PATH/stop-node"
#!/bin/bash
echo -e "\e[91mStopping Demos node...\e[0m"
systemctl stop demos-node.service
pkill -f demos-node || true
fuser -k 3000/tcp || true
EOF

# Create helper: logs-node
cat << 'EOF' > "$INSTALL_PATH/logs-node"
#!/bin/bash
echo -e "\e[91mShowing Demos node logs...\e[0m"
journalctl -u demos-node.service -n 100 --no-pager
EOF

# Make all scripts executable
chmod +x "$INSTALL_PATH/restart-node"
chmod +x "$INSTALL_PATH/stop-node"
chmod +x "$INSTALL_PATH/logs-node"

echo -e "\e[92mHelper scripts installed successfully.\e[0m"

#!/bin/bash
# [04] Clone Demos Node repository and pause so operator can verify postgres config
set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [04] Cloning Demos Node repository (pause after clone for verification)...\e[0m"
echo -e "\e[91mThis step sets up the node codebase in /opt/demos-node and then exits so you can check files.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/04_clone_repo.done"
mkdir -p "$MARKER_DIR"

# If already completed previously, we still perform a quick verification and exit
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m⚠️ [04] Step previously completed. Running verification and exiting for manual check.\e[0m"
fi

# Ensure Bun is available in PATH for future steps, but we do not run bun install now
export PATH="/root/.bun/bin:$PATH"

# === Clone the repository ===
echo -e "\e[91m📥 Cloning Demos Node repository into /opt/demos-node...\e[0m"
if [ -d "/opt/demos-node/.git" ]; then
  echo -e "\e[93m⚠️ Repository already exists at /opt/demos-node. Skipping git clone.\e[0m"
else
  rm -rf /opt/demos-node 2>/dev/null || true
  if ! git clone https://github.com/kynesyslabs/node.git /opt/demos-node; then
    echo -e "\e[91m❌ Git clone failed. Check network/GitHub access and retry installer.\e[0m"
    exit 1
  fi
fi

# === Short verification of expected files (template + instance) ===
PG_PORT=${PG_PORT:-5332}
TEMPLATE="/opt/demos-node/postgres/docker-compose.yml"
INSTANCE="/opt/demos-node/postgres_${PG_PORT}/docker-compose.yml"

echo -e "\e[94m🔎 Verifying postgres compose/template presence (preview truncated)...\e[0m"

if [ -f "$TEMPLATE" ]; then
  echo -e "\e[92mTEMPLATE FOUND: $TEMPLATE ($(stat -c%s "$TEMPLATE") bytes)\e[0m"
  echo "----- preview $TEMPLATE -----"
  sed -n '1,20p' "$TEMPLATE" || true
else
  echo -e "\e[91mTEMPLATE MISSING: $TEMPLATE\e[0m"
fi

if [ -f "$INSTANCE" ]; then
  echo -e "\e[92mINSTANCE FILE FOUND: $INSTANCE ($(stat -c%s "$INSTANCE") bytes)\e[0m"
  echo "----- preview $INSTANCE -----"
  sed -n '1,20p' "$INSTANCE" || true
else
  echo -e "\e[93mINSTANCE FILE MISSING: $INSTANCE\e[0m"
  echo -e "\e[93mNote: the installer/runtime normally copies the template into the instance folder on first run.\e[0m"
fi

# Optional quick remote check for upstream template (do not modify files)
GH_RAW_URL="https://raw.githubusercontent.com/kynesyslabs/node/main/postgres/docker-compose.yml"
if curl -fsS --head "$GH_RAW_URL" >/dev/null 2>&1; then
  echo -e "\e[92mUPSTREAM TEMPLATE AVAILABLE: $GH_RAW_URL\e[0m"
else
  echo -e "\e[93mUPSTREAM TEMPLATE NOT FOUND at $GH_RAW_URL\e[0m"
fi

# Print next-steps instructions and exit so operator can inspect files
cat <<'EOF'

Step 04 has paused intentionally after cloning so you can verify:
 - Check /opt/demos-node/postgres/docker-compose.yml (template)
 - Check /opt/demos-node/postgres_<PORT>/docker-compose.yml (instance for your PG_PORT)
 - If instance file is missing or a placeholder, you can copy the template into postgres_<PORT>/ now:
     sudo mkdir -p /opt/demos-node/postgres_${PG_PORT}
     sudo cp -av /opt/demos-node/postgres/docker-compose.yml /opt/demos-node/postgres_${PG_PORT}/docker-compose.yml
     sudo sed -i "s/\${PG_PORT}/${PG_PORT}/g" /opt/demos-node/postgres_${PG_PORT}/docker-compose.yml
     sudo chown root:root /opt/demos-node/postgres_${PG_PORT}/docker-compose.yml
     sudo chmod 644 /opt/demos-node/postgres_${PG_PORT}/docker-compose.yml

When you're satisfied, re-run the installer to continue with dependency install and remaining steps:
    sudo bash demos_node_setup_v1.sh

This step did NOT run bun install and did NOT mark step 04 complete; the installer will continue from here when re-run.

EOF

# Exit gracefully so the overall installer stops here for manual inspection
exit 0

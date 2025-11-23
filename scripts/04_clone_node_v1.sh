#!/bin/bash
# [04] Clone Demos Node repository and install dependencies (auto-fix Bun untrusted packages)
set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [04] Cloning Demos Node repository and installing dependencies...\e[0m"
echo -e "\e[91mThis step sets up the actual node codebase in /opt/demos-node.\e[0m"

MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/04_clone_repo.done"
mkdir -p "$MARKER_DIR"

# === Skip if already completed ===
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[92m✅ [04] Node repository already cloned. Skipping...\e[0m"
  exit 0
fi

# === Ensure bun binary is resolvable in non-interactive contexts ===
if command -v /usr/local/bin/bun &>/dev/null; then
  BUN_BIN="/usr/local/bin/bun"
elif command -v bun &>/dev/null; then
  BUN_BIN="$(command -v bun)"
elif [ -x "/root/.bun/bin/bun" ]; then
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  BUN_BIN="/usr/local/bin/bun"
else
  echo -e "\e[91m❌ Bun is not available in PATH.\e[0m"
  echo -e "\e[91mMake sure Bun was installed correctly in step 03.\e[0m"
  echo -e "\e[91mRun the installer again to complete Bun setup:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

export BUN_BIN
export PATH="$(dirname "$BUN_BIN"):$PATH"

echo -e "\e[91m🔍 Using bun binary: $BUN_BIN\e[0m"

# === Clone the repository ===
echo -e "\e[91m📥 Cloning Demos Node repository into /opt/demos-node...\e[0m"
if [ -d "/opt/demos-node/.git" ]; then
  echo -e "\e[93m⚠️ Repository already exists at /opt/demos-node. Skipping git clone.\e[0m"
else
  rm -rf /opt/demos-node 2>/dev/null || true
  if ! git clone https://github.com/kynesyslabs/node.git /opt/demos-node; then
    echo -e "\e[91m❌ Git clone failed.\e[0m"
    echo -e "\e[91mCheck your internet connection or GitHub access.\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  fi
fi

# === Install dependencies ===
echo -e "\e[91m📦 Installing dependencies with Bun...\e[0m"
cd /opt/demos-node

if [ -f "bun.lockb" ] || [ -f "package.json" ]; then
  if ! "$BUN_BIN" install; then
    echo -e "\e[91m❌ bun install failed on first attempt. Retrying after a cache clean...\e[0m"
    "$BUN_BIN" cache clean 2>/dev/null || true
    if ! "$BUN_BIN" install; then
      echo -e "\e[91m❌ bun install failed again. Try running manually:\e[0m"
      echo -e "\e[91mcd /opt/demos-node && $BUN_BIN install\e[0m"
      exit 1
    fi
  fi
else
  echo -e "\e[93m⚠️ No bun.lockb or package.json found. Skipping install.\e[0m"
fi

# === Robust trust + postinstall fix sequence ===
BUN_LOG="/var/log/demos-node-bun.log"
echo -e "\e[91m🔐 Ensuring Bun package trust and running postinstalls (logs: $BUN_LOG)...\e[0m"
mkdir -p "$(dirname "$BUN_LOG")"
: > "$BUN_LOG"

fix_attempt=0
MAX_FIX_ATTEMPTS=3
while [ $fix_attempt -lt $MAX_FIX_ATTEMPTS ]; do
  fix_attempt=$((fix_attempt + 1))
  {
    echo "=== Attempt $fix_attempt - $(date) ==="
    echo "=== bun pm untrusted (before) ==="
    "$BUN_BIN" pm untrusted || true
    echo "=== bun pm trust --all ==="
    "$BUN_BIN" pm trust --all || true
    echo "=== bun pm untrusted (after trust) ==="
    "$BUN_BIN" pm untrusted || true
    echo "=== bun install (post-trust) ==="
    "$BUN_BIN" install || true
    echo "=== bun rebuild (native modules if any) ==="
    "$BUN_BIN" rebuild || true
    echo "=== end attempt ==="
  } >> "$BUN_LOG" 2>&1 || true

  # check if any untrusted remain
  if ! "$BUN_BIN" pm untrusted | grep -q '.'; then
    echo -e "\e[92m✅ Bun packages trusted and postinstalls attempted (attempt $fix_attempt).\e[0m"
    break
  fi

  echo -e "\e[93m⚠️ Some packages remain untrusted after attempt $fix_attempt. Retrying...\e[0m"
  sleep 2
done

# Final check: if still untrusted, attempt one last best-effort trust and proceed with a clear log
if "$BUN_BIN" pm untrusted | grep -q '.'; then
  echo -e "\e[93m⚠️ bun pm untrusted still reports blocked packages after $MAX_FIX_ATTEMPTS attempts.\e[0m"
  echo -e "\e[93mAttempting a final trust --all and proceeding; inspect $BUN_LOG for details.\e[0m"
  "$BUN_BIN" pm trust --all >> "$BUN_LOG" 2>&1 || true
  "$BUN_BIN" install >> "$BUN_LOG" 2>&1 || true
else
  echo -e "\e[92m✅ Bun dependency trust and postinstall sequence completed successfully.\e[0m"
fi

# === Verify run script ===
if [ -f "/opt/demos-node/run" ]; then
  echo -e "\e[92m✅ Node repository is ready.\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Missing run script in /opt/demos-node.\e[0m"
  echo -e "\e[91mCheck manually:\e[0m"
  echo -e "\e[91mls -l /opt/demos-node/run\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

# Show short bun log tail for quick feedback
echo -e "\e[91m🔎 bun log tail (last 40 lines):\e[0m"
tail -n 40 "$BUN_LOG" 2>/dev/null || true

exit 0

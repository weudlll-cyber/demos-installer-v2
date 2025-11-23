#!/bin/bash
# [04] Clone Demos Node repository and install dependencies (simple)
set -euo pipefail
IFS=$'\n\t'

# ---------- config ----------
REPO_URL="https://github.com/kynesyslabs/node.git"
TARGET_DIR="/opt/demos-node"
MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/04_clone_repo.done"
BUN_LOG="/var/log/demos-node-bun.log"
GIT_LOG="/var/log/git-demos-node.log"

mkdir -p "$MARKER_DIR"
mkdir -p "$(dirname "$BUN_LOG")"
mkdir -p "$(dirname "$GIT_LOG")"
: > "$BUN_LOG"
: > "$GIT_LOG"

echo -e "\e[91m🔧 [04] Cloning Demos Node repository and installing dependencies...\e[0m"

# ---------- idempotency ----------
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[92m✅ [04] Node repository already cloned. Skipping...\e[0m"
  exit 0
fi

# ---------- resolve bun ----------
if command -v /usr/local/bin/bun &>/dev/null; then
  BUN_BIN="/usr/local/bin/bun"
elif command -v bun &>/dev/null; then
  BUN_BIN="$(command -v bun)"
elif [ -x "/root/.bun/bin/bun" ]; then
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  BUN_BIN="/usr/local/bin/bun"
else
  echo -e "\e[91m❌ Bun not found. Ensure step 03 completed successfully.\e[0m"
  exit 1
fi
export BUN_BIN
export PATH="$(dirname "$BUN_BIN"):$PATH"
echo -e "\e[93m🔍 Using bun binary: $BUN_BIN\e[0m"

# ---------- clone or update ----------
echo -e "\e[93m📥 Cloning or updating repository into $TARGET_DIR...\e[0m"
if [ -d "${TARGET_DIR}/.git" ]; then
  cd "$TARGET_DIR"
  git fetch --all --tags --prune >> "$GIT_LOG" 2>&1 || true
  git reset --hard origin/HEAD >> "$GIT_LOG" 2>&1 || true
else
  rm -rf "$TARGET_DIR" 2>/dev/null || true
  if ! git clone "$REPO_URL" "$TARGET_DIR" >> "$GIT_LOG" 2>&1; then
    echo -e "\e[91m❌ Git clone failed. See $GIT_LOG\e[0m"
    exit 1
  fi
fi

cd "$TARGET_DIR"

# ---------- bun install and single trust pass ----------
echo -e "\e[93m📦 Running bun install (simple flow)...\e[0m"
if [ -f "bun.lockb" ] || [ -f "package.json" ]; then
  "$BUN_BIN" install >> "$BUN_LOG" 2>&1 || true
fi

echo -e "\e[93m🔐 Attempting a single bun trust and install pass...\e[0m"
"$BUN_BIN" pm trust --all >> "$BUN_LOG" 2>&1 || true
"$BUN_BIN" install >> "$BUN_LOG" 2>&1 || true

# ---------- verify run script ----------
if [ -f "${TARGET_DIR}/run" ]; then
  echo -e "\e[92m✅ Node repository is ready (run script present).\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Missing run script in ${TARGET_DIR}. Aborting.\e[0m"
  echo -e "\e[91mCheck: ls -l ${TARGET_DIR}/run\e[0m"
  exit 1
fi

# ---------- show short bun log tail ----------
echo -e "\e[93m🔎 bun log tail (last 40 lines):\e[0m"
tail -n 40 "$BUN_LOG" 2>/dev/null || true

echo -e "\e[92m✅ [04] Clone + dependencies step completed.\e[0m"
exit 0

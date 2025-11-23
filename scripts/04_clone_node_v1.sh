#!/bin/bash
# [04] Clone Demos Node repository and install dependencies (auto-fix Bun untrusted packages)
# - Idempotent clone into /opt/demos-node
# - Uses a stable bun binary (/usr/local/bin/bun) for non-interactive contexts
# - Auto-installs pnpm if required by package preinstall scripts
# - Runs bun pm trust --all, bun install, and bun rebuild in a retry loop
# - Logs detailed bun activity to /var/log/demos-node-bun.log
# - Writes a step marker so re-runs are safe and fast
set -euo pipefail
IFS=$'\n\t'

# ---------- header ----------
echo -e "\e[91m🔧 [04] Cloning Demos Node repository and installing dependencies...\e[0m"
echo -e "\e[91mThis step sets up the node codebase in /opt/demos-node and ensures Bun deps are installed and trusted.\e[0m"

# ---------- markers (idempotency) ----------
MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/04_clone_repo.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[92m✅ [04] Node repository already cloned. Skipping...\e[0m"
  exit 0
fi

# ---------- resolve bun binary for non-interactive contexts ----------
# Prefer global symlink at /usr/local/bin/bun, fallback to any available bun binary,
# create symlink if bun is installed under /root/.bun but not globally linked.
if command -v /usr/local/bin/bun &>/dev/null; then
  BUN_BIN="/usr/local/bin/bun"
elif command -v bun &>/dev/null; then
  BUN_BIN="$(command -v bun)"
elif [ -x "/root/.bun/bin/bun" ]; then
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  BUN_BIN="/usr/local/bin/bun"
else
  echo -e "\e[91m❌ Bun is not available in PATH. Ensure step 03 completed successfully.\e[0m"
  echo -e "\e[91mRun the installer again once Bun is installed:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi

export BUN_BIN
export PATH="$(dirname "$BUN_BIN"):$PATH"
echo -e "\e[93m🔍 Using bun binary: $BUN_BIN\e[0m"

# ---------- repo settings ----------
REPO_URL="https://github.com/kynesyslabs/node.git"
TARGET_DIR="/opt/demos-node"

# ---------- clone repository (idempotent; keep current branch synced) ----------
echo -e "\e[93m📥 Cloning or updating Demos Node repository into $TARGET_DIR...\e[0m"
if [ -d "${TARGET_DIR}/.git" ]; then
  echo -e "\e[93m⚠️ Repository exists at ${TARGET_DIR}. Fetching and resetting to remote HEAD.\e[0m"
  cd "$TARGET_DIR"
  git fetch --all --tags --prune >> /var/log/git-demos-node.log 2>&1 || true
  # Try to reset to remote HEAD; do not fail the entire script on non-critical git issues
  git reset --hard origin/HEAD >> /var/log/git-demos-node.log 2>&1 || true
else
  rm -rf "$TARGET_DIR" 2>/dev/null || true
  if ! git clone "$REPO_URL" "$TARGET_DIR" >> /var/log/git-demos-node.log 2>&1; then
    echo -e "\e[91m❌ Git clone failed. Check network/GitHub access and retry.\e[0m"
    echo -e "\e[91mSee /var/log/git-demos-node.log for details.\e[0m"
    exit 1
  fi
fi

# ---------- prepare bun log (detailed) ----------
BUN_LOG="/var/log/demos-node-bun.log"
mkdir -p "$(dirname "$BUN_LOG")"
: > "$BUN_LOG"

# ---------- install dependencies with bun (initial attempt) ----------
echo -e "\e[93m📦 Installing dependencies with Bun (initial attempt)...\e[0m"
cd "$TARGET_DIR"

if [ -f "bun.lockb" ] || [ -f "package.json" ]; then
  if ! "$BUN_BIN" install >> "$BUN_LOG" 2>&1; then
    echo -e "\e[93m⚠️ bun install initially failed. Cleaning bun cache and retrying...\e[0m"
    "$BUN_BIN" cache clean 2>/dev/null || true
    if ! "$BUN_BIN" install >> "$BUN_LOG" 2>&1; then
      echo -e "\e[91m❌ bun install failed after retry. Inspect $BUN_LOG and re-run the installer.\e[0m"
      exit 1
    fi
  fi
else
  echo -e "\e[93m⚠️ No bun.lockb or package.json found in repo; skipping dependency install.\e[0m"
fi

# ---------- ensure pnpm present early ----------
# Some packages run pnpm in preinstall; install pnpm so those scripts can run
echo -e "\e[93m🔧 Ensuring pnpm is available (some packages expect pnpm in lifecycle scripts)...\e[0m"
if ! command -v pnpm &>/dev/null; then
  # Use npm to install pnpm globally; tolerant to failure but check after
  npm install -g pnpm >> "$BUN_LOG" 2>&1 || true
fi
if command -v pnpm &>/dev/null; then
  echo -e "\e[92m✅ pnpm available at: $(command -v pnpm)\e[0m"
else
  echo -e "\e[93m⚠️ pnpm not available after attempted install. pnpm-dependent preinstall scripts may fail.\e[0m"
fi

# ---------- run a pnpm pass to satisfy pnpm-specific preinstalls (non-fatal) ----------
if [ -f "package.json" ] && command -v pnpm &>/dev/null; then
  echo -e "\e[93m📦 Running pnpm install to allow pnpm-based preinstalls to complete...\e[0m"
  # ignore-scripts=false => allow preinstall / postinstall scripts run by pnpm
  pnpm install --ignore-scripts=false >> "$BUN_LOG" 2>&1 || true
fi

# ---------- automated trust / postinstall repair loop ----------
# This loop attempts to resolve blocked lifecycle scripts automatically:
# - bun pm trust --all
# - bun install
# - bun rebuild (if available)
# - pnpm install if pnpm is present and further preinstalls needed
# Loop until pm untrusted is empty or attempts exhausted.
echo -e "\e[93m🔐 Ensuring Bun packages are trusted and postinstalls have run (logs: $BUN_LOG)...\e[0m"

MAX_ATTEMPTS=4
attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  {
    echo "=== Attempt $attempt - $(date) ==="
    echo "=== bun pm untrusted (before) ==="
    "$BUN_BIN" pm untrusted || true

    echo "=== bun pm trust --all ==="
    "$BUN_BIN" pm trust --all || true

    echo "=== bun pm untrusted (after trust) ==="
    "$BUN_BIN" pm untrusted || true

    echo "=== bun install (post-trust attempt) ==="
    "$BUN_BIN" install || true

    echo "=== bun rebuild (if supported) ==="
    "$BUN_BIN" rebuild || true
  } >> "$BUN_LOG" 2>&1 || true

  # Success condition: no untrusted packages reported
  if ! "$BUN_BIN" pm untrusted | grep -q '.'; then
    echo -e "\e[92m✅ Bun packages trusted and postinstalls attempted (attempt $attempt).\e[0m"
    break
  fi

  # If still untrusted and pnpm exists, attempt pnpm install to satisfy pnpm-specific preinstalls
  if command -v pnpm &>/dev/null; then
    echo -e "\e[93mℹ️ Untrusted packages remain; running pnpm install to satisfy pnpm-based scripts (attempt $attempt)...\e[0m"
    pnpm install --ignore-scripts=false >> "$BUN_LOG" 2>&1 || true
  else
    echo -e "\e[93mℹ️ pnpm not available; skipping pnpm attempt (attempt $attempt).\e[0m"
  fi

  echo -e "\e[93m⚠️ Some packages remain untrusted after attempt $attempt. Retrying after backoff...\e[0m"
  sleep $((attempt * 2))
done

# ---------- final best-effort trust if still blocked ----------
if "$BUN_BIN" pm untrusted | grep -q '.'; then
  echo -e "\e[93m⚠️ bun pm untrusted still reports blocked packages after $MAX_ATTEMPTS attempts.\e[0m"
  echo -e "\e[93mAttempting a final 'bun pm trust --all' and 'bun install' then proceeding; inspect $BUN_LOG for details.\e[0m"
  "$BUN_BIN" pm trust --all >> "$BUN_LOG" 2>&1 || true
  "$BUN_BIN" install >> "$BUN_LOG" 2>&1 || true
else
  echo -e "\e[92m✅ Bun dependency trust and postinstall sequence completed successfully.\e[0m"
fi

# ---------- verify the run script exists and mark step complete ----------
if [ -f "${TARGET_DIR}/run" ]; then
  echo -e "\e[92m✅ Node repository is ready (run script present).\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Missing run script in ${TARGET_DIR}. Aborting.\e[0m"
  echo -e "\e[91mCheck manually: ls -l ${TARGET_DIR}/run\e[0m"
  exit 1
fi

# ---------- show short bun log tail for quick feedback ----------
echo -e "\e[93m🔎 bun log tail (last 40 lines):\e[0m"
tail -n 40 "$BUN_LOG" 2>/dev/null || true

echo -e "\e[92m✅ [04] Clone + dependencies step completed.\e[0m"
exit 0

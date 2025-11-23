#!/bin/bash
# [04] Clone Demos Node repository and install dependencies (auto-fix Bun untrusted packages)
# - Idempotent clone into /opt/demos-node
# - Ensures Node/npm or Corepack available so pnpm can be installed
# - Installs pnpm robustly (corepack -> npm -g -> pnpm install script)
# - Runs an initial pnpm install pass, then bun trust/install/rebuild loop
# - Logs detailed bun activity to /var/log/demos-node-bun.log
set -euo pipefail
IFS=$'\n\t'

# ---------- header ----------
echo -e "\e[91m🔧 [04] Cloning Demos Node repository and installing dependencies...\e[0m"
echo -e "\e[91mThis step sets up /opt/demos-node and makes sure pnpm/bun deps run their lifecycle scripts.\e[0m"

# ---------- markers ----------
MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/04_clone_repo.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[92m✅ [04] Node repository already cloned. Skipping...\e[0m"
  exit 0
fi

# ---------- resolve bun binary ----------
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

# ---------- repo settings ----------
REPO_URL="https://github.com/kynesyslabs/node.git"
TARGET_DIR="/opt/demos-node"
BUN_LOG="/var/log/demos-node-bun.log"
mkdir -p "$(dirname "$BUN_LOG")"
: > "$BUN_LOG"

# ---------- clone or update repository ----------
echo -e "\e[93m📥 Cloning or updating repository into $TARGET_DIR...\e[0m"
if [ -d "${TARGET_DIR}/.git" ]; then
  cd "$TARGET_DIR"
  git fetch --all --tags --prune >> /var/log/git-demos-node.log 2>&1 || true
  git reset --hard origin/HEAD >> /var/log/git-demos-node.log 2>&1 || true
else
  rm -rf "$TARGET_DIR" 2>/dev/null || true
  if ! git clone "$REPO_URL" "$TARGET_DIR" >> /var/log/git-demos-node.log 2>&1; then
    echo -e "\e[91m❌ Git clone failed. See /var/log/git-demos-node.log\e[0m"
    exit 1
  fi
fi

cd "$TARGET_DIR"

# ---------- ensure Node/npm or Corepack available for pnpm ----------
# Some package preinstalls call pnpm. If npm/corepack/pnpm are missing, install them.
ensure_node_and_pnpm() {
  # If pnpm already available, nothing to do
  if command -v pnpm &>/dev/null; then
    echo -e "\e[92m✅ pnpm already available: $(command -v pnpm)\e[0m"
    return 0
  fi

  echo -e "\e[93m🔧 Ensuring Node/npm or Corepack is installed so pnpm can be installed...\e[0m"

  # 1) Try corepack (bundled with Node >=16.13 but disabled by default on some installs)
  if command -v corepack &>/dev/null; then
    echo -e "\e[93mℹ️ corepack present — enabling pnpm via corepack...\e[0m"
    corepack enable 2>> "$BUN_LOG" || true
    corepack prepare pnpm@latest --activate 2>> "$BUN_LOG" || true
    if command -v pnpm &>/dev/null; then
      echo -e "\e[92m✅ pnpm installed via corepack: $(command -v pnpm)\e[0m"
      return 0
    fi
  fi

  # 2) If npm available, install pnpm globally
  if command -v npm &>/dev/null; then
    echo -e "\e[93mℹ️ npm available — installing pnpm globally via npm...\e[0m"
    npm install -g pnpm >> "$BUN_LOG" 2>&1 || true
    if command -v pnpm &>/dev/null; then
      echo -e "\e[92m✅ pnpm installed via npm: $(command -v pnpm)\e[0m"
      return 0
    fi
  fi

  # 3) If neither corepack nor npm existed, install Node.js (NodeSource LTS) to get npm
  if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
    echo -e "\e[93mℹ️ Node/npm missing — installing Node.js 18 LTS via NodeSource (non-interactive)...\e[0m"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >> "$BUN_LOG" 2>&1 || true
    apt-get install -y nodejs >> "$BUN_LOG" 2>&1 || true
    # verify npm now present
    if command -v npm &>/dev/null; then
      echo -e "\e[92m✅ node/npm installed: $(node --version) $(npm --version)\e[0m"
      npm install -g pnpm >> "$BUN_LOG" 2>&1 || true
      if command -v pnpm &>/dev/null; then
        echo -e "\e[92m✅ pnpm installed via npm after Node install: $(command -v pnpm)\e[0m"
        return 0
      fi
    else
      echo -e "\e[93m⚠️ Node/npm install failed; pnpm may not be available. See $BUN_LOG\e[0m"
    fi
  fi

  # 4) fallback: pnpm standalone installer (official script)
  echo -e "\e[93mℹ️ Attempting pnpm standalone installer as fallback...\e[0m"
  curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME=/usr/local pnpm=true bash >> "$BUN_LOG" 2>&1 || true
  # add /usr/local/bin to PATH if necessary (should be already)
  if command -v pnpm &>/dev/null; then
    echo -e "\e[92m✅ pnpm installed via fallback: $(command -v pnpm)\e[0m"
    return 0
  fi

  # If we reach here, pnpm couldn't be installed automatically
  echo -e "\e[93m⚠️ Could not install pnpm automatically. Some package preinstalls may fail. Check $BUN_LOG\e[0m"
  return 1
}

ensure_node_and_pnpm >> "$BUN_LOG" 2>&1 || true

# ---------- run a pnpm install pass if pnpm present (to satisfy pnpm-based preinstalls) ----------
if [ -f "package.json" ] && command -v pnpm &>/dev/null; then
  echo -e "\e[93m📦 Running pnpm install to satisfy pnpm-based preinstall hooks...\e[0m"
  pnpm install --ignore-scripts=false >> "$BUN_LOG" 2>&1 || true
else
  echo -e "\e[93mℹ️ Skipping pnpm pass (package.json missing or pnpm not available)\e[0m"
fi

# ---------- initial bun install (already done earlier or now) ----------
echo -e "\e[93m📦 Ensuring bun install has been run (post-pnpm)...\e[0m"
if [ -f "bun.lockb" ] || [ -f "package.json" ]; then
  "$BUN_BIN" install >> "$BUN_LOG" 2>&1 || true
fi

# ---------- automated trust / postinstall repair loop ----------
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

  # success if no blocked packages remain
  if ! "$BUN_BIN" pm untrusted | grep -q '.'; then
    echo -e "\e[92m✅ Bun packages trusted and postinstalls attempted (attempt $attempt).\e[0m"
    break
  fi

  # if still untrusted and pnpm exists, do another pnpm pass
  if command -v pnpm &>/dev/null; then
    echo -e "\e[93mℹ️ Untrusted packages remain; re-running pnpm install (attempt $attempt)...\e[0m"
    pnpm install --ignore-scripts=false >> "$BUN_LOG" 2>&1 || true
  fi

  echo -e "\e[93m⚠️ Some packages remain untrusted after attempt $attempt. Retrying after backoff...\e[0m"
  sleep $((attempt * 2))
done

# ---------- final best-effort ----------
if "$BUN_BIN" pm untrusted | grep -q '.'; then
  echo -e "\e[93m⚠️ bun pm untrusted still reports blocked packages after $MAX_ATTEMPTS attempts.\e[0m"
  echo -e "\e[93mAttempting a final 'bun pm trust --all' and 'bun install' then proceeding; inspect $BUN_LOG for details.\e[0m"
  "$BUN_BIN" pm trust --all >> "$BUN_LOG" 2>&1 || true
  "$BUN_BIN" install >> "$BUN_LOG" 2>&1 || true
else
  echo -e "\e[92m✅ Bun dependency trust and postinstall sequence completed successfully.\e[0m"
fi

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

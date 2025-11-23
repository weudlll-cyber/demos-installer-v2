#!/bin/bash
# [04] Clone Demos Node repository and install dependencies (robust, non-interactive)
set -euo pipefail
IFS=$'\n\t'

# ---------- configuration ----------
REPO_URL="https://github.com/kynesyslabs/node.git"
TARGET_DIR="/opt/demos-node"
MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/04_clone_repo.done"
BUN_LOG="/var/log/demos-node-bun.log"
GIT_LOG="/var/log/git-demos-node.log"
MAX_BUN_ATTEMPTS=4
GIT_CLONE_TIMEOUT=300    # seconds for shallow clone attempt (increased)
PNPM_INSTALL_TIMEOUT=900 # seconds for pnpm installation attempts (increased)
NODE_SOURCE_SETUP_URL="https://deb.nodesource.com/setup_18.x"

mkdir -p "$MARKER_DIR"
mkdir -p "$(dirname "$BUN_LOG")"
mkdir -p "$(dirname "$GIT_LOG")"
: > "$BUN_LOG"
: > "$GIT_LOG"

echo -e "\e[96m🔧 [04] Clone + deps (non-interactive, robust) starting...\e[0m"

# ---------- idempotency ----------
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[92m✅ [04] already completed. Skipping.\e[0m"
  exit 0
fi

# ---------- ensure /usr/local/bin visible to non-interactive shells ----------
export PATH="/usr/local/bin:$PATH"

# ---------- resolve bun binary ----------
if command -v /usr/local/bin/bun &>/dev/null; then
  BUN_BIN="/usr/local/bin/bun"
elif command -v bun &>/dev/null; then
  BUN_BIN="$(command -v bun)"
elif [ -x "/root/.bun/bin/bun" ]; then
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  BUN_BIN="/usr/local/bin/bun"
else
  echo -e "\e[91m❌ bun not found in PATH. Ensure step 03 completed successfully.\e[0m"
  exit 1
fi
export BUN_BIN
export PATH="/usr/local/bin:$(dirname "$BUN_BIN"):$PATH"
echo -e "\e[93m🔍 Using bun: $BUN_BIN\e[0m"

# ---------- helpers ----------
log_bun() { echo "[$(date -Is)] $*" >> "$BUN_LOG"; }
log_git() { echo "[$(date -Is)] $*" >> "$GIT_LOG"; }

# run apt non-interactively helper
apt_noninteractive() {
  DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" -y "$@" >> "$GIT_LOG" 2>&1
}

# Temporarily disable needrestart to avoid whiptail dialogs; restore later
NEEDRESTART_WAS_ACTIVE=0
disable_needrestart_temporarily() {
  if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^needrestart\.service'; then
    systemctl is-active --quiet needrestart.service && NEEDRESTART_WAS_ACTIVE=1 || NEEDRESTART_WAS_ACTIVE=0
    systemctl stop needrestart.service || true
    systemctl disable needrestart.service || true
    log_bun "needrestart stopped/disabled"
  fi
}
restore_needrestart() {
  if [ "${NEEDRESTART_WAS_ACTIVE:-0}" -eq 1 ]; then
    systemctl enable needrestart.service || true
    systemctl start needrestart.service || true
    log_bun "needrestart restored"
  fi
}
trap 'restore_needrestart || true' EXIT

# ---------- clone repo: shallow with timeout, fallback to tarball ----------
echo -e "\e[93m📥 Cloning repository into $TARGET_DIR (shallow clone with timeout)...\e[0m"
if [ -d "$TARGET_DIR/.git" ]; then
  echo -e "\e[93m⚠️ Repo exists; fetching and resetting to remote HEAD...\e[0m"
  cd "$TARGET_DIR"
  git fetch --all --tags --prune >> "$GIT_LOG" 2>&1 || log_git "git fetch failed"
  git reset --hard origin/HEAD >> "$GIT_LOG" 2>&1 || log_git "git reset failed"
else
  rm -rf "$TARGET_DIR" 2>/dev/null || true
  mkdir -p "$TARGET_DIR"
  if timeout "$GIT_CLONE_TIMEOUT" git clone --depth 1 --single-branch "$REPO_URL" "$TARGET_DIR" >> "$GIT_LOG" 2>&1; then
    log_git "shallow clone succeeded"
  else
    log_git "shallow clone timed out or failed; trying tarball fallback"
    rm -rf "$TARGET_DIR" || true
    mkdir -p "$TARGET_DIR"
    if curl -fsSL "https://codeload.github.com/$(echo "$REPO_URL" | sed -E 's#https://github.com/##')/tar.gz/HEAD" \
         | tar -xz --strip-components=1 -C "$TARGET_DIR" >> "$GIT_LOG" 2>&1; then
      log_git "tarball fallback succeeded"
    else
      log_git "tarball fallback failed; aborting"
      echo -e "\e[91m❌ Could not fetch repository (git clone and tarball fallback failed). See $GIT_LOG\e[0m"
      exit 1
    fi
  fi
fi

cd "$TARGET_DIR"

# ---------- ensure Node/npm/Corepack/pnpm available before lifecycle scripts ----------
echo -e "\e[93m🔧 Ensuring pnpm (and npm/node) are available before lifecycle scripts...\e[0m"
disable_needrestart_temporarily

ensure_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    log_bun "pnpm already available: $(command -v pnpm)"
    return 0
  fi

  # try corepack first
  if command -v corepack >/dev/null 2>&1; then
    log_bun "corepack present; enabling and preparing pnpm"
    corepack enable >> "$BUN_LOG" 2>&1 || true
    corepack prepare pnpm@latest --activate >> "$BUN_LOG" 2>&1 || true
    command -v pnpm >/dev/null 2>&1 && return 0 || true
  fi

  # ensure npm exists (install Node.js if needed)
  if ! command -v npm >/dev/null 2>&1; then
    log_bun "npm missing; installing Node.js 18 LTS (non-interactive)"
    apt_noninteractive update || true
    apt_noninteractive install -y curl ca-certificates gnupg --no-install-recommends || true
    if curl -fsSL "$NODE_SOURCE_SETUP_URL" | bash - >> "$BUN_LOG" 2>&1; then
      apt_noninteractive install -y nodejs || true
    else
      log_bun "NodeSource setup script failed"
    fi
  fi

  # npm global install
  if command -v npm >/dev/null 2>&1; then
    log_bun "installing pnpm via npm -g"
    npm install -g pnpm >> "$BUN_LOG" 2>&1 || true
    if command -v pnpm >/dev/null 2>&1; then
      ln -sf "$(command -v pnpm)" /usr/local/bin/pnpm || true
      return 0
    fi
  fi

  # fallback installer script
  log_bun "attempting pnpm standalone installer fallback"
  curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME=/usr/local pnpm=true bash >> "$BUN_LOG" 2>&1 || true
  if command -v pnpm >/dev/null 2>&1; then
    ln -sf "$(command -v pnpm)" /usr/local/bin/pnpm || true
    return 0
  fi

  log_bun "pnpm could not be installed automatically"
  return 1
}

# Run ensure_pnpm with a generous timeout
if timeout "$PNPM_INSTALL_TIMEOUT" bash -c ensure_pnpm >> "$BUN_LOG" 2>&1; then
  echo -e "\e[92m✅ pnpm is available: $(command -v pnpm || echo unknown)\e[0m"
else
  echo -e "\e[93m⚠️ pnpm installation attempt timed out or failed. Some preinstall scripts may not run.\e[0m"
  log_bun "ensure_pnpm timed out or failed"
fi

# Ensure pnpm visible to the rest of the script
export PATH="/usr/local/bin:$PATH"

# ---------- run a pnpm install pass if package.json exists and pnpm present ----------
if [ -f "package.json" ] && command -v pnpm >/dev/null 2>&1; then
  echo -e "\e[93m📦 Running pnpm install to allow pnpm-based preinstalls to complete...\e[0m"
  pnpm install --ignore-scripts=false >> "$BUN_LOG" 2>&1 || log_bun "pnpm install returned non-zero"
else
  echo -e "\e[93mℹ️ Skipping pnpm pass (package.json missing or pnpm unavailable)\e[0m"
fi

# restore needrestart now that pnpm/node work is done
restore_needrestart

# ---------- bun install and trust/rebuild retry loop ----------
echo -e "\e[93m📦 Ensuring bun install has been run (post-pnpm)...\e[0m"
if [ -f "bun.lockb" ] || [ -f "package.json" ]; then
  "$BUN_BIN" install >> "$BUN_LOG" 2>&1 || log_bun "bun install initial attempt returned non-zero"
fi

echo -e "\e[93m🔐 Running bun trust/install/rebuild loop (retries: $MAX_BUN_ATTEMPTS)...\e[0m"
attempt=0
while [ $attempt -lt "$MAX_BUN_ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  {
    echo "=== Attempt $attempt - $(date -Is) ==="
    echo "=== bun pm untrusted (before) ==="
    "$BUN_BIN" pm untrusted || true

    echo "=== bun pm trust --all ==="
    "$BUN_BIN" pm trust --all || true

    echo "=== bun pm untrusted (after trust) ==="
    "$BUN_BIN" pm untrusted || true

    echo "=== bun install (post-trust) ==="
    "$BUN_BIN" install || true

    echo "=== bun rebuild (if supported) ==="
    "$BUN_BIN" rebuild || true
  } >> "$BUN_LOG" 2>&1 || true

  # success condition
  if ! "$BUN_BIN" pm untrusted | grep -q '.'; then
    echo -e "\e[92m✅ Bun packages trusted and postinstalls attempted (attempt $attempt).\e[0m"
    log_bun "bun pm untrusted empty after attempt $attempt"
    break
  fi

  # attempt pnpm again if available
  if command -v pnpm >/dev/null 2>&1; then
    log_bun "untrusted packages remain; re-running pnpm install (attempt $attempt)"
    pnpm install --ignore-scripts=false >> "$BUN_LOG" 2>&1 || log_bun "pnpm install failed during retry"
  fi

  log_bun "untrusted packages still present after attempt $attempt; backing off and retrying"
  echo -e "\e[93m⚠️ Some packages remain untrusted after attempt $attempt. Retrying after backoff...\e[0m"
  sleep $((attempt * 2))
done

# ---------- final outcome ----------
if "$BUN_BIN" pm untrusted | grep -q '.'; then
  echo -e "\e[93m⚠️ bun pm untrusted still reports blocked packages after $MAX_BUN_ATTEMPTS attempts.\e[0m"
  echo -e "\e[93mInspect $BUN_LOG for details. The script proceeds but lifecycle scripts may be incomplete.\e[0m"
  log_bun "final state: untrusted packages remain; user intervention may be required"
else
  echo -e "\e[92m✅ Bun dependency trust and postinstall sequence completed successfully.\e[0m"
fi

# ---------- verify run script and mark completion ----------
if [ -f "${TARGET_DIR}/run" ]; then
  echo -e "\e[92m✅ Node repository appears ready (run script present).\e[0m"
  touch "$STEP_MARKER"
else
  echo -e "\e[91m❌ Missing run script in ${TARGET_DIR}. Aborting.\e[0m"
  echo -e "\e[91mCheck: ls -l ${TARGET_DIR}/run\e[0m"
  exit 1
fi

# ---------- final logs ----------
echo -e "\e[93m🔎 bun log tail (last 40 lines):\e[0m"
tail -n 40 "$BUN_LOG" 2>/dev/null || true
echo -e "\e[92m✅ [04] completed (see $BUN_LOG and $GIT_LOG for details).\e[0m"
exit 0

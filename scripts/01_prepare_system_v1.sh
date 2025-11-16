#!/bin/bash
# Step 01: Prepare system for Demos Node installation
# Ensures compatibility, repairs package state, verifies required tools, and confirms GitHub DNS reachability.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [01] Preparing your system for Demos Node installation...\e[0m"
echo -e "\e[91mThis step ensures your environment is clean, compatible, and ready for the rest of the setup.\e[0m"

# === Markers ===
MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/01_prepare_system.done"
mkdir -p "$MARKER_DIR"

if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [01] Preparation already completed. Skipping...\e[0m"
  exit 0
fi

# === Root check ===
echo -e "\e[91m🔍 Checking for root privileges...\e[0m"
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo -e "\e[91m❌ This script must be run as root.\e[0m"
  echo -e "\e[91mRun:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi
echo -e "\e[91m✅ Root access confirmed.\e[0m"

# === Sanitize environment ===
echo -e "\e[91m🧹 Unsetting proxy environment variables...\e[0m"
for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  if env | grep -q "^${var}="; then unset "$var"; fi
done
echo -e "\e[91m✅ Environment sanitized.\e[0m"

# === Ubuntu version check ===
echo -e "\e[91m🔍 Verifying Ubuntu version...\e[0m"
UBUNTU_VERSION="$(lsb_release -rs 2>/dev/null || echo "0")"
if ! dpkg --compare-versions "$UBUNTU_VERSION" ge "20.04"; then
  echo -e "\e[91m❌ Unsupported Ubuntu version: $UBUNTU_VERSION\e[0m"
  echo -e "\e[91mPlease upgrade to Ubuntu 20.04 or later.\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi
echo -e "\e[91m✅ Ubuntu $UBUNTU_VERSION is supported.\e[0m"

# === systemd check ===
echo -e "\e[91m🔍 Checking for systemd...\e[0m"
if ! command -v systemctl &>/dev/null; then
  echo -e "\e[91m❌ systemd is not available.\e[0m"
  echo -e "\e[91mDemos Node requires systemd to manage its service.\e[0m"
  echo -e "\e[91mUse a full Ubuntu installation (not WSL/minimal containers).\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi
echo -e "\e[91m✅ systemd is available.\e[0m"

# === Git check/install ===
echo -e "\e[91m🔍 Checking for Git...\e[0m"
if ! command -v git &>/dev/null; then
  echo -e "\e[91m⚠️ Git not found. Installing...\e[0m"
  apt-get update && apt-get install -y git || {
    echo -e "\e[91m❌ Git installation failed.\e[0m"
    echo -e "\e[91mRun manually:\e[0m"
    echo -e "\e[91msudo apt-get install -y git\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  }
fi
echo -e "\e[91m✅ Git is installed.\e[0m"

# === curl check/install ===
echo -e "\e[91m🔍 Checking for curl...\e[0m"
if ! command -v curl &>/dev/null; then
  echo -e "\e[91m⚠️ curl not found. Installing...\e[0m"
  apt-get update && apt-get install -y curl || {
    echo -e "\e[91m❌ curl installation failed.\e[0m"
    echo -e "\e[91mRun manually:\e[0m"
    echo -e "\e[91msudo apt-get install -y curl\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  }
fi
echo -e "\e[91m✅ curl is installed.\e[0m"

# === Repair dpkg if interrupted ===
echo -e "\e[91m🔍 Checking for broken package installations...\e[0m"
if dpkg --audit | grep -q .; then
  echo -e "\e[91m⚠️ dpkg reports pending configuration. Attempting repair...\e[0m"
  echo -e "\e[91m⏳ Waiting up to 2 minutes for dpkg lock to clear...\e[0m"

  LOCK_FILE="/var/lib/dpkg/lock-frontend"
  WAIT_TIME=120
  INTERVAL=10
  WAITED=0

  while sudo fuser "$LOCK_FILE" >/dev/null 2>&1 && [ "$WAITED" -lt "$WAIT_TIME" ]; do
    echo -e "\e[91m⌛ dpkg is locked... ($WAITED/$WAIT_TIME seconds)\e[0m"
    sleep "$INTERVAL"
    WAITED=$((WAITED + INTERVAL))
  done

  if sudo fuser "$LOCK_FILE" >/dev/null 2>&1; then
    echo -e "\e[91m❌ dpkg is still locked after waiting.\e[0m"
    echo -e "\e[91m👉 Please run manually: sudo dpkg --configure -a\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  fi

  dpkg --configure -a || {
    echo -e "\e[91m❌ dpkg repair failed.\e[0m"
    echo -e "\e[91mRun manually:\e[0m"
    echo -e "\e[91msudo dpkg --configure -a\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  }

  if dpkg --audit | grep -q .; then
    echo -e "\e[91m❌ dpkg still reports issues after repair.\e[0m"
    echo -e "\e[91mRun manually:\e[0m"
    echo -e "\e[91msudo dpkg --configure -a\e[0m"
    echo -e "\e[91mThen restart the installer:\e[0m"
    echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
    exit 1
  fi
  echo -e "\e[91m✅ dpkg repair successful.\e[0m"
else
  echo -e "\e[91m✅ No dpkg issues found.\e[0m"
fi

# === DNS check with retry ===
echo -e "\e[91m🌐 Checking GitHub DNS resolution...\e[0m"
MAX_RETRIES=10
for i in $(seq 1 "$MAX_RETRIES"); do
  if getent hosts github.com >/dev/null 2>&1 || ping -c1 -W2 github.com >/dev/null 2>&1; then
    echo -e "\e[91m✅ GitHub DNS resolved.\e[0m"
    touch "$STEP_MARKER"
    exit 0
  else
    backoff=$((i * 2))
    echo -e "\e[91mAttempt $i/$MAX_RETRIES: DNS not ready. Retrying in ${backoff}s...\e[0m"
    sleep "$backoff"
  fi
done

echo -e "\e[91m❌ DNS resolution failed after $MAX_RETRIES attempts.\e[0m"
echo -e "\e[91mCheck network/DNS settings (e.g., resolv.conf, firewall, upstream connectivity).\e[0m"
echo -e "\e[91mThen restart the installer:\e[0m"
echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
exit 1

#!/bin/bash
# This script prepares the system for installing the Demos Node.
# It checks for compatibility, installs missing tools, repairs broken package states,
# and ensures GitHub DNS is reachable before continuing.

set -euo pipefail
IFS=$'\n\t'

echo -e "\e[91m🔧 [01] Preparing your system for Demos Node installation...\e[0m"
echo -e "\e[91mThis step ensures your environment is clean, compatible, and ready for the rest of the setup.\e[0m"

# Create marker directory to track completed steps
MARKER_DIR="/root/.demos_node_setup"
STEP_MARKER="$MARKER_DIR/01_prepare_system.done"
mkdir -p "$MARKER_DIR"

# Skip this step if already completed
if [ -f "$STEP_MARKER" ]; then
  echo -e "\e[91m✅ [01] Preparation already completed. Skipping...\e[0m"
  exit 0
fi

# === Root Check ===
# Many installation steps require root privileges (e.g., installing packages, creating services)
echo -e "\e[91m🔍 Checking for root privileges...\e[0m"
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[91m❌ This script must be run as root.\e[0m"
  echo -e "\e[91mRun:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi
echo -e "\e[91m✅ Root access confirmed.\e[0m"

# === Sanitize Environment ===
# Proxy variables can interfere with network access (e.g., GitHub, curl)
echo -e "\e[91m🧹 Unsetting proxy environment variables...\e[0m"
unset $(env | grep -E '^(http_proxy|https_proxy|no_proxy)=' | cut -d= -f1)
echo -e "\e[91m✅ Environment sanitized.\e[0m"

# === Check Ubuntu Version ===
# Demos Node requires Ubuntu 20.04 or newer for compatibility with Docker and systemd
echo -e "\e[91m🔍 Verifying Ubuntu version...\e[0m"
UBUNTU_VERSION=$(lsb_release -rs || echo "unknown")
if [[ "$UBUNTU_VERSION" < "20.04" ]]; then
  echo -e "\e[91m❌ Unsupported Ubuntu version: $UBUNTU_VERSION\e[0m"
  echo -e "\e[91mPlease upgrade to Ubuntu 20.04 or later.\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi
echo -e "\e[91m✅ Ubuntu $UBUNTU_VERSION is supported.\e[0m"

# === Check for systemd ===
# systemd is required to run the node as a background service
echo -e "\e[91m🔍 Checking for systemd...\e[0m"
if ! command -v systemctl &>/dev/null; then
  echo -e "\e[91m❌ systemd is not available.\e[0m"
  echo -e "\e[91mDemos Node requires systemd to manage its service.\e[0m"
  echo -e "\e[91mMake sure you're using a full Ubuntu installation (not WSL or minimal containers).\e[0m"
  echo -e "\e[91mThen restart the installer:\e[0m"
  echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
  exit 1
fi
echo -e "\e[91m✅ systemd is available.\e[0m"

# === Check for Git ===
# Git is needed to clone the Demos Node repository from GitHub
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

# === Check for curl ===
# curl is used to download Bun and helper scripts
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

# === Repair dpkg if interrupted (with lock wait) ===
# dpkg --audit checks for broken package states
# dpkg --configure -a attempts to fix them
echo -e "\e[91m🔍 Checking for broken package installations...\e[0m"
if dpkg --audit | grep -q .; then
  echo -e "\e[91m⚠️ dpkg was interrupted. Attempting repair...\e[0m"
  echo -e "\e[91mℹ️ This often happens if the VPS is still finishing its initial setup or auto-updates.\e[0m"
  echo -e "\e[91m⏳ Waiting up to 2 minutes for dpkg lock to clear, checking every 10 seconds...\e[0m"

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
    echo -e "\e[91m👉 This usually means the VPS is still setting up. Wait a minute, then run:\e[0m"
    echo -e "\e[91msudo dpkg --configure -a\e[0m"
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

  # Re-check to confirm repair worked
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

# === DNS Check with Retry ===
# GitHub must be reachable to clone the node repository
echo -e "\e[91m🌐 Checking GitHub DNS resolution...\e[0m"
MAX_RETRIES=10
for i in $(seq 1 $MAX_RETRIES); do
  if ping -c1 github.com &>/dev/null; then
    echo -e "\e[91m✅ GitHub DNS resolved.\e[0m"
    touch "$STEP_MARKER"
    exit 0
  else
    echo -e "\e[91mAttempt $i/$MAX_RETRIES: DNS not ready. Retrying in $((i * 2)) seconds...\e[0m"
    sleep $((i * 2))
  fi
done

echo -e "\e[91m❌ DNS resolution failed after $MAX_RETRIES attempts.\e[0m"
echo -e "\e[91mCheck your internet connection or DNS settings.\e[0m"
echo -e "\e[91mThen restart the installer:\e[0m"
echo -e "\e[91msudo bash demos_node_setup_v1.sh\e[0m"
exit 1

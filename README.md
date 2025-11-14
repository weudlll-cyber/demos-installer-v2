# 🛡️ Demos Node Installer
This repository provides a robust, idempotent installer system for setting up a Demos Network node on Ubuntu 24.04+.
It includes:
- ✅ DNS wait and retry for GitHub access
- ✅ apt/dpkg lock detection and recovery
- ✅ Bun and Docker installation
- ✅ Node repo cloning and dependency install
- ✅ Systemd service creation
- ✅ Public IP detection and peerlist setup
- ✅ Key backup, restart, stop, and health-check helpers
- ✅ One-time reboot with resume logic
- ✅ Smart skipping of already-installed components
- ✅ Bright red output for all user-facing messages

🚀 Quick Start
🧱 Install the Demos Node
```
bash
curl -fsSL https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/demos_node_setup_v1.sh | bash
```


🧰 Install the Helper Tools
```
bash
curl -fsSL https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/install_helpers_v1.sh | bash
```


💡 The installer will automatically reboot once to finalize system upgrades.
After reboot, re-run the same command or execute the script locally if you saved it.

🧠 Features
- 🛡️ Idempotent: Safe to re-run. Skips steps already completed.
- 🐳 Container-aware: Skips Docker install if already running.
- 🔁 Reboot-aware: Automatically reboots once and resumes setup.
- 🟥 Red output: All user-facing messages are printed in bright red.
- 🧩 Marker-based logic: Each script writes a .done marker to /root/.demos_node_setup/
- 🩺 Health check: Monitors service status, logs, PID, and optional HTTP endpoint
- 🧰 Helper scripts: Easy commands to manage your node

🧰 Helper Commands
Once installed, you can use the following commands from any terminal:
🔍 Check Node Status
check_demos_node


Shows:
- Systemd status (active, inactive, failed, etc.)
- Main PID
- Optional HTTP health check
- Recent logs if failed
- Recovery hints and restart suggestions

🔄 Restart Node
```bash
restart_demos_node
```


Restarts the systemd service and confirms success.

📊 Unified Log & Health Tool
```bash
logs_demos_node --status
```
Shows systemd status and PID.

```bash
logs_demos_node --logs=100
```
Shows the last 100 lines of logs.

```bash
logs_demos_node --health
```
Performs a full health check:
- Systemd status + explanation
- PID check
- HTTP endpoint check
- Auto-repair if service is inactive or failed


```bash
logs_demos_node --autorestart
```
Restarts the node only if unhealthy.

```bash
logs_demos_node --restart
```
Force restarts the node.

🧪 Recovery Tips
If something fails:
```bash
sudo bash demos_node_setup_v1.sh
```


Check logs:
```bash
sudo journalctl -u demos-node --no-pager --since "10 minutes ago"
```


Restart manually:
```bash
sudo systemctl restart demos-node
```


```
📁 Repository Structure
├── demos_node_setup_v1.sh         # Main installer (orchestrates all scripts)
├── install_helpers_v1.sh          # Standalone installer for helper tools
├── helpers/                       # Executable helper scripts
│   ├── check_demos_node
│   ├── restart_demos_node
│   └── logs_demos_node
├── scripts/                       # Modular installation scripts (01–07)
│   ├── 01_setup_env.sh
│   ├── 02_install_bun.sh
│   ├── 03_install_docker.sh
│   ├── 04_clone_node_repo.sh
│   ├── 05_create_service.sh
│   ├── 06_create_helpers_v1.sh
│   └── 07_finalize_v1.sh
```


Each script in the scripts/ folder is:
- ✅ Executable independently
- ✅ Idempotent (safe to re-run)
- ✅ Marked with a .done file in /root/.demos_node_setup/
- ✅ Designed to be orchestrated by demos_node_setup_v1.sh



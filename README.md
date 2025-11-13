# 🛡️ Demos Node Installer

This repository provides a robust, idempotent installer script for setting up a Demos Network node on Ubuntu 24.04+. It handles:

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

---

🚀 Quick Start

To install a Demos node in one step:

```bash
curl -fsSL https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/demos_node_setup_v1.sh | bash
```

To install the helper programs:

`bash
bash <(curl -fsSL https://raw.githubusercontent.com/weudlll-cyber/demos-installer-v2/main/scripts/installhelpersv1.sh)
`

💡 The script will automatically reboot once to finalize system upgrades.  
After reboot, re-run the same command or execute the script locally if you saved it.

---

🧠 Features

- 🛡️ Idempotent: Safe to re-run. Skips steps already completed.  
- 🐳 Container support: Skips installs if Docker is already running.  
- 🔁 Reboot-aware: Automatically reboots once and resumes setup.  
- 🟥 Red output: All user-facing messages are printed in red.  
- 🧩 Marker-based logic: Each step writes a marker file.  
- 🩺 Health check script: Monitors service status, logs, PID, and optional HTTP endpoint.  

---

🧰 Helper Scripts

These are installed locally and globally:

| Script             | Description                                      |
|--------------------|--------------------------------------------------|
| demosnodesetup | Full installer script                            |
| restart-node     | Restart the node and show systemd status         |
| stop-node        | Stop service, kill processes, free ports         |
| logs-node        | View recent logs from systemd                    |


---

🔐 After Install

To restart and monitor logs:

`bash
restart-node
`

To stop your Demos node:

`bash
stop-node
`

To check node logs:

`bash
logs-node
`

Node source: github.com/weudl/demos-node

---

🩺 Health Check Usage

Show systemd status:

`bash
logs-node --status
`

Tail last 100 lines of journal:

`bash
logs-node --logs=100
`

Check service + PID + optional HTTP endpoint:

`bash
logs-node --health
`

Restart node if unhealthy:

`bash
logs-node --autorestart
`

Force restart:

`bash
logs-node --restart
`

Monitor logs are stored at /var/log/demosnodemonitor.log.

---

🛠️ Troubleshooting

If the installer exits early or skips steps:

- Check /root/.demosnodesetup/ for marker files  
- Delete specific markers to re-run steps:

`bash
rm /root/.demosnodesetup/02installdocker_v1.done
`

If apt locks persist:

- Wait for background processes to finish  
- Re-run the script manually

If Bun blocks postinstalls:

`bash
cd /opt/demos-node
bun pm untrusted
bun install
`

To inspect logs:

`bash
journalctl -u demos-node.service -n 100 --no-pager
`

---

🧪 Development Notes

This script is designed for reproducibility and operational clarity:

- All critical steps are marked and logged  
- Reboot logic is tracked via marker files  
- All user-facing output is bright red for visibility  
- Safe to run manually or via curl  
- Health check script logs to /var/log/demosnodemonitor.log

---

🧑‍💻 Maintainer

Built and maintained by Weudl  
Focused on privacy infrastructure, reproducible workflows, and community education.

# Setup-Server

# 0xZenarch Home Server Setup

Transform any Linux machine into a smart, fully-featured home server with a single command. 

This interactive Bash script automates the deployment of essential home network services. It dynamically detects your package manager (APT, Pacman, or DNF) to ensure seamless cross-distribution compatibility (Ubuntu/Kubuntu, Arch Linux, Fedora).

## Features

* **Samba File Sharing:** Instantly creates a secure, accessible network drive for all your devices.
* **AdGuard Home (Network-Wide Ad Blocker):** Automatically resolves `systemd-resolved` port 53 conflicts, configures firewall rules, and deploys a central DNS sinkhole to block ads and trackers across your entire Wi-Fi network.
* **WireGuard VPN:** Automates secure remote access setup, allowing you to utilize your home ad-blocker and access local files from anywhere in the world.
* **Smart Fallbacks:** Checks for missing dependencies (like `curl` or `ufw`), asks for user permission, and installs them automatically.
* **Safe Execution:** Automatically creates backups of critical configuration files (`smb.conf`, `resolved.conf`) before making any modifications.

## Quick Start

Run the script directly from your terminal without cloning the repository:

```bash
curl -sL [https://raw.githubusercontent.com/mahmoudelsheikh7/Setup-Server/main/setup_server.sh](https://raw.githubusercontent.com/mahmoudelsheikh7/Setup-Server/main/setup_server.sh) | sudo bash


Manual Execution
If you prefer to review the code before running:

Clone the repository:

git clone [https://github.com/mahmoudelsheikh7/Setup-Server.git](https://github.com/mahmoudelsheikh7/Setup-Server.git)


Navigate to the directory:

Bash
cd Setup-Server
Make the script executable:

Bash
chmod +x setup_server.sh
Run with root privileges:

Bash
sudo ./setup_server.sh
Post-Installation Guide
Upon successful execution, the script outputs a tailored terminal guide based on your installation choices. It will provide your server's local IP and remind you to:

Connect to your new SMB share via smb://<SERVER_IP>/HomeServer.

Complete the AdGuard Home web setup at http://<SERVER_IP>:3000.

Disable the DHCP server on your ISP router so AdGuard can manage network IP assignments.

Transfer the generated WireGuard .conf profile to your client devices.

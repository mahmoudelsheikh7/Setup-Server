# Setup-Server

### 0xZenarch Home Server Setup

**Transform any Linux machine into a smart, fully-featured home server with a single command.**

This interactive Bash script automates the deployment of essential home network services. It automatically detects your package manager (APT, Pacman, or DNF) for seamless cross-distribution compatibility on Ubuntu/Kubuntu, Arch Linux, and Fedora.

---

## Features

- **Samba File Sharing:** Instantly creates a secure network drive accessible from all your devices.
- **AdGuard Home (Network-Wide Ad Blocker):** Automatically resolves `systemd-resolved` port 53 conflicts, configures firewall rules, and deploys a central DNS sinkhole that blocks ads and trackers across your entire Wi-Fi network.
- **WireGuard VPN:** Automates secure remote access, so you can use your home ad-blocker and reach your local files from anywhere in the world.
- **Smart Fallbacks:** Detects missing dependencies (such as `curl` or `ufw`), asks for your permission, and installs them automatically.
- **Safe Execution:** Creates backups of critical configuration files (`smb.conf`, `resolved.conf`) before making any changes.

## Supported Distributions

| Family | Package Manager | Examples |
|--------|-----------------|----------|
| Debian-based | APT | Ubuntu, Kubuntu |
| Arch-based | Pacman | Arch Linux |
| Red Hat-based | DNF | Fedora |

## Quick Start

Run the script directly from your terminal without cloning the repository:

```bash
curl -sL https://raw.githubusercontent.com/mahmoudelsheikh7/Setup-Server/main/setup_server.sh | sudo bash
```

> **Tip:** Piping a script into `sudo bash` runs it without you reading it first. If you'd like to inspect the code before running it, use the manual method below.

## Manual Execution

1. **Clone the repository:**

   ```bash
   git clone https://github.com/mahmoudelsheikh7/Setup-Server.git
   ```

2. **Navigate to the directory:**

   ```bash
   cd Setup-Server
   ```

3. **Make the script executable:**

   ```bash
   chmod +x setup_server.sh
   ```

4. **Run with root privileges:**

   ```bash
   sudo ./setup_server.sh
   ```

## Post-Installation Guide

Once the script finishes, it prints a terminal guide tailored to the services you selected. It shows your server's local IP and reminds you to:

1. **Connect to your SMB share** at `smb://<SERVER_IP>/HomeServer`.
2. **Complete the AdGuard Home web setup** at `http://<SERVER_IP>:3000`.
3. **Disable the DHCP server on your ISP router** so AdGuard can manage network IP assignments.
4. **Transfer the generated WireGuard `.conf` profile** to your client devices.

---

Made by [0xZenarch](https://github.com/mahmoudelsheikh7)

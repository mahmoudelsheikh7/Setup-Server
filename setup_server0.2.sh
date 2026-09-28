#!/bin/bash
# 0xZenarch Ultimate Home Server Setup Script
# Built to save time, avoid headaches, and automate the boring stuff.

# Colors for a better terminal experience
G='\033[1;32m'
Y='\033[1;33m'
C='\033[1;36m'
R='\033[1;31m'
NC='\033[0m'

echo -e "${C}=================================================${NC}"
echo -e "${G}      0xZenarch Home Server Master Script        ${NC}"
echo -e "${C}=================================================${NC}"

# Check for root privileges (required for installation and services)
if [ "$EUID" -ne 0 ]; then
  echo -e "${R}Error: Please run this script with root privileges (sudo).${NC}"
  exit 1
fi

# Detect the real user behind sudo to avoid setting up files for 'root'
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Smart function to detect the package manager (Supports Ubuntu/Kubuntu, Arch, Fedora)
get_pkg_manager() {
  if command -v apt &>/dev/null; then
    PKG="apt install -y"
    UPDATE="apt update"
  elif command -v pacman &>/dev/null; then
    PKG="pacman -S --noconfirm"
    UPDATE="pacman -Sy"
  elif command -v dnf &>/dev/null; then
    PKG="dnf install -y"
    UPDATE="dnf check-update"
  else
    echo -e "${R}Error: Unsupported package manager!${NC}"
    exit 1
  fi
}
get_pkg_manager

# Function to check for missing tools and prompt for automatic installation
check_and_install() {
  if ! command -v $1 &>/dev/null; then
    echo -e "${Y}Tool [$1] is missing.${NC}"
    read -p "Do you want to install it automatically? (y/n): " choice
    if [[ "$choice" == [Yy]* ]]; then
      echo -e "${G}Installing $1...${NC}"
      $UPDATE &>/dev/null
      $PKG $1
    else
      echo -e "${R}Skipped. You might face issues in the next steps.${NC}"
    fi
  fi
}

# Ensure basic dependencies are installed
check_and_install curl
check_and_install ufw

# ---------------------------------------------------------
# 1. Samba Setup (Network File Sharing)
# ---------------------------------------------------------
echo -e "\n${C}--- [1] Samba Setup (File Sharing) ---${NC}"
read -p "Do you want to setup a Samba file server? (y/n): " ans_samba
if [[ "$ans_samba" == [Yy]* ]]; then

  # Install samba if not present
  if ! command -v smbd &>/dev/null; then
    echo -e "${Y}Installing Samba...${NC}"
    $PKG samba
  fi

  # Confirm the username for Samba access
  read -p "Enter the username for Samba access [Default: $REAL_USER]: " input_user
  SMB_USER=${input_user:-$REAL_USER}
  SMB_HOME=$(getent passwd "$SMB_USER" | cut -d: -f6)

  # Create the shared directory
  mkdir -p "$SMB_HOME/HomeServer"
  chown -R "$SMB_USER:$SMB_USER" "$SMB_HOME/HomeServer"

  # Backup the config file before editing
  cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

  # Append configuration if it doesn't already exist
  if ! grep -q "\\[HomeServer\\]" /etc/samba/smb.conf; then
    echo "
[HomeServer]
path = $SMB_HOME/HomeServer
valid users = $SMB_USER
read only = no
browsable = yes
" >>/etc/samba/smb.conf
    echo -e "${G}HomeServer share added successfully.${NC}"
  else
    echo -e "${Y}Samba config already exists. Skipping modification to prevent duplicates.${NC}"
  fi

  # Enable service and set password
  systemctl enable --now smbd
  echo -e "${Y}Please create a network password for the user ($SMB_USER):${NC}"
  smbpasswd -a "$SMB_USER"
fi

# ---------------------------------------------------------
# 2. AdGuard Home Setup (Network-wide Ad Blocker)
# ---------------------------------------------------------
echo -e "\n${C}--- [2] AdGuard Home Setup (Ad Blocker) ---${NC}"
read -p "Do you want to install AdGuard Home? (y/n): " ans_adg
if [[ "$ans_adg" == [Yy]* ]]; then

  # Fix Port 53 conflict caused by systemd-resolved (common in Ubuntu/Kubuntu)
  echo -e "${Y}Freeing up Port 53 for AdGuard Home...${NC}"
  if [ -f /etc/systemd/resolved.conf ]; then
    cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
    sed -i 's/DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
    systemctl restart systemd-resolved
  fi

  # Open required firewall ports quietly
  ufw allow 53/tcp &>/dev/null
  ufw allow 53/udp &>/dev/null
  ufw allow 80/tcp &>/dev/null
  ufw allow 3000/tcp &>/dev/null

  # Run the official installation script
  echo -e "${G}Downloading and installing AdGuard Home...${NC}"
  curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

  # ---------------------------------------------------------
  # 3. WireGuard VPN Setup (Remote Access)
  # ---------------------------------------------------------
  echo -e "\n${C}--- [3] WireGuard VPN Setup (Secure Remote Access) ---${NC}"
  read -p "Do you want to install WireGuard VPN to access your network remotely? (y/n): " ans_vpn
  if [[ "$ans_vpn" == [Yy]* ]]; then
    echo -e "${G}Launching the automated WireGuard script (Press Enter for default options)...${NC}"
    curl -O https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
    chmod +x wireguard-install.sh
    ./wireguard-install.sh
  fi
fi

# Fetch the current local IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# ---------------------------------------------------------
# Post-Installation Guide
# ---------------------------------------------------------
echo -e "\n${C}======================================================${NC}"
echo -e "${G} 🎉 Setup Complete! Here is your Post-Install Guide: ${NC}"
echo -e "${C}======================================================${NC}"

if [[ "$ans_samba" == [Yy]* ]]; then
  echo -e "${Y}[1] File Sharing (Samba):${NC}"
  echo -e "    Access your files from any device using this path:"
  echo -e "    ${C}smb://$SERVER_IP/HomeServer${NC}\n"
fi

if [[ "$ans_adg" == [Yy]* ]]; then
  echo -e "${Y}[2] AdGuard Home:${NC}"
  echo -e "    - Open your browser and go to: ${C}http://$SERVER_IP:3000${NC}"
  echo -e "    - Complete the initial setup wizard."
  echo -e "    - Disable the DHCP server on your main router."
  echo -e "    - Enable the DHCP server inside AdGuard settings to take control."
  echo -e "    - (Optional) Add encrypted DNS like Cloudflare in Upstream settings.\n"
fi

if [[ "$ans_vpn" == [Yy]* ]]; then
  echo -e "${Y}[3] WireGuard VPN:${NC}"
  echo -e "    - A .conf file has been generated in your current directory."
  echo -e "    - Send this file to your phone and import it into the WireGuard app."
  echo -e "    - You can now enjoy Ad-blocking and file access from anywhere!\n"
fi

echo -e "${G}Enjoy your new command center, 0xZenarch! 🚀${NC}"
echo -e "${C}======================================================${NC}"

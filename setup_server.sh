#!/usr/bin/env bash
# =============================================================================
#  Arcalc Home Server Setup  (v0.3)
#
#  Sets up, step by step and with your permission:
#    1. Samba      - a shared folder on your network
#    2. AdGuard    - a network-wide ad blocker
#    3. WireGuard  - a VPN to reach your home network from anywhere
#
#  Works on Ubuntu/Debian (apt), Arch (pacman) and Fedora (dnf).
#  Every config file is backed up before it is changed.
#
#  Usage:   sudo bash setup_server.sh
#  Help:    bash setup_server.sh --help
# =============================================================================

VERSION="0.3"
LOG_FILE="/var/log/setup-server.log"

# ---------------------------------------------------------------------------
# Colors (only when printing to a real terminal)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  G=$'\033[1;32m'; Y=$'\033[1;33m'; C=$'\033[1;36m'
  R=$'\033[1;31m'; B=$'\033[1m';    NC=$'\033[0m'
else
  G=""; Y=""; C=""; R=""; B=""; NC=""
fi

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
log()  { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
say()  { printf '%b\n' "$*"; }
info() { say "${C}➜${NC} $*"; log "INFO  $*"; }
ok()   { say "${G}✔${NC} $*"; log "OK    $*"; }
warn() { say "${Y}⚠${NC} $*"; log "WARN  $*"; }
err()  { say "${R}✖${NC} $*" >&2; log "ERROR $*"; }
die()  { err "$*"; exit 1; }

header() {
  say "\n${C}=====================================================${NC}"
  say "${B}$*${NC}"
  say "${C}=====================================================${NC}"
}

# Ask a yes/no question.  Usage: ask_yes_no "Question?" [y|n]   (default: y)
ask_yes_no() {
  local prompt="$1" default="${2:-y}" hint reply
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  while true; do
    read -r -p "$(printf '%b' "${Y}?${NC} ${prompt} ${hint}: ")" reply || die "No input available."
    reply="${reply:-$default}"
    case "$reply" in
      [Yy] | [Yy][Ee][Ss]) return 0 ;;
      [Nn] | [Nn][Oo])     return 1 ;;
      *) say "   Please type y (yes) or n (no)." ;;
    esac
  done
}

pause_enter() { read -r -p "$(printf '%b' "${Y}?${NC} Press Enter to continue...")" _ || true; }

trap 'echo; warn "Cancelled. Nothing further will be changed."; exit 130' INT

# ---------------------------------------------------------------------------
# Command-line options
# ---------------------------------------------------------------------------
case "${1:-}" in
  -h | --help)
    cat <<EOF
Arcalc Home Server Setup v$VERSION

Usage: sudo bash setup_server.sh

The script asks before every step. You can say "no" to anything.
Backups of changed files are saved next to the originals (*.bak.<date>).
A log of what happened is written to $LOG_FILE
EOF
    exit 0
    ;;
  -v | --version)
    echo "setup_server.sh v$VERSION"
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Make sure we are root (re-launch with sudo automatically if we can)
# ---------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && [ -f "$0" ]; then
    say "${Y}⚠${NC} This script needs administrator rights. Re-running with sudo..."
    exec sudo bash "$0" "$@"
  fi
  die "Please run this script as root:  sudo bash setup_server.sh"
fi

touch "$LOG_FILE" 2>/dev/null && chmod 600 "$LOG_FILE" 2>/dev/null
log "=== Session started (v$VERSION) ==="

# When started with "curl ... | sudo bash", stdin is the script itself, which
# would swallow our questions. Point stdin at the keyboard instead.
if [ ! -t 0 ]; then
  if (: </dev/tty) 2>/dev/null; then
    exec </dev/tty
  else
    die "This script is interactive and needs a terminal. Download it and run:  sudo bash setup_server.sh"
  fi
fi

# ---------------------------------------------------------------------------
# System detection
# ---------------------------------------------------------------------------
REAL_USER="${SUDO_USER:-}"
[ "$REAL_USER" = "root" ] && REAL_USER=""
USER_HOME=""
[ -n "$REAL_USER" ] && USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

PM=""
detect_pkg_manager() {
  if   command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v pacman  >/dev/null 2>&1; then PM="pacman"
  elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
  else die "Unsupported system: no apt, pacman or dnf found."
  fi
}

APT_UPDATED=0
pkg_install() {
  case "$PM" in
    apt)
      if [ "$APT_UPDATED" -eq 0 ]; then
        info "Refreshing package list..."
        apt-get update -qq && APT_UPDATED=1
      fi
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
      ;;
    pacman) pacman -S --needed --noconfirm "$@" ;;
    dnf)    dnf install -y "$@" ;;
  esac
}

# Make sure a command exists; offer to install its package if not.
# Usage: ensure_cmd <command> [package]
ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  warn "The tool '$cmd' is missing."
  if ask_yes_no "Install '$pkg' now?" y; then
    if pkg_install "$pkg"; then
      ok "Installed $pkg."
      return 0
    fi
    err "Could not install $pkg."
    [ "$PM" = "pacman" ] && warn "On Arch, try 'sudo pacman -Syu' first, then run this script again."
  fi
  return 1
}

FW="none"
detect_firewall() {
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    FW="firewalld"
  elif command -v ufw >/dev/null 2>&1; then
    FW="ufw"
  fi
}

# Open a port in whichever firewall is present. Usage: open_port 53/tcp
open_port() {
  case "$FW" in
    ufw)       ufw allow "$1" >/dev/null 2>&1 && log "ufw: opened $1" ;;
    firewalld) firewall-cmd --quiet --permanent --add-port="$1" && log "firewalld: opened $1" ;;
  esac
}

firewall_finish() {
  case "$FW" in
    firewalld) firewall-cmd --quiet --reload ;;
    ufw)
      if ufw status 2>/dev/null | grep -qi "inactive"; then
        info "Your firewall (ufw) is switched off, so nothing was blocked anyway."
        info "The rules were saved and will apply if you turn it on later."
      fi
      ;;
    none) info "No firewall detected - no ports needed opening." ;;
  esac
}

LAST_BACKUP=""
backup_file() {
  LAST_BACKUP=""
  [ -f "$1" ] || return 0
  LAST_BACKUP="$1.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a "$1" "$LAST_BACKUP" && ok "Backup saved: $LAST_BACKUP"
}

find_service() {
  local s
  for s in "$@"; do
    if systemctl list-unit-files "$s.service" 2>/dev/null | grep -q "^$s.service"; then
      echo "$s"
      return 0
    fi
  done
  return 1
}

get_server_ip() {
  local ip
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  [ -z "$ip" ] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "${ip:-YOUR_SERVER_IP}"
}

# Track what actually succeeded (used for the final guide)
DONE_SAMBA=0
DONE_ADGUARD=0
DONE_VPN=0
WG_CONF=""

# ---------------------------------------------------------------------------
# 1. Samba
# ---------------------------------------------------------------------------
setup_samba() {
  header "[1/3] Samba - shared network folder"
  say "Samba creates a folder called ${B}HomeServer${NC} that your phone, laptop"
  say "and TV can open over your home network - like a private cloud drive."
  ask_yes_no "Set up Samba?" y || { info "Skipping Samba."; return 0; }

  if ! command -v smbd >/dev/null 2>&1; then
    info "Installing Samba..."
    pkg_install samba || { err "Samba installation failed. Skipping."; return 1; }
  fi

  # Pick the user who may access the share
  local default_user="$REAL_USER" input
  while true; do
    read -r -p "$(printf '%b' "${Y}?${NC} Which user should access the share? ${default_user:+[$default_user] }: ")" input || die "No input available."
    SMB_USER="${input:-$default_user}"
    if [ -n "$SMB_USER" ] && id "$SMB_USER" >/dev/null 2>&1; then break; fi
    warn "User '$SMB_USER' does not exist on this computer. Please try again."
  done

  local smb_home smb_group
  smb_home="$(getent passwd "$SMB_USER" | cut -d: -f6)"
  smb_group="$(id -gn "$SMB_USER")"
  SHARE_DIR="$smb_home/HomeServer"

  mkdir -p "$SHARE_DIR"
  chown -R "$SMB_USER:$smb_group" "$SHARE_DIR"
  ok "Shared folder ready: $SHARE_DIR"

  local conf="/etc/samba/smb.conf"
  backup_file "$conf"
  local backup="$LAST_BACKUP"

  # Some distros (e.g. Arch) ship no config at all - create a safe minimal one
  if [ ! -f "$conf" ]; then
    mkdir -p /etc/samba
    cat >"$conf" <<'EOF'
[global]
   workgroup = WORKGROUP
   server string = Home Server
   server role = standalone server
   security = user
   map to guest = never
EOF
    ok "Created a new Samba config."
  fi

  if grep -q '^\[HomeServer\]' "$conf"; then
    warn "A [HomeServer] share already exists in the config - leaving it untouched."
  else
    cat >>"$conf" <<EOF

[HomeServer]
   path = $SHARE_DIR
   valid users = $SMB_USER
   read only = no
   browsable = yes
   create mask = 0664
   directory mask = 0775
EOF
    if command -v testparm >/dev/null 2>&1 && ! testparm -s >/dev/null 2>&1; then
      err "The Samba config has an error."
      if [ -n "$backup" ]; then cp -a "$backup" "$conf" && warn "Your original config was restored."; fi
      return 1
    fi
    ok "Share added to Samba config."
  fi

  # SELinux (Fedora): allow Samba to read/write the folder
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
    info "SELinux is active - allowing Samba to use the shared folder..."
    if command -v semanage >/dev/null 2>&1; then
      semanage fcontext -a -t samba_share_t "$SHARE_DIR(/.*)?" 2>/dev/null ||
        semanage fcontext -m -t samba_share_t "$SHARE_DIR(/.*)?" 2>/dev/null
      restorecon -R "$SHARE_DIR" 2>/dev/null
    else
      chcon -R -t samba_share_t "$SHARE_DIR" 2>/dev/null || warn "Could not set the SELinux label."
    fi
  fi

  # Start the service (its name differs between distros)
  local svc
  svc="$(find_service smbd smb)" || { err "Could not find the Samba service."; return 1; }
  systemctl enable "$svc" >/dev/null 2>&1
  systemctl restart "$svc" || { err "Samba failed to start. Check: systemctl status $svc"; return 1; }
  ok "Samba service ($svc) is running."

  # Password
  say "\nNow choose a ${B}network password${NC} for '$SMB_USER'."
  say "It can differ from your login password. Typing is hidden - that is normal."
  until smbpasswd -a "$SMB_USER"; do
    warn "Password setup did not work."
    ask_yes_no "Try again?" y || { warn "No Samba password set - you will not be able to log in yet."; break; }
  done

  detect_firewall
  open_port 139/tcp
  open_port 445/tcp
  firewall_finish

  DONE_SAMBA=1
}

# ---------------------------------------------------------------------------
# 2. AdGuard Home
# ---------------------------------------------------------------------------
free_port_53() {
  systemctl is-active --quiet systemd-resolved || return 0
  local conf="/etc/systemd/resolved.conf"
  [ -f "$conf" ] || return 0

  info "Your system uses port 53 for its own DNS. Freeing it for AdGuard..."
  backup_file "$conf"

  if grep -qE '^[[:space:]]*#?[[:space:]]*DNSStubListener[[:space:]]*=' "$conf"; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*DNSStubListener[[:space:]]*=.*/DNSStubListener=no/' "$conf"
  elif grep -q '^\[Resolve\]' "$conf"; then
    sed -i '/^\[Resolve\]/a DNSStubListener=no' "$conf"
  else
    printf '\n[Resolve]\nDNSStubListener=no\n' >>"$conf"
  fi

  # Keep this computer's own internet lookups working after the change
  if [ "$(readlink -f /etc/resolv.conf 2>/dev/null)" = "/run/systemd/resolve/stub-resolv.conf" ]; then
    backup_file /etc/resolv.conf
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  fi

  systemctl restart systemd-resolved
  ok "Port 53 is free."
}

setup_adguard() {
  header "[2/3] AdGuard Home - network-wide ad blocker"
  say "AdGuard Home blocks ads and trackers for ${B}every device${NC} on your Wi-Fi"
  say "(phones, smart TVs, laptops) - no app needed on each device."
  ask_yes_no "Install AdGuard Home?" y || { info "Skipping AdGuard Home."; return 0; }

  if [ -d /opt/AdGuardHome ]; then
    ok "AdGuard Home is already installed - skipping the installation."
    DONE_ADGUARD=1
    return 0
  fi

  free_port_53

  if command -v ss >/dev/null 2>&1 && ss -lntup 2>/dev/null | grep -qE ':53[[:space:]]'; then
    warn "Something else is still using port 53:"
    ss -lntup 2>/dev/null | grep -E ':53[[:space:]]' | sed 's/^/     /'
    ask_yes_no "Continue anyway?" n || { info "Skipping AdGuard Home."; return 0; }
  fi

  detect_firewall
  open_port 53/tcp
  open_port 53/udp
  open_port 80/tcp
  open_port 3000/tcp
  firewall_finish

  info "Downloading the official AdGuard Home installer..."
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL "https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh" -o "$tmp"; then
    rm -f "$tmp"
    err "Download failed. Check your internet connection."
    return 1
  fi
  sh "$tmp" -v
  local rc=$?
  rm -f "$tmp"

  if [ $rc -ne 0 ] || [ ! -d /opt/AdGuardHome ]; then
    err "AdGuard Home installation did not finish correctly. See the messages above."
    return 1
  fi
  ok "AdGuard Home installed."
  DONE_ADGUARD=1
}

# ---------------------------------------------------------------------------
# 3. WireGuard
# ---------------------------------------------------------------------------
setup_wireguard() {
  header "[3/3] WireGuard VPN - reach your home network from anywhere"
  say "WireGuard lets your phone connect securely to your home server when you"
  say "are away - to open your files, or to keep the ad blocker on mobile data."
  say "${Y}Note:${NC} you will need to forward one UDP port on your router afterwards."
  ask_yes_no "Install WireGuard VPN?" y || { info "Skipping WireGuard."; return 0; }

  if [ "$DONE_ADGUARD" -eq 1 ]; then
    say "\n${C}Tip:${NC} to use AdGuard through the VPN, when the installer asks for the"
    say "DNS resolver, enter the ${B}Server WireGuard IPv4${NC} it shows (default 10.66.66.1)."
    pause_enter
  else
    say "\n${C}Tip:${NC} press Enter to accept the default answers - they are fine for most homes."
  fi

  info "Downloading the WireGuard installer (by angristan)..."
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL "https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh" -o "$tmp"; then
    rm -f "$tmp"
    err "Download failed. Check your internet connection."
    return 1
  fi
  bash "$tmp"
  local rc=$?
  rm -f "$tmp"
  [ $rc -eq 0 ] || { err "The WireGuard installer reported a problem."; return 1; }

  # Find the newest client profile it created
  local d f
  for d in "$USER_HOME" "/root"; do
    [ -n "$d" ] || continue
    f="$(ls -t "$d"/wg*-client-*.conf 2>/dev/null | head -n1)"
    [ -n "$f" ] && { WG_CONF="$f"; break; }
  done

  DONE_VPN=1
}

# ---------------------------------------------------------------------------
# Final guide
# ---------------------------------------------------------------------------
print_guide() {
  local ip
  ip="$(get_server_ip)"

  header "🎉 All done! Here is what to do next"

  if [ "$DONE_SAMBA" -eq 1 ]; then
    say "\n${Y}[1] Shared folder (Samba)${NC}"
    say "    Linux / macOS / phones:  ${C}smb://$ip/HomeServer${NC}"
    printf '    Windows:                 %b\\\\%s\\HomeServer%b\n' "$C" "$ip" "$NC"
    say "    Log in with your Samba username and the network password you chose."
  fi

  if [ "$DONE_ADGUARD" -eq 1 ]; then
    say "\n${Y}[2] Ad blocker (AdGuard Home)${NC}"
    say "    a) Open ${C}http://$ip:3000${NC} in your browser and follow the setup wizard."
    say "    b) Afterwards the dashboard lives at ${C}http://$ip${NC} (unless you changed the port)."
    say "    c) ${B}Turn it on for your whole network (easiest way):${NC}"
    say "       log in to your router and set its ${B}DNS server${NC} to ${C}$ip${NC}."
    say "    d) Advanced: you can instead let AdGuard hand out IP addresses (DHCP)."
    say "       Only do this if you are comfortable - turn off the router's DHCP first,"
    say "       and never have two DHCP servers on the same network."
    say "    e) Optional: add encrypted DNS (e.g. Cloudflare) under Settings > DNS settings."
  fi

  if [ "$DONE_VPN" -eq 1 ]; then
    say "\n${Y}[3] VPN (WireGuard)${NC}"
    if [ -n "$WG_CONF" ]; then
      say "    Your client profile:  ${C}$WG_CONF${NC}"
    else
      say "    Your client profile (.conf) was saved in your home folder."
    fi
    say "    - On your phone: scan the QR code shown earlier, or import the .conf file"
    say "      in the WireGuard app."
    local wg_port
    wg_port="$(awk -F= '/^ListenPort/{gsub(/ /,"",$2); print $2; exit}' /etc/wireguard/wg0.conf 2>/dev/null)"
    say "    - ${B}Required:${NC} in your router, forward ${B}UDP port ${wg_port:-<the port you chose>}${NC} to ${C}$ip${NC}."
    say "    - To add more devices later, run this script again and choose WireGuard."
  fi

  say "\n${Y}💡 Good to know${NC}"
  say "    - Give this server a ${B}fixed IP${NC} (a 'DHCP reservation' in your router),"
  say "      otherwise its address may change and things will stop working."
  say "    - Backups of changed files are next to the originals (*.bak.<date>)."
  say "    - A log of this session: $LOG_FILE"
  say "\n${G}Enjoy your new home server, Arcalc! 🚀${NC}\n"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  header "Arcalc Home Server Setup  v$VERSION"
  say "This script will guide you step by step. You can answer ${B}no${NC} to anything,"
  say "and every file it changes is backed up first. Press Ctrl+C at any time to stop."
  say "Just press ${B}Enter${NC} to accept the suggested answer shown in [brackets]."
  echo

  detect_pkg_manager
  ok "Detected package manager: $PM"

  info "Checking your internet connection..."
  if ! curl -fsI --max-time 10 https://github.com >/dev/null 2>&1; then
    if ! ensure_cmd curl; then die "'curl' is required."; fi
    curl -fsI --max-time 10 https://github.com >/dev/null 2>&1 ||
      die "No internet connection (could not reach github.com)."
  fi
  ok "Internet connection works."

  ask_yes_no "Ready to start?" y || { info "Okay, nothing was changed. Bye!"; exit 0; }

  setup_samba
  setup_adguard
  setup_wireguard
  print_guide
}

main

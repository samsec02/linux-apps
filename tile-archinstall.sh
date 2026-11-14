#!/usr/bin/env bash
# =============================================================================
#
#   ████████╗██╗██╗     ███████╗
#   ╚══██╔══╝██║██║     ██╔════╝    TILE // ARCH + HYPRLAND
#      ██║   ██║██║     █████╗      Samuel's tiling desktop deployment
#      ██║   ██║██║     ██╔══╝
#      ██║   ██║███████╗███████╗
#      ╚═╝   ╚═╝╚══════╝╚══════╝
#
#  Machines (auto-detected, you confirm):
#    1) Laptop        — Intel CPU/GPU, screen-flicker fix, power profiles
#    2) Desktop       — Ryzen 7 5800X3D + RX 7800 XT, Lutris + Heroic,
#                       dual boot with Windows on a separate drive
#    3) Gaming laptop — Lenovo Legion 5, i7-13700HX + RTX 4070, NVIDIA
#
#  System (same as complete-install.sh):
#    * Chosen disk wiped: GPT, 1 GiB EFI + LUKS2-encrypted Btrfs, zram swap
#    * systemd-boot, English GUI, Swedish keyboard/formats/timezone
#    * User "samuel" with sudo, root locked, PipeWire, Bluetooth, Firefox
#    * Flatpaks: Discord, Signal, Spotify, VSCodium, VLC, Steam, Bitwarden,
#      Mission Center (system monitor, like Task Manager: Ctrl+Shift+Esc)
#    * Firewall (ufw) on: incoming connections blocked, outgoing allowed
#
#  Desktop — Hyprland, ready to use on first login:
#    * Login: greetd + tuigreet (themed text login), then Hyprland
#    * Top bar: Waybar (workspaces, clock, volume, network, battery, power)
#    * App launcher: fuzzel (tap SUPER), notifications: mako
#    * Lock + idle: hyprlock / hypridle, wallpaper generated at install
#    * Terminal kitty, files Thunar, dark theme everywhere, 100% scaling
#    * Shortcut cheat sheet on SUPER + F1
#
#  Note: Hyprland 0.57+ only reads ~/.config/hypr/hyprland.lua (Lua config).
#
#  Run from the official Arch ISO (UEFI mode, internet connected):
#      bash tile-archinstall.sh
#  Skip the animations:
#      FAST=1 bash tile-archinstall.sh
# =============================================================================
set -Eeuo pipefail

# ----------------------------- Common settings -------------------------------
USERNAME="samuel"                 # Linux usernames should be lowercase
FULLNAME="Samuel"
TIMEZONE="Europe/Stockholm"
KEYMAP="sv-latin1"                # Swedish keyboard: console + LUKS password prompt
XKB_LAYOUT="se"                   # Swedish keyboard inside Hyprland
LANG_LOCALE="en_US.UTF-8"         # English menus/GUI
FORMAT_LOCALE="sv_SE.UTF-8"       # Swedish dates, 24h clock, numbers, currency, A4, metric

COMMON_PKGS=(
  # Base system
  base linux linux-firmware
  btrfs-progs cryptsetup dosfstools
  networkmanager sudo nano vim git base-devel man-db man-pages
  zram-generator xdg-user-dirs python
  # Hyprland desktop
  hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  hyprlock hypridle waybar fuzzel mako swaybg
  greetd greetd-tuigreet
  kitty thunar gvfs tumbler firefox
  # Desktop helpers: network/bluetooth/sound tray, keys, screenshots, clipboard
  network-manager-applet blueman pavucontrol brightnessctl playerctl
  grim slurp wl-clipboard libnotify polkit gnome-keyring
  # Firewall: blocks incoming connections, allows outgoing
  ufw
  # Look: dark GTK theme, fonts, Qt on Wayland
  gnome-themes-extra dconf gsettings-desktop-schemas
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
  qt5-wayland qt6-wayland
  # Audio: PipeWire (replaces PulseAudio + JACK)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  # Bluetooth (USB adapters like ASUS's use the built-in btusb driver)
  bluez bluez-utils
  # Apps
  flatpak
)
# Nice-to-haves installed one by one after the base system, so a renamed
# package can never stop the install
EXTRA_PKGS=(hyprpolkitagent hyprland-guiutils cliphist papirus-icon-theme adwaita-cursors)

COMMON_SERVICES=(NetworkManager greetd bluetooth ufw fstrim.timer systemd-timesyncd systemd-boot-update)
COMMON_FLATPAKS=(
  com.discordapp.Discord
  org.signal.Signal
  com.spotify.Client
  com.vscodium.codium
  org.videolan.VLC
  com.valvesoftware.Steam
  com.bitwarden.desktop
  io.missioncenter.MissionCenter   # System monitor, like Task Manager (Ctrl+Shift+Esc)
)
FLATHUB="https://dl.flathub.org/repo/flathub.flatpakrepo"
WALLPAPER_DIR="/usr/share/backgrounds/tile"   # dark.png + light.png

# ----------------------------- Machine profiles ------------------------------
profile_laptop() {
  MACHINE="laptop"
  MACHINE_LABEL="LAPTOP // INTEL"
  DEFAULT_HOSTNAME="arch-laptop"
  IS_LAPTOP="yes"
  MACHINE_PKGS=(
    intel-ucode
    mesa vulkan-intel intel-media-driver   # Intel graphics + video decoding
    sof-firmware                           # Intel laptop sound chips
    power-profiles-daemon                  # Power profiles (shown in the bar)
  )
  MACHINE_SERVICES=(power-profiles-daemon)
  MACHINE_FLATPAKS=()
  KERNEL_PARAMS="quiet i915.enable_psr=0"  # Fixes the screen flicker
  BOOT_TIMEOUT=3
  NVIDIA="no"
  MKINIT_HOOKS="base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck"
}

profile_desktop() {
  MACHINE="desktop"
  MACHINE_LABEL="DESKTOP // AMD"
  DEFAULT_HOSTNAME="arch-desktop"
  IS_LAPTOP="no"
  MACHINE_PKGS=(
    amd-ucode                              # Ryzen 7 5800X3D microcode
    mesa vulkan-radeon                     # RX 7800 XT: OpenGL, Vulkan (RADV), video decoding
  )
  MACHINE_SERVICES=()
  MACHINE_FLATPAKS=(
    net.lutris.Lutris
    com.heroicgameslauncher.hgl
  )
  KERNEL_PARAMS="quiet"
  BOOT_TIMEOUT=5                           # Time to pick Windows in the menu
  NVIDIA="no"
  MKINIT_HOOKS="base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck"
}

profile_gaming_laptop() {
  MACHINE="gaming-laptop"
  MACHINE_LABEL="GAMING LAPTOP // NVIDIA"
  DEFAULT_HOSTNAME="arch-legion"
  IS_LAPTOP="yes"
  MACHINE_PKGS=(
    intel-ucode
    mesa vulkan-intel intel-media-driver   # Intel iGPU (drives the desktop in Hybrid mode)
    nvidia-open nvidia-utils nvidia-settings  # RTX 4070 driver (open kernel modules)
    nvidia-prime                           # "prime-run <app>" = run an app on the RTX 4070
    sof-firmware                           # Intel laptop sound
    power-profiles-daemon                  # Power profiles = Legion quiet/balanced/performance
  )
  MACHINE_SERVICES=(
    power-profiles-daemon
    nvidia-suspend nvidia-hibernate nvidia-resume   # Sleep/wake without a black screen
    nvidia-powerd                                   # Dynamic Boost (more GPU watts when gaming)
  )
  MACHINE_FLATPAKS=(
    net.lutris.Lutris
    com.heroicgameslauncher.hgl
  )
  KERNEL_PARAMS="quiet nvidia_drm.modeset=1"
  BOOT_TIMEOUT=3
  NVIDIA="yes"
  # No "kms" hook: keeps the nouveau driver out of the boot image
  MKINIT_HOOKS="base systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt filesystems fsck"
}

ESP_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
MSR_GUID="e3c9e316-0b5c-4db8-817d-f92df00215ae"   # Microsoft Reserved partition

# =============================================================================
#  UI ENGINE  — colors, boxes, spinner, animated steps
#  (only uses characters the Linux console font can draw)
# =============================================================================
FAST="${FAST:-0}"
LOG=/tmp/arch-install.log
: > "$LOG"

C0=$'\e[0m'; DIM=$'\e[2m'; WH=$'\e[1;37m'
CY=$'\e[1;36m'; MG=$'\e[1;35m'; BL=$'\e[1;34m'
GR=$'\e[1;32m'; YL=$'\e[1;33m'; RD=$'\e[1;31m'

BOX_W=62
RUN_PID=""

cols()     { tput cols 2>/dev/null || echo 80; }
rep()      { local s="" i; for ((i=0; i<$2; i++)); do s+="$1"; done; printf '%s' "$s"; }
pause()    { [[ "$FAST" == 1 ]] || sleep "$1"; }
fmt_time() { printf '%02d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }
cursor_off() { tput civis 2>/dev/null || true; }
cursor_on()  { tput cnorm 2>/dev/null || true; }

typeout() {   # typeout "text" [delay]  — typewriter effect (ASCII text)
  local s="$1" d="${2:-0.008}" i
  if [[ "$FAST" == 1 ]]; then printf '%s' "$s"; return; fi
  for ((i=0; i<${#s}; i++)); do printf '%s' "${s:i:1}"; sleep "$d"; done
}

section() {   # section "PHASE 1" "SYSTEM SCAN"
  local title=" $1 // $2 "
  printf '\n  %s══[%s%s%s]%s%s\n\n' "$MG" "$WH" "$title" "$MG" "$(rep ═ $(( BOX_W - ${#title} - 4 )))" "$C0"
  pause 0.15
}

box() {       # box "TITLE" "line" "line" ...   (lines: plain ASCII)
  local title="$1" l inner=$(( BOX_W - 2 )); shift
  printf '  %s╔══[ %s%s%s ]%s╗%s\n' "$CY" "$WH" "$title" "$CY" "$(rep ═ $(( BOX_W - 6 - ${#title} )))" "$C0"
  for l in "$@"; do
    printf '  %s║%s %-*s %s║%s\n' "$CY" "$C0" "$inner" "${l:0:$inner}" "$CY" "$C0"
    pause 0.02
  done
  printf '  %s╚%s╝%s\n' "$CY" "$(rep ═ "$BOX_W")" "$C0"
}

ok()   { printf '  %s[%s  OK  %s]%s %s\n' "$DIM" "$GR" "$DIM" "$C0" "$1"; pause 0.06; }
note() { printf '  %s[%s INFO %s]%s %s\n' "$DIM" "$CY" "$DIM" "$C0" "$1"; }
warn() { printf '  %s[%s WARN %s]%s %s\n' "$DIM" "$YL" "$DIM" "$C0" "$1"; }

dots() {      # dots "Label" "value"  ->  Label ........... value
  printf '%s %s%s%s %s' "$1" "$DIM" "$(rep . $(( 22 - ${#1} )))" "$C0" "$2"
}

die() {
  cursor_on
  printf '\n  %s╔%s╗%s\n' "$RD" "$(rep ═ "$BOX_W")" "$C0"
  printf '  %s║%s %-*s %s║%s\n' "$RD" "$WH" $(( BOX_W - 2 )) "!! SYSTEM HALT" "$RD" "$C0"
  printf '  %s║%s %-*s %s║%s\n' "$RD" "$C0" $(( BOX_W - 2 )) "${1:0:$(( BOX_W - 2 ))}" "$RD" "$C0"
  printf '  %s╚%s╝%s\n\n' "$RD" "$(rep ═ "$BOX_W")" "$C0"
  exit 1
}

ask() {       # ask "Prompt" varname
  local -n __ans="$2"
  printf '  %s►%s %s' "$CY" "$C0" "$1"
  IFS= read -r __ans
}

read_secret() {   # read_secret "Prompt" varname  — shows * per character
  local -n __sec="$2"
  local c
  __sec=""
  printf '  %s►%s %s: ' "$CY" "$C0" "$1"
  while IFS= read -rsn1 c; do
    if [[ -z "$c" ]]; then
      break
    elif [[ "$c" == $'\x7f' || "$c" == $'\b' ]]; then
      if [[ -n "$__sec" ]]; then __sec="${__sec%?}"; printf '\b \b'; fi
    else
      __sec+="$c"; printf '%s*%s' "$MG" "$C0"
    fi
  done
  echo
}

ask_password() {  # ask_password "What" varname
  local p1 p2
  local -n __pw="$2"
  while true; do
    read_secret "$1" p1
    read_secret "Confirm" p2
    if [[ -n "$p1" && "$p1" == "$p2" ]]; then __pw="$p1"; return; fi
    warn "Empty or mismatched — try again."
  done
}

fail_screen() {
  cursor_on
  printf '\n  %s╔%s╗%s\n' "$RD" "$(rep ═ "$BOX_W")" "$C0"
  printf '  %s║%s %-*s %s║%s\n' "$RD" "$WH" $(( BOX_W - 2 )) "!! DEPLOYMENT FAILED" "$RD" "$C0"
  printf '  %s║%s %-*s %s║%s\n' "$RD" "$C0" $(( BOX_W - 2 )) "Step: ${1:0:50}" "$RD" "$C0"
  printf '  %s╚%s╝%s\n' "$RD" "$(rep ═ "$BOX_W")" "$C0"
  printf '\n  %sLast lines of %s:%s\n' "$DIM" "$LOG" "$C0"
  tail -n 20 "$LOG" | sed 's/^/    /'
  printf '\n  Nothing important is lost — fix the problem (or send the log) and run the script again.\n\n'
  exit 1
}

# Animated step runner. The command's output goes to the log; the screen shows
# a scanner bar, a timer and the latest log line.
STEP=0; TOTAL=0; LAST_OK="yes"
SPIN=("▓░░░░░" "▒▓░░░░" "░▒▓░░░" "░░▒▓░░" "░░░▒▓░" "░░░░▒▓" "░░░░▓▒" "░░░▓▒░" "░░▓▒░░" "░▓▒░░░")
_run() {      # _run hard|soft "LABEL" command args...
  local mode="$1" label="$2"; shift 2
  local t0=$SECONDS i=0 rc=0 head width tailtxt
  STEP=$(( STEP + 1 ))
  head=$(printf '  %s[%02d/%02d]%s %-26s' "$MG" "$STEP" "$TOTAL" "$C0" "${label:0:26}")
  printf '\n>>> [%02d/%02d] %s\n' "$STEP" "$TOTAL" "$label" >> "$LOG"

  ( trap - ERR; "$@" ) >> "$LOG" 2>&1 &
  RUN_PID=$!
  cursor_off
  while kill -0 "$RUN_PID" 2>/dev/null; do
    width=$(( $(cols) - 52 ))
    tailtxt=""
    if (( width > 12 )); then
      tailtxt=$(tail -n 1 "$LOG" 2>/dev/null | tr '\r' '\n' | tail -n 1 | tr -cd '[:print:]')
      tailtxt="${tailtxt:0:$width}"
    fi
    printf '\r\e[K%s %s%s%s %s%s%s %s%s%s' "$head" "$CY" "${SPIN[i % 10]}" "$C0" \
      "$DIM" "$(fmt_time $(( SECONDS - t0 )))" "$C0" "$DIM" "$tailtxt" "$C0"
    i=$(( i + 1 ))
    sleep 0.12
  done
  wait "$RUN_PID" || rc=$?
  RUN_PID=""
  cursor_on

  local took; took=$(fmt_time $(( SECONDS - t0 )))
  if (( rc == 0 )); then
    printf '\r\e[K%s %s██████%s %s%s%s  %s[ DONE ]%s\n' "$head" "$GR" "$C0" "$DIM" "$took" "$C0" "$GR" "$C0"
    LAST_OK="yes"
  elif [[ "$mode" == soft ]]; then
    printf '\r\e[K%s %s░░░░░░%s %s%s%s  %s[DEFER ]%s\n' "$head" "$YL" "$C0" "$DIM" "$took" "$C0" "$YL" "$C0"
    LAST_OK="no"
  else
    printf '\r\e[K%s %s██████%s %s%s%s  %s[ FAIL ]%s\n' "$head" "$RD" "$C0" "$DIM" "$took" "$C0" "$RD" "$C0"
    fail_screen "$label"
  fi
}
run() { _run hard "$@"; }   # must succeed
try() { _run soft "$@"; }   # may fail; result in $LAST_OK

on_err() {
  cursor_on
  printf '\n  %s[ FAIL ]%s Unexpected error on line %s. Log: %s\n\n' "$RD" "$C0" "$1" "$LOG"
}
on_int() {
  trap - INT TERM
  cursor_on; stty echo 2>/dev/null || true
  printf '\n\n  %s[ABORT ]%s Deployment cancelled by operator.\n\n' "$YL" "$C0"
  kill 0 2>/dev/null || true
  exit 130
}
trap 'on_err $LINENO' ERR
trap on_int INT
trap 'cursor_on; stty echo 2>/dev/null || true' EXIT

# ----------------------------- Visual effects --------------------------------
glitch() {    # quick "decrypting" hex stream
  [[ "$FAST" == 1 ]] && return 0
  local i j line n=$(( ($(cols) - 4) / 5 ))
  (( n > 14 )) && n=14
  cursor_off
  for ((i=0; i<14; i++)); do
    line=""
    for ((j=0; j<n; j++)); do line+=$(printf '%04X ' $(( RANDOM * 2 % 65536 ))); done
    printf '  %s%s%s\n' "$DIM" "$line" "$C0"
    sleep 0.03
  done
  sleep 0.15
  cursor_on
}

banner() {
  local art=(
    '████████╗██╗██╗     ███████╗'
    '╚══██╔══╝██║██║     ██╔════╝'
    '   ██║   ██║██║     █████╗  '
    '   ██║   ██║██║     ██╔══╝  '
    '   ██║   ██║███████╗███████╗'
    '   ╚═╝   ╚═╝╚══════╝╚══════╝'
  )
  local colors=("$BL" "$BL" "$CY" "$CY" "$MG" "$MG")
  local side=(
    ""
    "${WH}ARCH + HYPRLAND${C0}  ${DIM}tiling deployment v1.0${C0}"
    "${DIM}dynamic tiling // wayland // dark${C0}"
    "${DIM}operator ${C0}${CY}$USERNAME${C0}"
    "${DIM}target   ${C0}x86_64 / uefi / luks2"
    ""
  )
  local i
  printf '\n'
  for i in "${!art[@]}"; do
    printf '   %s%s%s    %s\n' "${colors[i]}" "${art[i]}" "$C0" "${side[i]}"
    pause 0.05
  done
  printf '   %s%s%s\n' "$DIM" "$(rep ─ 66)" "$C0"
}

done_banner() {
  local art=(
    '██████╗  ██████╗ ███╗   ██╗███████╗'
    '██╔══██╗██╔═══██╗████╗  ██║██╔════╝'
    '██║  ██║██║   ██║██╔██╗ ██║█████╗  '
    '██║  ██║██║   ██║██║╚██╗██║██╔══╝  '
    '██████╔╝╚██████╔╝██║ ╚████║███████╗'
    '╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚══════╝'
  )
  local colors=("$GR" "$GR" "$CY" "$CY" "$MG" "$MG") i
  printf '\n'
  for i in "${!art[@]}"; do
    printf '   %s%s%s\n' "${colors[i]}" "${art[i]}" "$C0"
    pause 0.06
  done
}

app_name() {
  case "$1" in
    *Discord) echo Discord ;;   *Signal) echo Signal ;;    *spotify*) echo Spotify ;;
    *codium)  echo VSCodium ;;  *VLC)    echo VLC ;;       *Steam)    echo Steam ;;
    *bitwarden*) echo Bitwarden ;; *Lutris) echo Lutris ;; *hgl)      echo Heroic ;;
    *MissionCenter) echo "Mission-Center" ;;
    *) echo "${1##*.}" ;;
  esac
}

# =============================================================================
#  PHASE 0 — BOOT SEQUENCE
# =============================================================================
printf '\e[2J\e[H'
glitch
printf '\e[2J\e[H'
banner

[[ $EUID -eq 0 ]] || die "Run as root (you are root by default on the Arch ISO)."

section "PHASE 0" "BOOT SEQUENCE"
printf '  '; typeout "Initializing tiling deployment core..."; printf '\n'; pause 0.2

[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode. Enable UEFI and disable CSM/Legacy in the BIOS."
FW_BITS=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "64")
ok "$(dots "Firmware" "UEFI ${FW_BITS}-bit")"

loadkeys "$KEYMAP"
ok "$(dots "Keymap" "$KEYMAP")"

ping -c1 -W3 archlinux.org &>/dev/null || die "No uplink. Wi-Fi: iwctl -> station wlan0 connect \"SSID\""
ok "$(dots "Uplink" "archlinux.org reachable")"

timedatectl set-ntp true
ok "$(dots "Clock sync" "NTP enabled")"

# Clean up leftovers if the script is re-run
umount -R /mnt 2>/dev/null || true
umount /tmp/winesp 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true
ok "$(dots "Workspace" "clean")"

# =============================================================================
#  PHASE 1 — SYSTEM SCAN
# =============================================================================
section "PHASE 1" "SYSTEM SCAN"

CPU_NAME=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)
CPU_NAME=$(echo "$CPU_NAME" | tr -s ' ')
RAM_MIB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))
GPU_LIST=""
if command -v lspci &>/dev/null; then
  GPU_LIST=$(lspci | grep -Ei 'vga|3d controller|display controller' \
             | sed -E 's/^[^:]+: [^:]+: //; s/ \(rev [^)]*\)//' || true)
fi

SCAN_LINES=("CPU      : ${CPU_NAME:-unknown}")
if [[ -n "$GPU_LIST" ]]; then
  while IFS= read -r g; do SCAN_LINES+=("GPU      : $g"); done <<< "$GPU_LIST"
else
  SCAN_LINES+=("GPU      : unknown")
fi
SCAN_LINES+=("MEMORY   : $(( (RAM_MIB + 512) / 1024 )) GiB")
SCAN_LINES+=("FIRMWARE : UEFI ${FW_BITS}-bit")
box "HARDWARE" "${SCAN_LINES[@]}"

# Suggest a profile from the hardware
SUGGEST=1
if grep -qi 'nvidia' <<< "$GPU_LIST"; then
  SUGGEST=3
elif grep -qiE 'amd|ati|radeon' <<< "$GPU_LIST" && grep -qi 'amd' <<< "$CPU_NAME"; then
  SUGGEST=2
fi

printf '\n  %s┌─ SELECT TARGET PROFILE %s%s\n' "$CY" "$(rep ─ 38)" "$C0"
printf '  %s│%s  %s[1]%s LAPTOP         %sIntel / flicker fix / power profiles%s\n'      "$CY" "$C0" "$MG" "$C0" "$DIM" "$C0"
printf '  %s│%s  %s[2]%s DESKTOP        %sRyzen 5800X3D + RX 7800 XT / dual boot%s\n'    "$CY" "$C0" "$MG" "$C0" "$DIM" "$C0"
printf '  %s│%s  %s[3]%s GAMING LAPTOP  %sLegion 5 / i7-13700HX + RTX 4070 / NVIDIA%s\n' "$CY" "$C0" "$MG" "$C0" "$DIM" "$C0"
printf '  %s└%s%s\n' "$CY" "$(rep ─ 62)" "$C0"
while true; do
  ask "Profile [1-3] (scan suggests ${GR}${SUGGEST}${C0}, Enter = accept): " CHOICE
  CHOICE="${CHOICE:-$SUGGEST}"
  case "$CHOICE" in
    1) profile_laptop;        break ;;
    2) profile_desktop;       break ;;
    3) profile_gaming_laptop; break ;;
    *) warn "Type 1, 2 or 3." ;;
  esac
done
ok "Profile locked: ${MG}${MACHINE_LABEL}${C0}"

PKGS=("${COMMON_PKGS[@]}" "${MACHINE_PKGS[@]}")
SERVICES=("${COMMON_SERVICES[@]}" "${MACHINE_SERVICES[@]}")
FLATPAKS=("${COMMON_FLATPAKS[@]}" "${MACHINE_FLATPAKS[@]}")

# =============================================================================
#  PHASE 2 — TARGET ACQUISITION
# =============================================================================
section "PHASE 2" "TARGET ACQUISITION"

printf '  %sAvailable drives:%s\n' "$DIM" "$C0"
lsblk -dpno NAME,SIZE,MODEL,TRAN -e 7,11 | sed "s/^/    ${CY}►${C0} /"
echo
ask "Drive to ERASE and install on (e.g. /dev/nvme0n1): " DISK
[[ -b "$DISK" ]] || die "$DISK is not a block device."

ISO_DEV=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
if [[ -n "$ISO_DEV" && "$ISO_DEV" == "$DISK"* ]]; then
  die "$DISK is the USB stick you booted from. Pick an internal drive."
fi

# Windows safety check: refuse to silently wipe a Windows drive
CONFIRM_WORD="ERASE"
if lsblk -lno FSTYPE,PARTTYPE "$DISK" | grep -qiE "ntfs|bitlocker|$MSR_GUID"; then
  echo
  lsblk -po NAME,SIZE,FSTYPE,LABEL,MODEL "$DISK" | sed 's/^/    /'
  warn "${YL}WINDOWS DETECTED on this drive!${C0}"
  warn "For dual boot, Arch should go on the OTHER drive."
  CONFIRM_WORD="ERASE WINDOWS"
fi

echo
while true; do
  ask "Hostname [${DEFAULT_HOSTNAME}]: " HOSTNAME
  HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"
  HOSTNAME="${HOSTNAME,,}"
  [[ "$HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] && break
  warn "Letters, digits and dashes only (no spaces, can't start/end with a dash)."
done
ok "Hostname: ${CY}${HOSTNAME}${C0}"

# Desktop: look for Windows' boot files on another drive
WIN_ESP=""
ADD_WINDOWS="no"
if [[ "$MACHINE" == "desktop" ]]; then
  mkdir -p /tmp/winesp
  while read -r part ptype; do
    [[ "${ptype,,}" == "$ESP_GUID" ]] || continue
    [[ "$part" == "$DISK"* ]] && continue          # that disk gets wiped
    if mount -o ro "$part" /tmp/winesp 2>/dev/null; then
      [[ -f /tmp/winesp/EFI/Microsoft/Boot/bootmgfw.efi ]] && WIN_ESP="$part"
      umount /tmp/winesp
    fi
    [[ -n "$WIN_ESP" ]] && break
  done < <(lsblk -lnpo NAME,PARTTYPE)

  if [[ -n "$WIN_ESP" ]]; then
    note "Windows boot manager found on $WIN_ESP"
    ask "Add Windows to the Arch boot menu? [Y/n]: " yn
    [[ "${yn,,}" == "n" ]] || ADD_WINDOWS="yes"
  else
    note "No Windows found on other drives — use the BIOS boot menu (F8 on ASUS) for Windows."
  fi
fi

DISK_BYTES=$(lsblk -bdno SIZE "$DISK")
DISK_GIB=$(( DISK_BYTES / 1024 / 1024 / 1024 ))
ZRAM_MIB=$(( RAM_MIB / 2 < 8192 ? RAM_MIB / 2 : 8192 ))

# Flatpak names, wrapped to fit the box
APP_LINES=(); line="Apps     :"
for f in "${FLATPAKS[@]}"; do
  n=$(app_name "$f")
  if (( ${#line} + ${#n} + 1 > BOX_W - 4 )); then APP_LINES+=("$line"); line="          "; fi
  line+=" $n"
done
APP_LINES+=("$line")

PLAN=(
  "Profile  : $MACHINE_LABEL"
  "Drive    : $DISK (~${DISK_GIB} GiB, ENTIRE DRIVE)"
  "  [1] EFI   1 GiB FAT32 -> /boot"
  "  [2] ROOT  ~$(( DISK_GIB - 1 )) GiB LUKS2 -> Btrfs"
  "            @ @home @log @pkg @snapshots"
  "Swap     : zram ~$(( ZRAM_MIB / 1024 )) GiB (compressed RAM)"
  "Hostname : $HOSTNAME"
  "Operator : $USERNAME (sudo) / root locked"
  "Desktop  : Hyprland / Waybar / dark / 100% scale"
  "Login    : greetd + tuigreet"
  "Firewall : ufw on (incoming blocked, outgoing allowed)"
  "Locale   : English UI / Swedish keyboard + formats"
  "Kernel   : $KERNEL_PARAMS"
  "${APP_LINES[@]}"
)
[[ "$MACHINE" == "desktop" ]] && PLAN+=("Windows  : $( [[ $ADD_WINDOWS == yes ]] && echo "in boot menu (read-only copy)" || echo "not in boot menu")")
echo
box "DEPLOYMENT PLAN" "${PLAN[@]}"

echo
printf '  %s!! ALL DATA ON %s WILL BE DESTROYED !!%s\n\n' "$RD" "$DISK" "$C0"
ask "Type ${RD}${CONFIRM_WORD}${C0} to arm the deployment: " CONFIRM
[[ "$CONFIRM" == "$CONFIRM_WORD" ]] || die "Aborted by operator. Nothing was changed."
ok "${RD}Deployment ARMED${C0}"

# =============================================================================
#  PHASE 3 — CREDENTIALS
# =============================================================================
section "PHASE 3" "CREDENTIALS"
note "Disk encryption key — typed at every boot (Swedish layout)."
ask_password "Encryption key" LUKS_PASS
ok "Encryption key stored in memory"
echo
note "Login password for '$USERNAME' (also unlocks lock screen + keyring)."
ask_password "User password" USER_PASS
ok "Credentials locked"

echo
cursor_off
for i in 3 2 1; do
  printf '\r  %sDEPLOYING IN %s%s%s ...  %s(Ctrl+C to abort)%s' "$YL" "$WH" "$i" "$YL" "$DIM" "$C0"
  sleep 1
done
printf '\r\e[K'
cursor_on

if [[ "$DISK" =~ [0-9]$ ]]; then PART="${DISK}p"; else PART="$DISK"; fi
ESP="${PART}1"
CRYPT="${PART}2"

# =============================================================================
#  STEP FUNCTIONS (each runs with its output in the log)
# =============================================================================
do_partition() {
  for p in $(lsblk -lnpo NAME "$DISK" | tail -n +2); do wipefs -af "$p" || true; done
  wipefs -af "$DISK"
  sgdisk --zap-all "$DISK"
  sgdisk -n1:0:+1G -t1:ef00 -c1:EFI \
         -n2:0:0   -t2:8309 -c2:cryptroot "$DISK"
  partprobe "$DISK"
  udevadm settle
}

do_esp() { mkfs.fat -F32 -n EFI "$ESP"; }

do_luks() {
  printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$CRYPT"
  printf '%s' "$LUKS_PASS" | cryptsetup open --allow-discards --key-file=- "$CRYPT" cryptroot
}

do_btrfs() {
  mkfs.btrfs -f -L arch /dev/mapper/cryptroot
  mount /dev/mapper/cryptroot /mnt
  for sv in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$sv"; done
  umount /mnt

  local o="noatime,compress=zstd"
  mount -o "$o,subvol=@" /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
  mount -o "$o,subvol=@home"      /dev/mapper/cryptroot /mnt/home
  mount -o "$o,subvol=@log"       /dev/mapper/cryptroot /mnt/var/log
  mount -o "$o,subvol=@pkg"       /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
  mount -o "$o,subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
  mount -o fmask=0077,dmask=0077 "$ESP" /mnt/boot
}

do_keyring() {
  sed -Ei 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
  pacman -Sy --noconfirm archlinux-keyring
}

do_pacstrap() {
  mkdir -p /mnt/etc
  printf 'KEYMAP=%s\nXKBLAYOUT=%s\n' "$KEYMAP" "$XKB_LAYOUT" > /mnt/etc/vconsole.conf
  pacstrap -K /mnt "${PKGS[@]}"
}

do_extras() {   # one at a time; a missing one is just skipped
  local p failed=0
  for p in "${EXTRA_PKGS[@]}"; do
    arch-chroot /mnt pacman -S --needed --noconfirm "$p" || { echo "SKIPPED: $p"; failed=1; }
  done
  return "$failed"
}

do_fstab() {
  genfstab -U /mnt >> /mnt/etc/fstab
  sed -Ei 's/,?subvolid=[0-9]+//' /mnt/etc/fstab   # keeps snapshot rollbacks sane
}

# -----------------------------------------------------------------------------
#  The desktop: wallpaper, login screen, helper scripts and dotfiles.
#  Dotfiles go to /etc/skel, so the new user gets them when it's created.
# -----------------------------------------------------------------------------
do_desktop() {
  local S=/mnt/etc/skel/.config
  mkdir -p "$S"/{hypr,waybar/themes,kitty/themes,fuzzel/themes,mako/themes,gtk-3.0,gtk-4.0,tile} \
           /mnt/usr/local/bin /mnt/usr/local/share/tile "/mnt$WALLPAPER_DIR"

  # ---- Wallpapers (dark + light): generated here, no download needed -------
  cat > /mnt/root/gen-wallpaper.py <<'PY'
#!/usr/bin/env python3
# Generates the Tile wallpaper: gradient + soft glows + faint tile-dot grid.
# usage: gen-wallpaper.py dark|light output.png
import math, struct, sys, zlib

W, H = 1920, 1080
mode = sys.argv[1] if len(sys.argv) > 1 else "dark"
out = sys.argv[2] if len(sys.argv) > 2 else "wallpaper.png"

if mode == "light":
    top, bottom = (238, 240, 248), (214, 219, 236)           # paper white -> soft blue-grey
    glows = [  # (cx, cy, radius, (r,g,b), strength)
        (0.18 * W, 0.92 * H, 0.75 * W, (46, 125, 233), 0.20),   # blue, bottom-left
        (0.88 * W, 0.08 * H, 0.60 * W, (152, 84, 241), 0.16),  # purple, top-right
        (0.55 * W, 0.55 * H, 0.35 * W, (0, 113, 151), 0.03),   # faint cyan core
    ]
    GRID, DOT, DOTK = 44, (46, 125, 233), 0.14
else:
    top, bottom = (11, 12, 22), (26, 27, 38)                 # deep navy -> night
    glows = [
        (0.18 * W, 0.92 * H, 0.75 * W, (122, 162, 247), 0.42),  # blue, bottom-left
        (0.88 * W, 0.08 * H, 0.60 * W, (187, 154, 247), 0.34),  # purple, top-right
        (0.55 * W, 0.55 * H, 0.35 * W, (125, 207, 255), 0.06),  # faint cyan core
    ]
    GRID, DOT, DOTK = 44, (122, 162, 247), 0.18

rows = bytearray()
for y in range(H):
    t = y / (H - 1)
    br, bg, bb = (top[i] + (bottom[i] - top[i]) * t for i in range(3))
    rows.append(0)  # PNG filter: none
    gy = (y % GRID) == GRID // 2
    for x in range(W):
        r, g, b = br, bg, bb
        for cx, cy, rad, (gr, gg, gb), s in glows:
            d = math.hypot(x - cx, y - cy) / rad
            if d < 1.0:
                k = s * (1.0 - d) ** 2.2
                r += (gr - r) * k; g += (gg - g) * k; b += (gb - b) * k
        if gy and (x % GRID) == GRID // 2:
            r += (DOT[0] - r) * DOTK; g += (DOT[1] - g) * DOTK; b += (DOT[2] - b) * DOTK
        # tiny dither against banding
        n = ((x * 7 + y * 13) % 5 - 2) * 0.35
        rows += bytes((min(255, max(0, int(r + n))), min(255, max(0, int(g + n))), min(255, max(0, int(b + n)))))

def chunk(tag, data):
    c = tag + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) \
      + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
with open(out, "wb") as f:
    f.write(png)
PY
  arch-chroot /mnt python3 /root/gen-wallpaper.py dark  "$WALLPAPER_DIR/dark.png"
  arch-chroot /mnt python3 /root/gen-wallpaper.py light "$WALLPAPER_DIR/light.png"
  rm -f /mnt/root/gen-wallpaper.py

  # ---- Login screen: greetd + tuigreet -----------------------------------
  mkdir -p /mnt/etc/greetd
  cat > /mnt/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --greeting 'TILE // welcome back' --theme 'border=magenta;text=cyan;prompt=green;time=blue;action=blue;button=magenta;container=black;input=white' --cmd start-hyprland"
user = "greeter"
EOF
  # Unlock the keyring with the login password (Signal, VSCodium, Discord use it)
  if [[ -f /mnt/etc/pam.d/greetd ]] && ! grep -q pam_gnome_keyring /mnt/etc/pam.d/greetd; then
    cat >> /mnt/etc/pam.d/greetd <<'EOF'
auth       optional     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start
password   optional     pam_gnome_keyring.so
EOF
  fi

  # ---- Helper scripts ------------------------------------------------------
  cat > /mnt/usr/local/bin/tile-powermenu <<'EOF'
#!/bin/bash
# Power menu (SUPER + Escape, or the power button in the bar)
choice=$(printf '%s\n' "Lock" "Logout" "Suspend" "Reboot" "Shutdown" \
  | fuzzel --dmenu --prompt "Power ❯ " --lines 5 --width 22)
case "$choice" in
  Lock)     loginctl lock-session ;;
  Logout)   hyprctl dispatch 'hl.dsp.exit()' ;;
  Suspend)  systemctl suspend ;;
  Reboot)   systemctl reboot ;;
  Shutdown) systemctl poweroff ;;
esac
EOF

  cat > /mnt/usr/local/bin/tile-screenshot <<'EOF'
#!/bin/bash
# tile-screenshot area|screen — saves to ~/Pictures/Screenshots and copies it
dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
if [[ "$1" == area ]]; then
  geo=$(slurp) || exit 0
  grim -g "$geo" "$file"
else
  grim "$file"
fi
wl-copy < "$file"
notify-send -i "$file" "Screenshot saved" "Copied to clipboard"
EOF

  cat > /mnt/usr/local/bin/tile-clipboard <<'EOF'
#!/bin/bash
# Clipboard history (SUPER + C)
command -v cliphist >/dev/null || { notify-send "Clipboard history" "cliphist is not installed"; exit 0; }
cliphist list | fuzzel --dmenu --prompt "Clipboard ❯ " --width 60 | cliphist decode | wl-copy
EOF

  cat > /mnt/usr/local/bin/tile-keybinds <<'EOF'
#!/bin/bash
# Shortcut cheat sheet (SUPER + F1)
fuzzel --dmenu --prompt "Shortcuts ❯ " --width 58 --lines 24 < /usr/local/share/tile/keybinds.txt >/dev/null
EOF

  cat > /mnt/usr/local/bin/tile-welcome <<'EOF'
#!/bin/bash
# One-time welcome notification
mark="${XDG_CONFIG_HOME:-$HOME/.config}/.tile-welcome-done"
[[ -f "$mark" ]] && exit 0
sleep 3
notify-send -t 15000 "Welcome to Tile" "Tap SUPER for apps  ·  SUPER + Enter for a terminal\nSUPER + T switches light/dark  ·  SUPER + F1 shows every shortcut"
touch "$mark"
EOF

  cat > /mnt/usr/local/bin/tile-theme <<'EOF'
#!/bin/bash
# tile-theme [toggle|dark|light|init|icon]
#   toggle  switch light <-> dark (SUPER + T, or the sun/moon button in the bar)
#   init    apply the saved theme at login (wallpaper + app colors)
#   icon    print the bar button icon
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="$CFG/tile/theme"
cur=$(cat "$STATE" 2>/dev/null); [[ "$cur" == light ]] || cur=dark

case "${1:-toggle}" in
  icon)       [[ "$cur" == dark ]] && echo "󰖔" || echo "󰖙"; exit 0 ;;
  toggle)     [[ "$cur" == dark ]] && new=light || new=dark ;;
  dark|light) new="$1" ;;
  init)       new="$cur" ;;
  *)          echo "usage: tile-theme [toggle|dark|light]"; exit 1 ;;
esac

mkdir -p "$CFG/tile"; echo "$new" > "$STATE"

# Desktop parts: each has a dark + light file; the active one is a link
ln -sfn "themes/$new.css"  "$CFG/waybar/style.css"
ln -sfn "themes/$new.conf" "$CFG/kitty/theme.conf"
ln -sfn "themes/$new.ini"  "$CFG/fuzzel/fuzzel.ini"
ln -sfn "themes/$new"      "$CFG/mako/config"

# Apps: GTK, libadwaita and Flatpak apps follow these settings live
if [[ "$new" == dark ]]; then
  scheme=prefer-dark;  gtk=Adwaita-dark; icons=Papirus-Dark; preferdark=1
else
  scheme=prefer-light; gtk=Adwaita;      icons=Papirus;      preferdark=0
fi
gsettings set org.gnome.desktop.interface color-scheme "$scheme"
gsettings set org.gnome.desktop.interface gtk-theme "$gtk"
gsettings set org.gnome.desktop.interface icon-theme "$icons"
for v in 3.0 4.0; do
  f="$CFG/gtk-$v/settings.ini"
  [[ -f "$f" ]] && sed -i -e "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=$preferdark/" \
                          -e "s/^gtk-theme-name=.*/gtk-theme-name=$gtk/" \
                          -e "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$icons/" "$f"
done

# Wallpaper
pkill -x swaybg
setsid -f swaybg -i "/usr/share/backgrounds/tile/$new.png" -m fill >/dev/null 2>&1

[[ "$1" == init ]] && exit 0

# Reload the running desktop parts
pkill -SIGUSR2 -x waybar          # bar
pkill -SIGUSR1 -x kitty           # terminal colors
makoctl reload 2>/dev/null        # notifications
hyprctl reload >/dev/null 2>&1    # window borders
notify-send -t 2000 "Tile" "${new^} mode"
EOF
  chmod 755 /mnt/usr/local/bin/tile-*

  cat > /mnt/usr/local/share/tile/keybinds.txt <<'EOF'
SUPER (tap)          App launcher
SUPER + Space        App launcher
SUPER + Enter        Terminal (kitty)
SUPER + B            Browser (Firefox)
SUPER + E            Files (Thunar)
SUPER + Q            Close window
SUPER + F            Fullscreen
SUPER + V            Float / unfloat window
SUPER + J            Flip split direction
SUPER + Arrows       Move focus
SUPER + Shift+Arrows Move window
SUPER + 1..0         Go to workspace 1-10
SUPER + Shift+1..0   Send window to workspace
SUPER + Scroll       Next / previous workspace
SUPER + Mouse drag   Move window (right button: resize)
SUPER + S            Scratchpad (hidden workspace)
SUPER + C            Clipboard history
SUPER + T            Light / dark mode
Ctrl + Shift + Esc   System monitor (Mission Center)
SUPER + L            Lock screen
SUPER + Escape       Power menu
Print                Screenshot of an area
Shift + Print        Screenshot of the whole screen
SUPER + Shift + S    Screenshot of an area
3-finger swipe       Switch workspace (touchpad)
SUPER + F1           This cheat sheet
EOF

  # ---- Hyprland (Lua config, Hyprland 0.57+) -------------------------------
  cat > "$S/hypr/hyprland.lua" <<'EOF'
-- ~/.config/hypr/hyprland.lua  —  Tile desktop
-- Based on Hyprland's official example config. Wiki: https://wiki.hypr.land/configuring/
-- Cheat sheet with every shortcut: SUPER + F1

local terminal    = "kitty"
local fileManager = "thunar"
local browser     = "firefox"
local menu        = "pkill fuzzel || fuzzel"
local mainMod     = "SUPER"

---- THEME: light or dark, saved by tile-theme (SUPER + T) ----
local function read_theme()
    local ok, t = pcall(function()
        local f = io.open(os.getenv("HOME") .. "/.config/tile/theme", "r")
        if not f then return "dark" end
        local v = f:read("*l")
        f:close()
        return v
    end)
    if ok and t == "light" then return "light" end
    return "dark"
end
local light = (read_theme() == "light")

local theme = light and {
    active   = { colors = {"rgba(2e7de9ee)", "rgba(9854f1ee)"}, angle = 45 },
    inactive = "rgba(a8aecbaa)",
    shadow   = 0x44000000,
} or {
    active   = { colors = {"rgba(7aa2f7ee)", "rgba(bb9af7ee)"}, angle = 45 },
    inactive = "rgba(414868aa)",
    shadow   = 0xee0b0c12,
}

---- MONITORS: native resolution, automatic placement, 100% scale ----
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

---- ENVIRONMENT ----
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- The login screen starts Hyprland directly (no login shell), so add the
-- Flatpak app folders here — otherwise Flatpak apps are missing from the launcher
hl.env("XDG_DATA_DIRS", (os.getenv("HOME") or "") .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share")

---- AUTOSTART ----
hl.on("hyprland.start", function()
    hl.exec_cmd("tile-theme init")   -- wallpaper + app colors for the saved theme
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("tile-welcome")
end)

---- LOOK AND FEEL ----
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 12,
        border_size = 2,
        col = {
            active_border   = theme.active,
            inactive_border = theme.inactive,
        },
        resize_on_border = true,
        allow_tearing    = false,
        layout = "dwindle",
    },

    decoration = {
        rounding       = 12,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.95,
        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = theme.shadow,
        },
        blur = {
            enabled  = true,
            size     = 6,
            passes   = 2,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
    },

    input = {
        kb_layout = "se",
        numlock_by_default = true,
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = true,
        },
    },
})

-- Animation curves (Hyprland's defaults)
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, damping = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- Touchpad: 3-finger swipe switches workspace
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

---- KEYBINDINGS ----
-- Apps
hl.bind("Super_L", hl.dsp.exec_cmd(menu), { release = true })   -- tap SUPER = launcher
hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + C",      hl.dsp.exec_cmd("tile-clipboard"))
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd("tile-theme toggle"))
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("flatpak run io.missioncenter.MissionCenter"))  -- like Windows
hl.bind(mainMod .. " + F1",     hl.dsp.exec_cmd("tile-keybinds"))
hl.bind(mainMod .. " + L",      hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("tile-powermenu"))

-- Windows
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- Focus / move with arrows
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mainMod .. " + " .. dir,           hl.dsp.focus({ direction = dir }))
    hl.bind(mainMod .. " + SHIFT + " .. dir,   hl.dsp.window.move({ direction = dir }))
end

-- Workspaces 1-10 (key 0 = workspace 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("tile-screenshot area"))

-- Scroll through workspaces, drag/resize with the mouse
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- Screenshots
hl.bind("Print",         hl.dsp.exec_cmd("tile-screenshot area"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("tile-screenshot screen"))

-- Volume, brightness and media keys
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

---- WINDOW RULES ----
hl.window_rule({
    -- Ignore maximize requests from apps (keeps tiling tidy)
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    -- Small settings tools open as floating windows
    name  = "float-settings-tools",
    match = { class = "^(org.pulseaudio.pavucontrol|pavucontrol|blueman-manager|nm-connection-editor)$" },
    float = true,
})
EOF

  # ---- Lock screen (hyprlock) ------------------------------------------------
  cat > "$S/hypr/hyprlock.conf" <<'EOF'
# Tile lock screen — based on hyprlock's official example
$font = JetBrainsMono Nerd Font

general {
    hide_cursor = true
}

animations {
    enabled = true
    bezier = linear, 1, 1, 0, 0
    animation = fadeIn, 1, 5, linear
    animation = fadeOut, 1, 5, linear
    animation = inputFieldDots, 1, 2, linear
}

background {
    monitor =
    path = screenshot
    blur_passes = 3
    brightness = 0.6
}

input-field {
    monitor =
    size = 20%, 5%
    outline_thickness = 3
    inner_color = rgba(26, 27, 38, 0.6)
    outer_color = rgba(7aa2f7ee) rgba(bb9af7ee) 45deg
    check_color = rgba(9ece6aee) rgba(7dcfffee) 120deg
    fail_color = rgba(f7768eee) rgba(ff007cee) 40deg
    font_color = rgb(192, 202, 245)
    fade_on_empty = false
    rounding = 15
    font_family = $font
    placeholder_text = Password...
    fail_text = $PAMFAIL
    dots_spacing = 0.3
    position = 0, -40
    halign = center
    valign = center
}

# TIME
label {
    monitor =
    text = $TIME
    color = rgba(192, 202, 245, 1.0)
    font_size = 96
    font_family = $font
    position = 0, 160
    halign = center
    valign = center
}

# DATE
label {
    monitor =
    text = cmd[update:60000] date +"%A %d %B"
    color = rgba(169, 177, 214, 1.0)
    font_size = 22
    font_family = $font
    position = 0, 70
    halign = center
    valign = center
}
EOF

  # ---- Idle (hypridle): laptops dim + suspend, desktop only locks ----------
  {
    cat <<'EOF'
# Tile idle rules — based on hypridle's official example
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
}
EOF
    if [[ "$IS_LAPTOP" == "yes" ]]; then
      cat <<'EOF'

# Dim the screen after 2.5 min
listener {
    timeout = 150
    on-timeout = brightnessctl -s set 10
    on-resume = brightnessctl -r
}
EOF
    fi
    cat <<'EOF'

# Lock after 5 min
listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

# Screen off after 5.5 min
listener {
    timeout = 330
    on-timeout = hyprctl dispatch 'hl.dsp.dpms({action = "off"})'
    on-resume = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
}
EOF
    if [[ "$IS_LAPTOP" == "yes" ]]; then
      cat <<'EOF'

# Suspend after 30 min
listener {
    timeout = 1800
    on-timeout = systemctl suspend
}
EOF
    fi
  } > "$S/hypr/hypridle.conf"

  # ---- Top bar (Waybar) ------------------------------------------------------
  local right='"tray", "pulseaudio", "network", "custom/theme", "custom/power"'
  [[ "$IS_LAPTOP" == "yes" ]] && right='"tray", "power-profiles-daemon", "pulseaudio", "network", "battery", "custom/theme", "custom/power"'
  cat > "$S/waybar/config.jsonc" <<EOF
{
    "layer": "top",
    "position": "top",
    "height": 34,
    "margin-top": 8,
    "margin-left": 12,
    "margin-right": 12,
    "spacing": 8,

    "modules-left": ["custom/launcher", "hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": [$right],

    "custom/launcher": {
        "format": "",
        "on-click": "pkill fuzzel || fuzzel",
        "tooltip": false
    },
    "hyprland/workspaces": {
        "format": "{id}",
        "on-click": "activate",
        "persistent-workspaces": { "*": 5 }
    },
    "clock": {
        "format": "{:%H:%M}",
        "format-alt": "{:%A %d %B  %H:%M}",
        "tooltip-format": "<tt>{calendar}</tt>"
    },
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "󰖁 muted",
        "format-icons": { "default": ["", "", ""] },
        "scroll-step": 5,
        "on-click": "pavucontrol",
        "on-click-right": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    },
    "network": {
        "format-wifi": "  {essid}",
        "format-ethernet": "󰈀 wired",
        "format-disconnected": "󰖪 offline",
        "tooltip-format": "{ifname}  {ipaddr}",
        "on-click": "nm-connection-editor"
    },
    "battery": {
        "states": { "warning": 25, "critical": 10 },
        "format": "{icon} {capacity}%",
        "format-charging": "󰂄 {capacity}%",
        "format-icons": ["󰁺", "󰁼", "󰁾", "󰂀", "󰁹"]
    },
    "power-profiles-daemon": {
        "format": "{icon}",
        "tooltip-format": "Power profile: {profile}",
        "format-icons": {
            "default": "󰗑",
            "performance": "󰓅",
            "balanced": "󰗑",
            "power-saver": "󰌪"
        }
    },
    "tray": { "spacing": 10, "icon-size": 16 },
    "custom/theme": {
        "exec": "tile-theme icon",
        "interval": "once",
        "on-click": "tile-theme toggle",
        "tooltip": false
    },
    "custom/power": {
        "format": "",
        "on-click": "tile-powermenu",
        "tooltip": false
    }
}
EOF

  # ---- Two color themes (Tokyo Night style): dark + light ---------------------
  #      Each part gets a dark and a light file; tile-theme links the active one.
  declare -A DARK=(  [bg]=1a1b26 [fg]=c0caf5 [muted]=565f89 [blue]=7aa2f7 [purple]=bb9af7
                     [cyan]=7dcfff [green]=9ece6a [yellow]=e0af68 [red]=f7768e [sel]=33467c )
  declare -A LIGHT=( [bg]=e1e2e7 [fg]=3760bf [muted]=8990b3 [blue]=2e7de9 [purple]=9854f1
                     [cyan]=007197 [green]=587539 [yellow]=8c6c3e [red]=f52a65 [sel]=b7c1e3 )

  write_theme() {   # write_theme dark|light PALETTE ICON-THEME
    local name="$1" icons="$3"
    local -n P="$2"

    # Top bar (Propo font = icons get their real width, so they sit centered)
    cat > "$S/waybar/themes/$name.css" <<EOF
* {
    font-family: "JetBrainsMono Nerd Font Propo", "JetBrainsMono Nerd Font", "Noto Sans", sans-serif;
    font-size: 13px;
    border: none;
    min-height: 0;
}

window#waybar {
    background: transparent;
    color: #${P[fg]};
}

#custom-launcher, #workspaces, #clock, #tray, #pulseaudio, #network,
#battery, #power-profiles-daemon, #custom-theme, #custom-power {
    background: alpha(#${P[bg]}, 0.88);
    border: 1px solid alpha(#${P[blue]}, 0.28);
    border-radius: 12px;
    padding: 0 14px;
}

#custom-launcher { color: #${P[blue]}; font-size: 17px; padding: 0 15px 0 13px; }
#workspaces { padding: 0 6px; }
#workspaces button {
    color: #${P[muted]};
    padding: 0 8px;
    border-radius: 8px;
    background: transparent;
    box-shadow: none;
    text-shadow: none;
}
#workspaces button.active {
    color: #${P[bg]};
    background-image: linear-gradient(90deg, #${P[blue]}, #${P[purple]});
}
#workspaces button:hover { background: alpha(#${P[blue]}, 0.2); color: #${P[fg]}; }
#clock { font-weight: bold; }
#pulseaudio.muted { color: #${P[muted]}; }
#network.disconnected { color: #${P[red]}; }
#battery.charging { color: #${P[green]}; }
#battery.warning:not(.charging) { color: #${P[yellow]}; }
#battery.critical:not(.charging) { color: #${P[red]}; }

/* Icon-only buttons: equal padding on both sides so the icon is centered */
#power-profiles-daemon, #custom-theme, #custom-power { padding: 0 12px; min-width: 16px; }
#power-profiles-daemon.performance { color: #${P[red]}; }
#power-profiles-daemon.balanced    { color: #${P[blue]}; }
#power-profiles-daemon.power-saver { color: #${P[green]}; }
#custom-theme { color: #${P[yellow]}; }
#custom-power { color: #${P[red]}; }

tooltip {
    background: #${P[bg]};
    border: 1px solid #${P[blue]};
    border-radius: 10px;
}
tooltip label { color: #${P[fg]}; }
EOF

    # App launcher: compact, and dpi-aware=no so it doesn't grow huge on
    # sharp laptop screens (fuzzel otherwise scales its font by screen DPI)
    cat > "$S/fuzzel/themes/$name.ini" <<EOF
[main]
font=JetBrainsMono Nerd Font:size=11
dpi-aware=no
icon-theme=$icons
terminal=kitty
prompt="❯ "
width=32
lines=8
horizontal-pad=16
vertical-pad=10
inner-pad=6
layer=overlay

[colors]
background=${P[bg]}f2
text=${P[fg]}ff
prompt=${P[blue]}ff
input=${P[fg]}ff
match=${P[purple]}ff
selection=${P[sel]}ff
selection-text=${P[fg]}ff
selection-match=${P[cyan]}ff
border=${P[blue]}ff

[border]
width=2
radius=12
EOF

    # Notifications
    cat > "$S/mako/themes/$name" <<EOF
font=JetBrainsMono Nerd Font 11
background-color=#${P[bg]}ee
text-color=#${P[fg]}
border-color=#${P[blue]}
border-size=2
border-radius=12
padding=12
margin=12
width=360
default-timeout=5000
icons=1
max-icon-size=48

[urgency=high]
border-color=#${P[red]}
default-timeout=0
EOF
  }

  write_theme dark  DARK  Papirus-Dark
  write_theme light LIGHT Papirus

  # ---- Terminal (kitty): base config + dark/light color files --------------------
  cat > "$S/kitty/kitty.conf" <<'EOF'
font_family      JetBrainsMono Nerd Font
font_size        11.0
background_opacity 0.92
window_padding_width 12
confirm_os_window_close 0
enable_audio_bell no
cursor_shape beam

# Colors: theme.conf links to themes/dark.conf or themes/light.conf (SUPER + T)
include theme.conf
EOF

  cat > "$S/kitty/themes/dark.conf" <<'EOF'
foreground #c0caf5
background #1a1b26
selection_foreground #1a1b26
selection_background #7aa2f7
cursor #c0caf5
url_color #73daca
color0  #15161e
color8  #414868
color1  #f7768e
color9  #f7768e
color2  #9ece6a
color10 #9ece6a
color3  #e0af68
color11 #e0af68
color4  #7aa2f7
color12 #7aa2f7
color5  #bb9af7
color13 #bb9af7
color6  #7dcfff
color14 #7dcfff
color7  #a9b1d6
color15 #c0caf5
EOF

  cat > "$S/kitty/themes/light.conf" <<'EOF'
foreground #3760bf
background #e1e2e7
selection_foreground #3760bf
selection_background #b7c1e3
cursor #3760bf
url_color #387068
color0  #e9e9ed
color8  #a1a6c5
color1  #f52a65
color9  #f52a65
color2  #587539
color10 #587539
color3  #8c6c3e
color11 #8c6c3e
color4  #2e7de9
color12 #2e7de9
color5  #9854f1
color13 #9854f1
color6  #007197
color14 #007197
color7  #6172b0
color15 #3760bf
EOF

  # Start in dark mode (the links are copied into the new user's home)
  ln -sfn themes/dark.css  "$S/waybar/style.css"
  ln -sfn themes/dark.conf "$S/kitty/theme.conf"
  ln -sfn themes/dark.ini  "$S/fuzzel/fuzzel.ini"
  ln -sfn themes/dark      "$S/mako/config"
  echo dark > "$S/tile/theme"

  # ---- Dark GTK theme + default apps -----------------------------------------
  for v in 3.0 4.0; do
    cat > "$S/gtk-$v/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 10
EOF
  done

  cat > "$S/mimeapps.list" <<'EOF'
[Default Applications]
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
text/html=firefox.desktop
application/pdf=firefox.desktop
inode/directory=thunar.desktop
EOF

  # System-wide dark defaults (also makes Flatpak apps dark via the portal)
  mkdir -p /mnt/etc/dconf/profile /mnt/etc/dconf/db/local.d
  printf 'user-db:user\nsystem-db:local\n' > /mnt/etc/dconf/profile/user
  cat > /mnt/etc/dconf/db/local.d/00-tile <<'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
icon-theme='Papirus-Dark'
cursor-theme='Adwaita'
cursor-size=24
font-name='Noto Sans 10'
monospace-font-name='JetBrainsMono Nerd Font 11'
EOF
  arch-chroot /mnt dconf update
}

do_configure() {
  declare -p USERNAME FULLNAME HOSTNAME TIMEZONE LANG_LOCALE FORMAT_LOCALE \
             KERNEL_PARAMS CRYPT_UUID SERVICES BOOT_TIMEOUT MKINIT_HOOKS \
             > /mnt/root/install.env

  cat > /mnt/root/setup.sh <<'CHROOT'
set -euo pipefail
source /root/install.env

# Time & locale
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
for loc in "$LANG_LOCALE" "$FORMAT_LOCALE"; do
  sed -i "s/^#\(${loc} UTF-8\)/\1/" /etc/locale.gen
done
locale-gen
# English text everywhere, Swedish formats (dates, 24h, numbers, kr, A4, metric)
cat > /etc/locale.conf <<EOF
LANG=$LANG_LOCALE
LC_TIME=$FORMAT_LOCALE
LC_NUMERIC=$FORMAT_LOCALE
LC_MONETARY=$FORMAT_LOCALE
LC_PAPER=$FORMAT_LOCALE
LC_MEASUREMENT=$FORMAT_LOCALE
LC_ADDRESS=$FORMAT_LOCALE
LC_TELEPHONE=$FORMAT_LOCALE
LC_NAME=$FORMAT_LOCALE
EOF

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# systemd-based initramfs with encryption
sed -Ei "s/^HOOKS=.*/HOOKS=($MKINIT_HOOKS)/" /etc/mkinitcpio.conf
mkinitcpio -P

# systemd-boot
bootctl install
cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout $BOOT_TIMEOUT
console-mode max
editor no
EOF
OPTIONS="rd.luks.name=$CRYPT_UUID=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot rootflags=subvol=@ rw $KERNEL_PARAMS"
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options $OPTIONS
EOF
if [[ -f /boot/initramfs-linux-fallback.img ]]; then
cat > /boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options $OPTIONS
EOF
fi

# zram swap (half of RAM, max 8 GiB)
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
EOF

# User + sudo (gets the Tile dotfiles from /etc/skel). Root is locked.
useradd -m -G wheel,video,input -c "$FULLNAME" -s /bin/bash "$USERNAME"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
passwd -l root

# Faster pacman on the installed system too
sed -Ei 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

# Firewall: block everything incoming, allow everything outgoing.
# (ufw still allows replies to your own connections, plus local network
#  discovery like mDNS, so things like Spotify Connect keep working.)
sed -i 's/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY="DROP"/;
        s/^DEFAULT_OUTPUT_POLICY=.*/DEFAULT_OUTPUT_POLICY="ACCEPT"/' /etc/default/ufw
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf

# Services (one at a time, so one missing service can't stop the install)
for s in "${SERVICES[@]}"; do
  systemctl enable "$s" || echo "WARNING: could not enable $s"
done
CHROOT

  arch-chroot /mnt bash /root/setup.sh
}

do_user() {
  printf '%s:%s\n' "$USERNAME" "$USER_PASS" | arch-chroot /mnt chpasswd
  rm -f /mnt/root/setup.sh /mnt/root/install.env
}

do_windows() {
  # systemd-boot only sees its own EFI partition, so copy Windows' boot
  # manager there; it shows up automatically as "Windows Boot Manager".
  # The Windows drive is only mounted read-only — nothing on it is changed.
  mount -o ro "$WIN_ESP" /tmp/winesp
  mkdir -p /mnt/boot/EFI
  cp -r /tmp/winesp/EFI/Microsoft /mnt/boot/EFI/
  umount /tmp/winesp
}

do_flatpaks() {
  arch-chroot /mnt flatpak remote-add --if-not-exists flathub "$FLATHUB" &&
  arch-chroot /mnt flatpak install -y --noninteractive --system flathub "${FLATPAKS[@]}"
}

do_finalize() {
  # A first-boot job is needed if the Flatpak step was deferred, or on NVIDIA:
  # Flatpak apps (Steam!) need an NVIDIA add-on matching the driver, and
  # Flatpak can only detect the driver once the real system has booted.
  if [[ "$FLATPAK_OK" == "no" || "$NVIDIA" == "yes" ]]; then
    cat > /mnt/etc/systemd/system/flatpak-firstboot.service <<EOF
[Unit]
Description=Install Flatpak apps on first boot
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/var/lib/flatpak-firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak remote-add --if-not-exists flathub $FLATHUB
ExecStart=/usr/bin/flatpak install -y --noninteractive --or-update --system flathub ${FLATPAKS[*]}
ExecStart=/usr/bin/flatpak update -y --noninteractive --system
ExecStartPost=/usr/bin/touch /var/lib/flatpak-firstboot.done
ExecStartPost=/usr/bin/systemctl disable flatpak-firstboot.service
Restart=on-failure
RestartSec=60
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    arch-chroot /mnt systemctl enable flatpak-firstboot.service
  fi
  cp "$LOG" /mnt/var/log/arch-install.log || true
  sync
  umount -R /mnt
  cryptsetup close cryptroot
}

# =============================================================================
#  PHASE 4 — DEPLOYMENT
# =============================================================================
TOTAL=14
[[ "$ADD_WINDOWS" == "yes" ]] && TOTAL=15
DEPLOY_START=$SECONDS

section "PHASE 4" "DEPLOYMENT"

run "Wiping + partitioning"    do_partition
run "Formatting EFI"           do_esp
run "Encrypting drive (LUKS2)" do_luks
unset LUKS_PASS
CRYPT_UUID=$(blkid -s UUID -o value "$CRYPT")
run "Building Btrfs volumes"   do_btrfs
run "Syncing package keyring"  do_keyring
run "Installing base system"   do_pacstrap
try "Installing extras"        do_extras
[[ "$LAST_OK" == "yes" ]] || warn "Some extras were skipped (see the log) — the desktop still works."
run "Writing fstab"            do_fstab
run "Building Tile desktop"    do_desktop
run "Configuring system"       do_configure
run "Creating operator"        do_user
unset USER_PASS
if [[ "$ADD_WINDOWS" == "yes" ]]; then
  try "Linking Windows boot"   do_windows
  [[ "$LAST_OK" == "yes" ]] || warn "Couldn't add Windows — use the BIOS boot menu (F8 on ASUS) instead."
fi
try "Deploying Flatpak apps"   do_flatpaks
FLATPAK_OK="$LAST_OK"
run "Finalizing"               do_finalize

ELAPSED=$(fmt_time $(( SECONDS - DEPLOY_START )))

# =============================================================================
#  PHASE 5 — COMPLETE
# =============================================================================
done_banner
echo
SUMMARY=(
  "Profile  : $MACHINE_LABEL"
  "Hostname : $HOSTNAME"
  "Operator : $USERNAME"
  "Desktop  : Hyprland (Tile) / dark / 100% scale"
  "Duration : $ELAPSED"
  "Log      : /var/log/arch-install.log"
)
box "DEPLOYMENT COMPLETE" "${SUMMARY[@]}"

NEXT=(
  "1. Remove the USB stick when the screen goes black"
  "2. Type your encryption key at the boot prompt"
  "3. Log in as '$USERNAME' on the Tile login screen"
  "4. Tap SUPER for apps, SUPER + F1 for every shortcut"
  "5. Wi-Fi: click the network icon in the tray (top right)"
)
if [[ "$FLATPAK_OK" == "no" || "$NVIDIA" == "yes" ]]; then
  NEXT+=("6. Apps finish installing in the background once online"
         "   (watch: journalctl -fu flatpak-firstboot)")
fi
echo
box "NEXT" "${NEXT[@]}"

if [[ "$MACHINE" == "desktop" ]]; then
  echo
  box "DUAL BOOT" \
    "* BIOS: put 'Linux Boot Manager' first in the boot order" \
    "* Windows shows wrong time? In Windows (admin terminal):" \
    "  reg add HKLM\\System\\CurrentControlSet\\Control\\" \
    "  TimeZoneInformation /v RealTimeIsUniversal /d 1" \
    "  /t REG_DWORD /f"
fi
if [[ "$NVIDIA" == "yes" ]]; then
  echo
  box "NVIDIA" \
    "* Check the driver: nvidia-smi" \
    "* Run an app on the RTX 4070: prime-run <app>" \
    "* Steam games pick the RTX 4070 automatically"
fi

echo
ask "Press ${GR}ENTER${C0} to reboot into your new system (Ctrl+C to stay): " _
printf '\n  %sSee you on the other side.%s\n\n' "$CY" "$C0"
sleep 1
reboot

#!/usr/bin/env bash
# =============================================================================
#
#    █████╗ ██████╗  ██████╗██╗  ██╗
#   ██╔══██╗██╔══██╗██╔════╝██║  ██║    COMPLETE INSTALL // v2.0
#   ███████║██████╔╝██║     ███████║    Samuel's automated deployment system
#   ██╔══██║██╔══██╗██║     ██╔══██║
#   ██║  ██║██║  ██║╚██████╗██║  ██║
#   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
#
#  Machines (auto-detected, you confirm):
#    1) Laptop        — Intel CPU/GPU, screen-flicker fix, power profiles
#    2) Desktop       — Ryzen 7 5800X3D + RX 7800 XT, Lutris + Heroic,
#                       dual boot with Windows on a separate drive
#    3) Gaming laptop — Lenovo Legion 5, i7-13700HX + RTX 4070, NVIDIA
#
#  All get:
#    * The chosen disk wiped (GPT: 1 GiB EFI + rest LUKS2-encrypted)
#    * Btrfs inside LUKS (@, @home, @log, @pkg, @snapshots), zram swap
#    * systemd-boot + systemd initramfs (sd-encrypt)
#    * GNOME on Wayland in DARK MODE, 100% display scaling
#    * Dock (Super key): Firefox, Files, Discord, Spotify, Signal
#    * PipeWire audio, Bluetooth, Firefox, NetworkManager
#    * English GUI, Swedish keyboard/formats/timezone
#    * User "samuel" with sudo, root locked
#    * Flatpaks: Discord, Signal, Spotify, VSCodium, VLC, Steam, Bitwarden
#
#  Run from the official Arch ISO (UEFI mode, internet connected):
#      bash complete-install.sh
#  Skip the animations:
#      FAST=1 bash complete-install.sh
# =============================================================================
set -Eeuo pipefail

# ----------------------------- Common settings -------------------------------
USERNAME="samuel"                 # Linux usernames should be lowercase
FULLNAME="Samuel"                 # Shown on the GDM login screen
TIMEZONE="Europe/Stockholm"
KEYMAP="sv-latin1"                # Swedish keyboard: console + LUKS password prompt
XKB_LAYOUT="se"                   # Swedish keyboard: GDM + GNOME (Wayland)
LANG_LOCALE="en_US.UTF-8"         # English menus/GUI
FORMAT_LOCALE="sv_SE.UTF-8"       # Swedish dates, 24h clock, numbers, currency, A4, metric

COMMON_PKGS=(
  # Base system
  base linux linux-firmware
  btrfs-progs cryptsetup dosfstools
  networkmanager sudo nano vim git base-devel man-db man-pages
  zram-generator xdg-user-dirs
  # Desktop
  gnome firefox
  # Audio: PipeWire (replaces PulseAudio + JACK)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  # Bluetooth (USB adapters like ASUS's use the built-in btusb driver;
  # their firmware ships in linux-firmware)
  bluez bluez-utils
  # Apps / fonts
  flatpak noto-fonts noto-fonts-emoji
)
COMMON_SERVICES=(NetworkManager gdm bluetooth fstrim.timer systemd-timesyncd systemd-boot-update)
COMMON_FLATPAKS=(
  com.discordapp.Discord
  org.signal.Signal
  com.spotify.Client
  com.vscodium.codium
  org.videolan.VLC
  com.valvesoftware.Steam
  com.bitwarden.desktop
)
# Pinned apps in the GNOME dock (press the Super/Windows key), in this order
DOCK_APPS=(
  firefox.desktop
  org.gnome.Nautilus.desktop
  com.discordapp.Discord.desktop
  com.spotify.Client.desktop
  org.signal.Signal.desktop
)
FLATHUB="https://dl.flathub.org/repo/flathub.flatpakrepo"

# ----------------------------- Machine profiles ------------------------------
profile_laptop() {
  MACHINE="laptop"
  MACHINE_LABEL="LAPTOP // INTEL"
  DEFAULT_HOSTNAME="arch-laptop"
  MACHINE_PKGS=(
    intel-ucode
    mesa vulkan-intel intel-media-driver   # Intel graphics + video decoding
    sof-firmware                           # Intel laptop sound chips
    power-profiles-daemon                  # GNOME Power Mode / battery
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
  MACHINE_PKGS=(
    intel-ucode
    mesa vulkan-intel intel-media-driver   # Intel iGPU (drives the desktop in Hybrid mode)
    nvidia-open nvidia-utils nvidia-settings  # RTX 4070 driver (open kernel modules)
    nvidia-prime                           # "prime-run <app>" = run an app on the RTX 4070
    switcheroo-control                     # GNOME "Launch using Discrete Graphics Card"
    sof-firmware                           # Intel laptop sound
    power-profiles-daemon                  # GNOME Power Mode = Legion quiet/balanced/performance
  )
  MACHINE_SERVICES=(
    power-profiles-daemon switcheroo-control
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
    ' █████╗ ██████╗  ██████╗██╗  ██╗'
    '██╔══██╗██╔══██╗██╔════╝██║  ██║'
    '███████║██████╔╝██║     ███████║'
    '██╔══██║██╔══██╗██║     ██╔══██║'
    '██║  ██║██║  ██║╚██████╗██║  ██║'
    '╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝'
  )
  local colors=("$BL" "$BL" "$CY" "$CY" "$MG" "$MG")
  local side=(
    ""
    "${WH}COMPLETE INSTALL${C0}  ${DIM}v2.0${C0}"
    "${DIM}automated deployment system${C0}"
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
printf '  '; typeout "Initializing deployment core..."; printf '\n'; pause 0.2

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
  "Desktop  : GNOME / Wayland / dark mode / 100% scale"
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
note "Login password for '$USERNAME'."
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

do_fstab() {
  genfstab -U /mnt >> /mnt/etc/fstab
  sed -Ei 's/,?subvolid=[0-9]+//' /mnt/etc/fstab   # keeps snapshot rollbacks sane
}

do_configure() {
  declare -p USERNAME FULLNAME HOSTNAME TIMEZONE XKB_LAYOUT LANG_LOCALE \
             FORMAT_LOCALE KERNEL_PARAMS CRYPT_UUID SERVICES BOOT_TIMEOUT \
             MKINIT_HOOKS DOCK_LIST > /mnt/root/install.env

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

# Swedish keyboard for GDM (via systemd-localed; the "X11" path is just
# where localed stores the XKB layout, GNOME still runs on Wayland)
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
EndSection
EOF

# GNOME defaults for every user: Swedish keyboard, dark mode, pinned dock apps.
# (These are defaults — you can still change them in Settings.)
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
cat > /etc/dconf/db/local.d/00-keyboard <<EOF
[org/gnome/desktop/input-sources]
sources=[('xkb', '$XKB_LAYOUT')]
EOF
cat > /etc/dconf/db/local.d/01-look <<EOF
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'

[org/gnome/shell]
favorite-apps=[$DOCK_LIST]
EOF
dconf update

# 100% display scaling. GNOME picks the scale per monitor when it first sees
# it, so this small job runs at login and sets every screen to 100% with
# GNOME's own display tool (gdctl). It stops running once it has succeeded.
cat > /usr/local/bin/first-login-scale <<'SCALE'
#!/bin/bash
MARK="${XDG_CONFIG_HOME:-$HOME/.config}/.scale-100-done"
[[ -f "$MARK" ]] && exit 0
command -v gdctl >/dev/null || exit 0
sleep 4
out=$(gdctl show 2>/dev/null) || exit 0
mkdir -p "$(dirname "$MARK")"
# Already 100% everywhere? Then we're done.
if ! grep -qE 'Scale: *([2-9]|1\.[0-9]*[1-9])' <<< "$out"; then touch "$MARK"; exit 0; fi
mapfile -t mons < <(grep -oE 'Monitor [A-Za-z]+(-[A-Za-z0-9]+)+' <<< "$out" | awk '{print $2}' | awk '!seen[$0]++')
(( ${#mons[@]} )) || exit 0
args=(--logical-monitor --primary --monitor "${mons[0]}" --scale 1)
prev="${mons[0]}"
for m in "${mons[@]:1}"; do
  args+=(--logical-monitor --monitor "$m" --scale 1 --right-of "$prev")
  prev="$m"
done
gdctl set --persistent "${args[@]}" && touch "$MARK"
SCALE
chmod 755 /usr/local/bin/first-login-scale
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/first-login-scale.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Set display scale to 100%
Exec=/usr/local/bin/first-login-scale
NoDisplay=true
X-GNOME-Autostart-enabled=true
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

# User + sudo. Root gets NO password and is locked, so nobody can log in
# as root; admin tasks go through "sudo" with your own password.
useradd -m -G wheel -c "$FULLNAME" -s /bin/bash "$USERNAME"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
passwd -l root

# Faster pacman on the installed system too
sed -Ei 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

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
DOCK_LIST=$(printf "'%s', " "${DOCK_APPS[@]}"); DOCK_LIST="${DOCK_LIST%, }"
TOTAL=11
[[ "$ADD_WINDOWS" == "yes" ]] && TOTAL=12
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
run "Writing fstab"            do_fstab
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
  "Desktop  : GNOME / dark mode / 100% scale"
  "Duration : $ELAPSED"
  "Log      : /var/log/arch-install.log"
)
box "DEPLOYMENT COMPLETE" "${SUMMARY[@]}"

NEXT=(
  "1. Remove the USB stick when the screen goes black"
  "2. Type your encryption key at the boot prompt"
  "3. Log in as '$USERNAME'"
  "4. Connect Wi-Fi from the top-right menu"
)
if [[ "$FLATPAK_OK" == "no" || "$NVIDIA" == "yes" ]]; then
  NEXT+=("5. Apps finish installing in the background once online"
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
    "* Run an app on the RTX 4070: prime-run <app>," \
    "  or right-click it -> Launch using Discrete Graphics Card"
fi

echo
ask "Press ${GR}ENTER${C0} to reboot into your new system (Ctrl+C to stay): " _
printf '\n  %sSee you on the other side.%s\n\n' "$CY" "$C0"
sleep 1
reboot

#!/usr/bin/env bash
# =============================================================================
#  Automated Arch Linux installer — Samuel's laptop & desktop
#
#  Pick a machine at the start:
#    1) Laptop  — Intel CPU/GPU, screen-flicker fix, power profiles
#    2) Desktop — AMD Ryzen 7 5800X3D + Radeon RX 7800 XT, Lutris + Heroic,
#                 dual boot with Windows on a separate drive
#    3) Gaming laptop — Lenovo Legion 5, i7-13700HX + RTX 4070 (hybrid
#                 Intel/NVIDIA), NVIDIA driver, Lutris + Heroic
#
#  Then pick a desktop:  1) GNOME   2) KDE Plasma   (both on Wayland)
#
#  All get:
#    * The chosen disk wiped (GPT: 1 GiB EFI + rest LUKS2-encrypted)
#    * Btrfs inside LUKS with subvolumes (@, @home, @log, @pkg, @snapshots)
#    * systemd-boot + systemd-based initramfs (sd-encrypt)
#    * PipeWire audio, Bluetooth, Firefox
#    * Laptops: power-profiles-daemon (power modes + battery in GNOME and KDE)
#    * English GUI, Swedish keyboard/formats/timezone
#    * zram swap, NetworkManager, user "samuel" with sudo, root locked
#    * Flatpak + Flathub: Discord, VSCodium, Spotify, VLC, Steam, Bitwarden
#
#  Run from the official Arch ISO, booted in UEFI mode, with internet:
#      bash arch-install.sh
# =============================================================================
set -euo pipefail

# ----------------------------- Common settings -------------------------------
USERNAME="samuel"                 # Linux usernames should be lowercase
FULLNAME="Samuel"                 # Shown on the login screen
TIMEZONE="Europe/Stockholm"
KEYMAP="sv-latin1"                # Swedish keyboard: console + LUKS password prompt
XKB_LAYOUT="se"                   # Swedish keyboard: login screen + desktop
LANG_LOCALE="en_US.UTF-8"         # English menus/GUI
FORMAT_LOCALE="sv_SE.UTF-8"       # Swedish dates, 24h clock, numbers, currency, A4, metric

COMMON_PKGS=(
  # Base system
  base linux linux-firmware
  btrfs-progs cryptsetup dosfstools
  networkmanager sudo nano vim git base-devel man-db man-pages
  zram-generator xdg-user-dirs
  # Browser (desktop environment is chosen below)
  firefox
  # Audio: PipeWire (replaces PulseAudio + JACK)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  # Bluetooth (USB adapters like ASUS's use the built-in btusb driver;
  # their firmware ships in linux-firmware)
  bluez bluez-utils
  # Apps / fonts
  flatpak noto-fonts noto-fonts-emoji
)
COMMON_SERVICES=(NetworkManager bluetooth fstrim.timer systemd-timesyncd systemd-boot-update)

# ----------------------------- Desktop environments --------------------------
de_gnome() {
  DE="gnome"
  DE_NAME="GNOME"
  DE_PKGS=(gnome)                            # Includes GDM, Files, Software, etc.
  DE_SERVICES=(gdm)
}

de_kde() {
  DE="kde"
  DE_NAME="KDE Plasma"
  DE_PKGS=(
    plasma-meta                              # Plasma desktop, Discover, PowerDevil (power/battery), portals
    plasma-login-manager                     # KDE's login screen
    konsole dolphin kate ark spectacle gwenview okular kcalc filelight ffmpegthumbs
  )
  DE_SERVICES=(plasmalogin)
}
COMMON_FLATPAKS=(
  com.discordapp.Discord
  com.vscodium.codium
  com.spotify.Client
  org.videolan.VLC
  com.valvesoftware.Steam
  com.bitwarden.desktop
)

# ----------------------------- Machine profiles ------------------------------
profile_laptop() {
  MACHINE="laptop"
  DEFAULT_HOSTNAME="arch-laptop"
  MACHINE_PKGS=(
    intel-ucode
    mesa vulkan-intel intel-media-driver   # Intel graphics + video decoding
    sof-firmware                           # Intel laptop sound chips
    power-profiles-daemon                  # Power modes / battery (GNOME + KDE)
  )
  MACHINE_SERVICES=(power-profiles-daemon)
  MACHINE_FLATPAKS=()
  KERNEL_PARAMS="quiet i915.enable_psr=0"  # Fixes the screen flicker
  BOOT_TIMEOUT=3
  NVIDIA="no"
  MKINIT_HOOKS="base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck"
}

profile_gaming_laptop() {
  MACHINE="gaming-laptop"
  DEFAULT_HOSTNAME="arch-legion"
  MACHINE_PKGS=(
    intel-ucode
    mesa vulkan-intel intel-media-driver   # Intel iGPU (drives the desktop in Hybrid mode)
    nvidia-open nvidia-utils nvidia-settings  # RTX 4070 driver (open kernel modules)
    nvidia-prime                           # "prime-run <app>" = run an app on the RTX 4070
    switcheroo-control                     # "Run on discrete GPU" menu option (GNOME + KDE)
    sof-firmware                           # Intel laptop sound
    power-profiles-daemon                  # Power modes = Legion quiet/balanced/performance
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

profile_desktop() {
  MACHINE="desktop"
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

msg()  { printf '\n\e[1;32m==> %s\e[0m\n' "$*"; }
warn() { printf '\e[1;33m!!  %s\e[0m\n' "$*"; }
die()  { printf '\e[1;31mXX  %s\e[0m\n' "$*" >&2; exit 1; }

ask_password() {   # ask_password "Prompt" varname
  local prompt="$1" p1 p2
  local -n out="$2"
  while true; do
    read -rsp "$prompt: " p1; echo
    read -rsp "Confirm: " p2; echo
    if [[ -n "$p1" && "$p1" == "$p2" ]]; then out="$p1"; return; fi
    warn "Passwords were empty or didn't match — try again."
  done
}

ESP_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
MSR_GUID="e3c9e316-0b5c-4db8-817d-f92df00215ae"   # Microsoft Reserved partition

# ----------------------------- Pre-flight ------------------------------------
[[ $EUID -eq 0 ]] || die "Run as root (you are root by default on the Arch ISO)."
[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode. Enable UEFI (and disable CSM/Legacy) in the BIOS."
ping -c1 -W3 archlinux.org &>/dev/null || die "No internet. For Wi-Fi run: iwctl  (then: station wlan0 connect \"SSID\")"

loadkeys "$KEYMAP"   # So passwords typed now match the layout at boot
timedatectl set-ntp true

# Clean up leftovers if the script is re-run
umount -R /mnt 2>/dev/null || true
umount /tmp/winesp 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true

# ----------------------------- Questions -------------------------------------
msg "Which machine is this?"
echo "  1) Laptop        (Intel, flicker fix, battery/power profiles)"
echo "  2) Desktop       (Ryzen 7 5800X3D + RX 7800 XT, Lutris + Heroic, dual boot)"
echo "  3) Gaming laptop (Legion 5: i7-13700HX + RTX 4070, NVIDIA, Lutris + Heroic)"
while true; do
  read -rp "Choose [1/2/3]: " CHOICE
  case "$CHOICE" in
    1) profile_laptop;        break ;;
    2) profile_desktop;       break ;;
    3) profile_gaming_laptop; break ;;
    *) warn "Type 1, 2 or 3." ;;
  esac
done

msg "Which desktop?"
echo "  1) GNOME"
echo "  2) KDE Plasma"
while true; do
  read -rp "Choose [1/2]: " DE_CHOICE
  case "$DE_CHOICE" in
    1) de_gnome; break ;;
    2) de_kde;   break ;;
    *) warn "Type 1 or 2." ;;
  esac
done

PKGS=("${COMMON_PKGS[@]}" "${DE_PKGS[@]}" "${MACHINE_PKGS[@]}")
SERVICES=("${COMMON_SERVICES[@]}" "${DE_SERVICES[@]}" "${MACHINE_SERVICES[@]}")
FLATPAKS=("${COMMON_FLATPAKS[@]}" "${MACHINE_FLATPAKS[@]}")

msg "Available disks:"
lsblk -dpno NAME,SIZE,MODEL,TRAN -e 7,11
echo
read -rp "Disk to ERASE and install Arch on (e.g. /dev/nvme0n1): " DISK
[[ -b "$DISK" ]] || die "$DISK is not a block device."

ISO_DEV=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
if [[ -n "$ISO_DEV" && "$ISO_DEV" == "$DISK"* ]]; then
  die "$DISK is the USB stick you booted from. Pick an internal disk."
fi

# Windows safety check: refuse to silently wipe a Windows drive
CONFIRM_WORD="ERASE"
if lsblk -lno FSTYPE,PARTTYPE "$DISK" | grep -qiE "ntfs|bitlocker|$MSR_GUID"; then
  echo
  lsblk -po NAME,SIZE,FSTYPE,LABEL,MODEL "$DISK"
  warn "This disk looks like it has WINDOWS on it!"
  warn "For dual boot, Arch should go on the OTHER drive."
  CONFIRM_WORD="ERASE WINDOWS"
fi

echo
while true; do
  read -rp "Hostname (computer name) [$DEFAULT_HOSTNAME]: " HOSTNAME
  HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"
  HOSTNAME="${HOSTNAME,,}"   # lowercase
  [[ "$HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] && break
  warn "Use only letters, digits and dashes (no spaces, can't start/end with a dash)."
done

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
    echo
    msg "Found Windows boot files on $WIN_ESP"
    read -rp "Add Windows to the Arch boot menu? [Y/n]: " yn
    [[ "${yn,,}" == "n" ]] || ADD_WINDOWS="yes"
  else
    warn "No Windows install found on other drives — use the BIOS boot menu (F8 on ASUS) to reach Windows."
  fi
fi

DISK_BYTES=$(lsblk -bdno SIZE "$DISK")
DISK_GIB=$(( DISK_BYTES / 1024 / 1024 / 1024 ))
RAM_MIB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))
ZRAM_MIB=$(( RAM_MIB / 2 < 8192 ? RAM_MIB / 2 : 8192 ))

echo
msg "Install plan"
cat <<EOF
  Machine:     $MACHINE
  Desktop:     $DE_NAME (Wayland)
  Disk:       $DISK  (~${DISK_GIB} GiB, the WHOLE disk is used)
    1) EFI     1 GiB  FAT32, mounted at /boot (bootloader + kernels)
    2) Root    ~$(( DISK_GIB - 1 )) GiB  LUKS2 encrypted -> Btrfs
               subvolumes @ (/), @home, @log, @pkg, @snapshots
               (they share all the space, no fixed sizes)
  Swap:        zram in RAM, ~$(( ZRAM_MIB / 1024 )) GiB (no swap partition)
  Hostname:    $HOSTNAME
  User:        $USERNAME (sudo), root login disabled
  Language:    English GUI, Swedish keyboard/formats, $TIMEZONE
  Kernel opts: $KERNEL_PARAMS
  Flatpaks:    ${FLATPAKS[*]}
EOF
[[ "$MACHINE" == "desktop" ]] && echo "  Windows:     $( [[ $ADD_WINDOWS == yes ]] && echo "added to boot menu (from $WIN_ESP, read-only)" || echo "not in boot menu")"
echo
lsblk "$DISK"
warn "EVERYTHING on $DISK will be destroyed."
read -rp "Type $CONFIRM_WORD to continue: " CONFIRM
[[ "$CONFIRM" == "$CONFIRM_WORD" ]] || die "Aborted."

echo
msg "Disk encryption password (you type this at every boot)"
ask_password "LUKS password" LUKS_PASS
msg "Password for user '$USERNAME'"
ask_password "User password" USER_PASS

# Log everything from here on (passwords are never echoed)
exec > >(tee -a /tmp/arch-install.log) 2>&1

if [[ "$DISK" =~ [0-9]$ ]]; then PART="${DISK}p"; else PART="$DISK"; fi
ESP="${PART}1"
CRYPT="${PART}2"

# ----------------------------- Partitioning ----------------------------------
msg "Wiping and partitioning $DISK"
for p in $(lsblk -lnpo NAME "$DISK" | tail -n +2); do wipefs -af "$p" || true; done
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:EFI \
       -n2:0:0   -t2:8309 -c2:cryptroot "$DISK"
partprobe "$DISK"
udevadm settle

msg "Formatting EFI partition"
mkfs.fat -F32 -n EFI "$ESP"

msg "Setting up LUKS2 encryption"
printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$CRYPT"
printf '%s' "$LUKS_PASS" | cryptsetup open --allow-discards --key-file=- "$CRYPT" cryptroot
unset LUKS_PASS
CRYPT_UUID=$(blkid -s UUID -o value "$CRYPT")

# ----------------------------- Btrfs -----------------------------------------
msg "Creating Btrfs filesystem and subvolumes"
mkfs.btrfs -f -L arch /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
for sv in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt

BTRFS_OPTS="noatime,compress=zstd"
mount -o "$BTRFS_OPTS,subvol=@" /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
mount -o "$BTRFS_OPTS,subvol=@home"      /dev/mapper/cryptroot /mnt/home
mount -o "$BTRFS_OPTS,subvol=@log"       /dev/mapper/cryptroot /mnt/var/log
mount -o "$BTRFS_OPTS,subvol=@pkg"       /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o "$BTRFS_OPTS,subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
mount -o fmask=0077,dmask=0077 "$ESP" /mnt/boot

# ----------------------------- Base install ----------------------------------
msg "Installing packages (this takes a while)"
sed -Ei 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacman -Sy --noconfirm archlinux-keyring

mkdir -p /mnt/etc
printf 'KEYMAP=%s\nXKBLAYOUT=%s\n' "$KEYMAP" "$XKB_LAYOUT" > /mnt/etc/vconsole.conf
pacstrap -K /mnt "${PKGS[@]}"

msg "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab
sed -Ei 's/,?subvolid=[0-9]+//' /mnt/etc/fstab   # keeps snapshot rollbacks sane

# ----------------------------- Configure system ------------------------------
msg "Configuring the new system"
declare -p USERNAME FULLNAME HOSTNAME TIMEZONE XKB_LAYOUT LANG_LOCALE \
           FORMAT_LOCALE KERNEL_PARAMS CRYPT_UUID SERVICES BOOT_TIMEOUT \
           MKINIT_HOOKS DE > /mnt/root/install.env

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

# Swedish keyboard for the login screen (GDM / Plasma Login read it via
# systemd-localed; the "X11" path is just where localed stores the XKB
# layout, everything still runs on Wayland)
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
EndSection
EOF

# Swedish keyboard as the default inside the desktop session too
if [[ "$DE" == "gnome" ]]; then
  mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
  printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
  cat > /etc/dconf/db/local.d/00-keyboard <<EOF
[org/gnome/desktop/input-sources]
sources=[('xkb', '$XKB_LAYOUT')]
EOF
  dconf update
else
  mkdir -p /etc/xdg
  cat > /etc/xdg/kxkbrc <<EOF
[Layout]
LayoutList=$XKB_LAYOUT
Use=true
EOF
fi

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
printf '%s:%s\n' "$USERNAME" "$USER_PASS" | arch-chroot /mnt chpasswd
unset USER_PASS
rm -f /mnt/root/setup.sh /mnt/root/install.env

# ----------------------------- Windows boot entry (desktop) ------------------
if [[ "$ADD_WINDOWS" == "yes" ]]; then
  msg "Adding Windows to the boot menu"
  # systemd-boot only sees its own EFI partition, so copy Windows' boot
  # manager there; it shows up automatically as "Windows Boot Manager".
  # The Windows drive is only mounted read-only — nothing on it is changed.
  if mount -o ro "$WIN_ESP" /tmp/winesp; then
    mkdir -p /mnt/boot/EFI
    cp -r /tmp/winesp/EFI/Microsoft /mnt/boot/EFI/ || warn "Copying Windows boot files failed — use the BIOS boot menu instead."
    umount /tmp/winesp
  else
    warn "Couldn't mount $WIN_ESP — use the BIOS boot menu (F8 on ASUS) for Windows."
  fi
fi

# ----------------------------- Flatpaks --------------------------------------
msg "Installing Flatpak apps from Flathub (Steam is big — be patient)"
FLATHUB="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATPAK_OK="no"
if arch-chroot /mnt flatpak remote-add --if-not-exists flathub "$FLATHUB" &&
   arch-chroot /mnt flatpak install -y --noninteractive --system flathub "${FLATPAKS[@]}"; then
  FLATPAK_OK="yes"
  msg "Flatpak apps installed"
else
  warn "Flatpak install inside the installer failed — they'll install on first boot once you're online."
fi

# A first-boot job is needed if the install above failed, or on NVIDIA:
# Flatpak apps (Steam!) need an NVIDIA add-on matching the driver, and Flatpak
# can only detect the driver once the real system has booted.
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

# ----------------------------- Done ------------------------------------------
cp /tmp/arch-install.log /mnt/var/log/arch-install.log 2>/dev/null || true
sync
umount -R /mnt
cryptsetup close cryptroot

msg "All done! Remove the USB stick and run: reboot"
echo "    At boot: type your disk password, then log in as '$USERNAME'."
if [[ "$DE" == "gnome" ]]; then
  echo "    Wi-Fi: connect from the top-right menu after logging in."
else
  echo "    Wi-Fi: connect from the network icon in the bottom-right panel."
fi
if [[ "$MACHINE" == "desktop" ]]; then
  echo
  echo "    Dual boot tips:"
  echo "    * In the BIOS, put 'Linux Boot Manager' first in the boot order."
  echo "    * Fix Windows showing the wrong time: in Windows, run as admin:"
  echo '      reg add "HKLM\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f'
fi
if [[ "$NVIDIA" == "yes" ]]; then
  echo
  echo "    NVIDIA tips:"
  echo "    * Connect to the internet after first login: a background job adds the"
  echo "      NVIDIA support Steam/Lutris/Heroic need (check: journalctl -fu flatpak-firstboot)."
  echo "    * Check the driver works: nvidia-smi"
  echo "    * Run a normal app on the RTX 4070: prime-run <app>, or right-click it in"
  echo "      the app menu -> 'Launch using Discrete Graphics Card' / 'Run using dedicated graphics card'."
fi

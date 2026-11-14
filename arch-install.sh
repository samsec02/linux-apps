#!/usr/bin/env bash
# =============================================================================
#  Automated Arch Linux installer — Samuel's laptop
#
#  What it does:
#    * Wipes the disk you pick (GPT: 1 GiB EFI + rest LUKS2-encrypted)
#    * Btrfs inside LUKS with subvolumes (@, @home, @log, @pkg, @snapshots)
#    * systemd-boot + systemd-based initramfs (sd-encrypt)
#    * Kernel param i915.enable_psr=0 (fixes the screen flicker)
#    * GNOME + GDM on Wayland, PipeWire audio, Bluetooth, power-profiles-daemon
#    * English GUI, Swedish keyboard/formats/timezone
#    * zram swap, NetworkManager, user "samuel" with sudo, root locked
#    * Flatpak + Flathub: Discord, VSCodium, Spotify, VLC, Steam, Bitwarden
#    * Asks you for: disk, hostname, disk password, user password
#
#  Run from the official Arch ISO, booted in UEFI mode, with internet:
#      bash arch-install.sh
# =============================================================================
set -euo pipefail

# ----------------------------- Settings --------------------------------------
USERNAME="samuel"                 # Linux usernames should be lowercase
FULLNAME="Samuel"                 # Shown on the GDM login screen
DEFAULT_HOSTNAME="arch-laptop"    # You're asked for a hostname; Enter = this
TIMEZONE="Europe/Stockholm"
KEYMAP="sv-latin1"                # Swedish keyboard: console + LUKS password prompt
XKB_LAYOUT="se"                   # Swedish keyboard: GDM + GNOME (Wayland)
LANG_LOCALE="en_US.UTF-8"         # English menus/GUI
FORMAT_LOCALE="sv_SE.UTF-8"       # Swedish dates, 24h clock, numbers, currency, A4, metric
KERNEL_PARAMS="quiet i915.enable_psr=0"
FLATPAKS=(
  com.discordapp.Discord
  com.vscodium.codium
  com.spotify.Client
  org.videolan.VLC
  com.valvesoftware.Steam
  com.bitwarden.desktop
)
PKGS=(
  # Base system
  base linux linux-firmware intel-ucode sof-firmware
  btrfs-progs cryptsetup dosfstools
  networkmanager sudo nano vim git base-devel man-db man-pages
  zram-generator xdg-user-dirs
  # Desktop
  gnome
  # Audio: PipeWire (replaces PulseAudio + JACK)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  # Bluetooth
  bluez bluez-utils
  # Intel graphics + video decoding
  mesa vulkan-intel intel-media-driver
  # Laptop power modes (the Power Mode toggle in GNOME)
  power-profiles-daemon
  # Apps / fonts
  flatpak noto-fonts noto-fonts-emoji
)
# -----------------------------------------------------------------------------

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

# ----------------------------- Pre-flight ------------------------------------
[[ $EUID -eq 0 ]] || die "Run as root (you are root by default on the Arch ISO)."
[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode. Enable UEFI (and disable CSM/Legacy) in the BIOS."
ping -c1 -W3 archlinux.org &>/dev/null || die "No internet. For Wi-Fi run: iwctl  (then: station wlan0 connect \"SSID\")"

loadkeys "$KEYMAP"   # So passwords typed now match the layout at boot
timedatectl set-ntp true

# Clean up leftovers if the script is re-run
umount -R /mnt 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true

# ----------------------------- Questions -------------------------------------
msg "Available disks:"
lsblk -dpno NAME,SIZE,MODEL -e 7,11
echo
read -rp "Disk to ERASE and install to (e.g. /dev/nvme0n1): " DISK
[[ -b "$DISK" ]] || die "$DISK is not a block device."

ISO_DEV=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
if [[ -n "$ISO_DEV" && "$ISO_DEV" == "$DISK"* ]]; then
  die "$DISK is the USB stick you booted from. Pick the laptop's internal disk."
fi

echo
while true; do
  read -rp "Hostname (computer name) [$DEFAULT_HOSTNAME]: " HOSTNAME
  HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"
  HOSTNAME="${HOSTNAME,,}"   # lowercase
  [[ "$HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] && break
  warn "Use only letters, digits and dashes (no spaces, can't start/end with a dash)."
done

DISK_BYTES=$(lsblk -bdno SIZE "$DISK")
DISK_GIB=$(( DISK_BYTES / 1024 / 1024 / 1024 ))
RAM_MIB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))
ZRAM_MIB=$(( RAM_MIB / 2 < 8192 ? RAM_MIB / 2 : 8192 ))

echo
msg "Install plan"
cat <<EOF
  Disk:        $DISK  (~${DISK_GIB} GiB, the WHOLE disk is used)
    1) EFI     1 GiB  FAT32, mounted at /boot (bootloader + kernels)
    2) Root    ~$(( DISK_GIB - 1 )) GiB  LUKS2 encrypted -> Btrfs
               subvolumes @ (/), @home, @log, @pkg, @snapshots
               (they share all the space, no fixed sizes)
  Swap:        zram in RAM, ~$(( ZRAM_MIB / 1024 )) GiB (no swap partition)
  Hostname:    $HOSTNAME
  User:        $USERNAME (sudo), root login disabled
  Language:    English GUI, Swedish keyboard/formats, $TIMEZONE
EOF
echo
lsblk "$DISK"
warn "EVERYTHING on $DISK will be destroyed."
read -rp "Type ERASE to continue: " CONFIRM
[[ "$CONFIRM" == "ERASE" ]] || die "Aborted."

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
           FORMAT_LOCALE KERNEL_PARAMS CRYPT_UUID > /mnt/root/install.env

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

# Swedish keyboard as the default inside your GNOME session too
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
cat > /etc/dconf/db/local.d/00-keyboard <<EOF
[org/gnome/desktop/input-sources]
sources=[('xkb', '$XKB_LAYOUT')]
EOF
dconf update

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# systemd-based initramfs with encryption
sed -Ei 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# systemd-boot
bootctl install
cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
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

# Services
systemctl enable NetworkManager gdm bluetooth power-profiles-daemon \
                 fstrim.timer systemd-timesyncd systemd-boot-update
CHROOT

arch-chroot /mnt bash /root/setup.sh
printf '%s:%s\n' "$USERNAME" "$USER_PASS" | arch-chroot /mnt chpasswd
unset USER_PASS
rm -f /mnt/root/setup.sh /mnt/root/install.env

# ----------------------------- Flatpaks --------------------------------------
msg "Installing Flatpak apps from Flathub (Steam is big — be patient)"
FLATHUB="https://dl.flathub.org/repo/flathub.flatpakrepo"
if arch-chroot /mnt flatpak remote-add --if-not-exists flathub "$FLATHUB" &&
   arch-chroot /mnt flatpak install -y --noninteractive --system flathub "${FLATPAKS[@]}"; then
  msg "Flatpak apps installed"
else
  warn "Flatpak install inside the installer failed — setting it up to run on first boot instead."
  cat > /mnt/etc/systemd/system/flatpak-firstboot.service <<EOF
[Unit]
Description=Install Flatpak apps on first boot
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/var/lib/flatpak-firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak remote-add --if-not-exists flathub $FLATHUB
ExecStart=/usr/bin/flatpak install -y --noninteractive --system flathub ${FLATPAKS[*]}
ExecStartPost=/usr/bin/touch /var/lib/flatpak-firstboot.done
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
echo "    At boot: type your disk password, then log in as '$USERNAME' in GDM."
echo "    Wi-Fi: connect from the GNOME top-right menu after logging in."

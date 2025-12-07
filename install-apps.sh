#!/bin/bash

# It assumes Flatpak is already installed and Flathub is configured.
# Be aware that -y accepts everything promted and is not recommended, however for the sake of this script we do it anyways because it downloads known applications. 
echo "Starting simplified Fedora application installation script..."

echo "Installing Flatpak applications..."

flatpak install flathub com.bitwarden.desktop -y || echo "ERROR: Failed to install com.Bitwarden.desktop"
flatpak install flathub com.discordapp.Discord -y || echo "ERROR: Failed to install com.discordapp.Discord"
flatpak install flathub org.qbittorrent.qBittorrent -y || echo "ERROR: Failed to install org.qbittorrent.qBittorrent"
flatpak install flathub com.valvesoftware.Steam -y || echo "ERROR: Failed to install com.valvesoftware.Steam"
flatpak install flathub net.lutris.Lutris -y || echo "ERROR: Failed to install net.lutris.Lutris"
flatpak install flathub com.spotify.Client -y || echo "ERROR: Failed to install com.spotify.Client"
flatpak install flathub com.vscodium.codium -y || echo "ERROR: Failed to install com.vscodium.codium"
flatpak install flathub net.cozic.joplin_desktop -y || echo "ERROR: Failed to install net.cozic.joplin_desktop"
flatpak install flathub org.videolan.VLC -y || echo "ERROR: Failed to install org.videolan.VLC"
flatpak install flathub io.freetubeapp.FreeTube -y || echo "ERROR: Failed to install io.freetubeapp.FreeTube"
flatpak install flathub org.signal.Signal -y || echo "ERROR: Failed to install org.signal.Signal"
flatpak install flathub net.codelogistics.webapps -y || echo "ERROR: Failed to install net.codelogistics.webapps"
flatpak install flathub com.brave.Browser -y || echo "ERROR: Failed to install com.brave.Browser"
flatpak install flathub com.obsproject.Studio -y || echo "ERROR: Failed to install com.obsproject.Studio"
flatpak install flathub io.missioncenter.MissionCenter -y || echo "ERROR: Failed to install io.missioncenter.MissionCenter"
flatpak install flathub org.localsend.localsend_app -y || echo "ERROR: Failed to install localsend.localsend_app"

echo "Flatpaks installed"

echo "Script finished. Please review the output for any errors."
echo "You might need to reboot or log out/in for some changes to take effect."

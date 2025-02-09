#!/bin/bash

defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write -g InitialKeyRepeat -int 9
defaults write -g KeyRepeat -int 1

source "./_dock_utils.sh"
defaults write com.apple.Dock autohide -bool true
defaults write com.apple.dock tilesize -int 32;
defaults write com.apple.dock largesize -integer 40
defaults write com.apple.dock orientation left
clear_dock
disable_recent_apps_from_dock
killall Dock

brew install \
    google-chrome \
    firefox \
    discord \
    1password \
    orbstack \
    visual-studio-code \
    keepassxc \
    rectangle \
    lazygit \
    gpg \
    mpv \
    pv \
    ffmpeg \
    yt-dlp \
    ripgrep \
    font-jetbrains-mono-nerd-font
curl -fsSL https://get.pnpm.io/install.sh | sh -
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

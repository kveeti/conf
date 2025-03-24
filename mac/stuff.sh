#!/bin/bash

defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write -g InitialKeyRepeat -int 9
defaults write -g KeyRepeat -int 1

source "./_dock_utils.sh"
defaults write com.apple.Dock autohide -bool true
defaults write com.apple.dock tilesize -int 32;
defaults write com.apple.dock largesize -integer 40
defaults write com.apple.dock orientation left
defaults write com.apple.dock magnification -bool true
clear_dock
disable_recent_apps_from_dock
killall Dock

brew install \
    lazygit \
    gpg \
    mpv \
    pv \
    ffmpeg \
    yt-dlp \
    ripgrep \
    font-jetbrains-mono-nerd-font \
    colima \
    docker \
    docker-compose \
    docker-buildx \
    docker-credential-helper \
    neovim

brew install --cask \
    librewolf \
    keepassxc \
    rectangle \
    ghostty \
    bitwarden


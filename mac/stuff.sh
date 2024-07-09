#!/bin/bash

brew install google-chrome firefox orbstack neovim ripgrep tmux alacritty keepassxc linearmouse rectangle font-jetbrains-mono-nerd-font

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
curl -fsSL https://get.pnpm.io/install.sh | sh -

defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write -g InitialKeyRepeat -int 10
defaults write -g KeyRepeat -int 1

source "./_dock_utils.sh"
defaults read com.apple.Dock autohide
defaults write com.apple.dock tilesize -int 32;
defaults write com.apple.dock largesize -integer 40
defaults write com.apple.dock orientation left
clear_dock
disable_recent_apps_from_dock
killall Dock


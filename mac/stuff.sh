#!/bin/bash

# brew
brew install google-chrome neovim tmux alacritty keepassxc linearmouse rectangle fnm podman font-jetbrains-mono-nerd-font ripgrep

# rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# -- key repeat --

# enable key repeat globally
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# key repeat rate and delay until repeat
defaults write -g InitialKeyRepeat -int 10
defaults write -g KeyRepeat -int 1

# -- key repeat --

# -- dock --
source "./dock.sh"

# enable auto hide
defaults read com.apple.Dock autohide

# change size
defaults write com.apple.dock tilesize -int 32;

# magnification
defaults write com.apple.dock largesize -integer 40

# position
defaults write com.apple.dock orientation left

clear_dock
disable_recent_apps_from_dock

# declare -a apps=(
#     '/System/Applications/Utilities/Terminal.app'
#     '/Applications/Google Chrome.app'
#     '/System/Applications/System Preferences.app'
# );
#
# declare -a folders=(
#     ~/Downloads
# );
#
# for app in "${apps[@]}"; do
#
#     add_app_to_dock "$app"
# done
#
# for folder in "${folders[@]}"; do
#     add_folder_to_dock $folder
# done

killall Dock

# -- dock --

#!/bin/zsh

HOSTNAME='r'

# Login window settings
sudo defaults write /Library/Preferences/com.apple.loginwindow DisableConsoleAccess -bool true
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false

# Finder settings
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder AppleShowAllExtensions -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder FXRemoveOldTrashItems -bool true
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -bool false
defaults write com.apple.finder NewWindowTarget -string "Home"
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
defaults write com.apple.finder ShowStatusBar -bool true

# Dock settings
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock orientation -string "left"
defaults write com.apple.dock mouse-over-hilite-stack -bool true
defaults write com.apple.dock magnification -bool false
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock tilesize -int 16
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
defaults write com.apple.dock expose-animation-duration -float 0.1
defaults delete com.apple.dock persistent-apps
defaults delete com.apple.dock persistent-others

# Hot corners
defaults write com.apple.dock wvous-bl-corner -int 1 # 1 = Disabled
defaults write com.apple.dock wvous-br-corner -int 1
defaults write com.apple.dock wvous-tr-corner -int 1
defaults write com.apple.dock wvous-tl-corner -int 1

# Menubar
defaults write ~/Library/Preferences/ByHost/com.apple.controlcenter Bluetooth -int 18 # 18 = Enabled
defaults write ~/Library/Preferences/ByHost/com.apple.controlcenter WiFi -int 18
defaults write ~/Library/Preferences/ByHost/com.apple.controlcenter BatteryShowPercentage -int 1 # 1 = Enabled
defaults write NSGlobalDomain _HIHideMenuBar -bool true

# Keyboard
defaults write com.apple.HIToolbox AppleShowInputMenu -bool false
defaults write com.apple.HIToolbox "com.apple.keyboard.remap.capslock" -int 2
sudo hidutil property --set '{ "UserKeyMapping": [{ "HIDKeyboardModifierMappingSrc": 30064771129, "HIDKeyboardModifierMappingDst": 30064771296 }] }' # Remap Caps -> CTRL
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticInlinePredictionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true # CMD + CTRL drag
defaults write NSGlobalDomain "com.apple.keyboard.fnState" -bool false
defaults write NSGlobalDomain "com.apple.trackpad.scaling" -float 3 # 0.5 - 3

defaults write com.brave.Browser NSUserKeyEquivalents -dict-remove "Save Page As..."
defaults write com.brave.Browser NSUserKeyEquivalents -dict-add "Save Page As..." "@~^\$s"

# Global settings
defaults write NSGlobalDomain AppleShowAllFiles -bool true
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain "com.apple.springing.enabled" -bool true
defaults write NSGlobalDomain "com.apple.springing.delay" -float 0.0
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
defaults write NSGlobalDomain AppleScrollerPagingBehavior -bool true
defaults write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"
defaults write NSGlobalDomain AppleEnableMouseSwipeNavigateWithScrolls -bool true
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool true
defaults write NSGlobalDomain AppleWindowTabbingMode -string "always"
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
defaults write NSGlobalDomain NSScrollAnimationEnabled -bool true
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
defaults write NSGlobalDomain AppleMeasurementUnits -string "Centimeters"
defaults write NSGlobalDomain AppleMetricUnits -int 1
defaults write NSGlobalDomain AppleTemperatureUnit -string "Celsius"
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

# Custom System Preferences for AdLib
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
defaults write com.apple.AdLib allowIdentifierForAdvertising -bool false
defaults write com.apple.AdLib forceLimitAdTracking -bool true
defaults write com.apple.AdLib personalizedAdsMigrated -bool false

sudo defaults write /Library/Preferences/com.apple.loginwindow "ShowFullName" -bool true
sudo defaults write /Library/Preferences/com.apple.loginwindow "HideFastUserSwitch" -bool false
	
# Mute startup chime
sudo nvram StartupMute=%01

# Hostname
sudo scutil --set HostName "${HOSTNAME}"
sudo scutil --set ComputerName "${HOSTNAME}"
sudo scutil --set LocalHostName "${HOSTNAME}"

# Launch Services settings
defaults write com.apple.LaunchServices LSQuarantine -bool false

# Touch id sudo
sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
echo "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local > /dev/null

killall Finder
killall Dock


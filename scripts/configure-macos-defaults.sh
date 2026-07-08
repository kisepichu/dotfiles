#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: this script is intended for macOS" >&2
  exit 1
fi

defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain AppleShowScrollBars -string Always
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder FXDefaultSearchScope -string SCcf
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock show-recents -bool false

defaults write com.apple.screencapture location -string "$HOME/Desktop"

# Free up some Ctrl-based combos so they reach the terminal instead of being
# swallowed by macOS system shortcuts:
#   * 79 / 81: Mission Control "Move left/right a space" (Ctrl+Left / Ctrl+Right)
#              -> needed for tmux pane swap (prefix C-f then C-Arrow).
#              80/82 (the Shift variants) are left untouched.
#   * 156: Ctrl+Shift+Space -> needed for WezTerm QuickSelect (copy link/URL).
for hotkey in 79 81 156; do
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$hotkey" "{ enabled = 0; }"
done

if defaults read com.apple.AppleMultitouchTrackpad >/dev/null 2>&1; then
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
fi

for app in Finder Dock SystemUIServer cfprefsd; do
  killall "$app" >/dev/null 2>&1 || true
done

# Reload symbolic hotkeys so the Mission Control changes apply without logout.
activate_settings="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
if [ -x "$activate_settings" ]; then
  "$activate_settings" -u >/dev/null 2>&1 || true
fi

echo "macOS defaults configured. Some settings may require logout or restart."

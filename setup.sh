#!/bin/bash
set -e
echo "Installing XcodeGen..."
brew install xcodegen 2>/dev/null || echo "xcodegen already installed"
echo "Generating Xcode project..."
cd "$(dirname "$0")"
xcodegen generate
echo "Done! Open PetTalk.xcodeproj in Xcode."

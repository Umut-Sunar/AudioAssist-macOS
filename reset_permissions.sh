#!/bin/bash

echo "🔄 Resetting AudioAssist permissions..."

# App bundle ID
BUNDLE_ID="com.dogan.audioassist"

echo "📱 Bundle ID: $BUNDLE_ID"

# Kill the app if running
echo "🔪 Killing AudioAssist if running..."
pkill -f "AudioAssist" || echo "App not running"

# Reset TCC permissions (requires password)
echo "🔒 Resetting TCC permissions (requires sudo)..."
sudo tccutil reset ScreenCapture $BUNDLE_ID
sudo tccutil reset Microphone $BUNDLE_ID  
sudo tccutil reset Camera $BUNDLE_ID

# Clear app caches
echo "🗑️  Clearing app caches..."
rm -rf ~/Library/Caches/$BUNDLE_ID
rm -rf ~/Library/Saved\ Application\ State/$BUNDLE_ID.savedState/
rm -rf ~/Library/Preferences/$BUNDLE_ID.plist

# Clear Xcode DerivedData
echo "🗑️  Clearing Xcode DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/AudioAssist-*

echo "✅ Permission reset complete!"
echo "📝 Next steps:"
echo "   1. Build and run the app from Xcode"
echo "   2. Click 'Request Permission' button"
echo "   3. Check System Preferences → Security & Privacy → Screen Recording"
echo "   4. Look for 'AudioAssist' in the list"
echo "   5. Enable the permission"

# Open System Preferences to Screen Recording
echo "🔧 Opening System Preferences..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

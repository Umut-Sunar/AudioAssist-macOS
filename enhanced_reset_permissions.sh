#!/bin/bash

echo "🔄 ENHANCED AudioAssist Permission Reset..."
echo "🚨 This will completely reset ALL privacy permissions for AudioAssist"
echo "⚠️  You will need to grant permissions again after this reset"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled"
    exit 1
fi

# App bundle ID
BUNDLE_ID="com.dogan.audioassist"
APP_NAME="AudioAssist"

echo "📱 Bundle ID: $BUNDLE_ID"
echo "📱 App Name: $APP_NAME"
echo ""

# Kill the app if running
echo "🔪 Step 1: Killing $APP_NAME if running..."
pkill -f "$APP_NAME" || echo "✅ App not running"
sleep 1

echo ""
echo "🔒 Step 2: Comprehensive TCC Permission Reset (requires sudo)..."
echo "This will reset ALL privacy permissions for $BUNDLE_ID"

# Reset all possible TCC permissions
sudo tccutil reset All $BUNDLE_ID 2>/dev/null || echo "⚠️  Bundle-specific reset failed (expected for debug builds)"

# Reset system-wide permissions (more aggressive)
echo "🔒 Resetting system-wide permissions..."
sudo tccutil reset ScreenCapture 2>/dev/null || echo "⚠️  System ScreenCapture reset failed"
sudo tccutil reset Microphone 2>/dev/null || echo "⚠️  System Microphone reset failed"  
sudo tccutil reset Camera 2>/dev/null || echo "⚠️  System Camera reset failed"

# Force refresh permission daemon
echo "🔄 Forcing TCC daemon refresh..."
sudo killall tccd 2>/dev/null || echo "⚠️  tccd not running"
sudo launchctl stop com.apple.tccd 2>/dev/null || echo "⚠️  tccd service stop failed"
sudo launchctl start com.apple.tccd 2>/dev/null || echo "⚠️  tccd service start failed"

# Clear preference caches
echo "🗑️  Clearing preference caches..."
killall cfprefsd 2>/dev/null || echo "⚠️  cfprefsd not running"

echo ""
echo "🗑️  Step 3: Clearing app caches and states..."
rm -rf ~/Library/Caches/$BUNDLE_ID 2>/dev/null || echo "⚠️  No cache to clear"
rm -rf ~/Library/Saved\ Application\ State/$BUNDLE_ID.savedState/ 2>/dev/null || echo "⚠️  No saved state to clear"
rm -rf ~/Library/Preferences/$BUNDLE_ID.plist 2>/dev/null || echo "⚠️  No preferences to clear"

echo ""
echo "🗑️  Step 4: Clearing Xcode DerivedData (Debug build paths)..."
DERIVED_DATA_PATTERN="~/Library/Developer/Xcode/DerivedData/AudioAssist-*"
if ls ~/Library/Developer/Xcode/DerivedData/AudioAssist-* 1> /dev/null 2>&1; then
    rm -rf ~/Library/Developer/Xcode/DerivedData/AudioAssist-*
    echo "✅ Cleared DerivedData"
else
    echo "⚠️  No DerivedData found"
fi

echo ""
echo "🔧 Step 5: Force-refreshing system permission cache..."
# Force macOS to refresh its permission cache
sudo dscacheutil -flushcache 2>/dev/null || echo "⚠️  Cache flush failed"

echo ""
echo "✅ ENHANCED PERMISSION RESET COMPLETE!"
echo ""
echo "🚨 CRITICAL NEXT STEPS:"
echo "📝 Next steps:"
echo "   1. ⚠️  RESTART YOUR MAC (recommended for complete TCC reset)"
echo "      OR at minimum: log out and log back in"
echo ""
echo "   2. 🏗️  In Xcode: Product → Clean Build Folder"
echo "   3. 🏗️  Restart Xcode completely"
echo "   4. 🏗️  Build and run the app from Xcode"
echo ""
echo "   5. 🔒 When permission dialog appears:"
echo "      - Click 'Request Permission' in app"
echo "      - OR manually grant in System Settings"
echo ""
echo "   6. 📱 Verify in System Settings:"
echo "      → Privacy & Security → Screen Recording"
echo "      → Look for '$APP_NAME' entry"
echo "      → Ensure it's ENABLED (checkbox checked)"
echo ""
echo "🎯 ALTERNATIVE SOLUTION (Recommended):"
echo "   → Create an Archive build instead of Debug"
echo "   → Product → Archive → Distribute App → Copy App"
echo "   → Archive builds have stable paths and better permission handling"
echo ""

# Ask if user wants to open System Settings
read -p "Open System Settings → Screen Recording now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔧 Opening System Settings..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null || \
    open "x-apple.systempreferences:com.apple.preference.security" 2>/dev/null || \
    echo "⚠️  Could not open System Settings automatically"
else
    echo "ℹ️  You can manually open: System Settings → Privacy & Security → Screen Recording"
fi

echo ""
echo "🎉 Script completed! Follow the next steps above."

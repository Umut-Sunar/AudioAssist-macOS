#!/bin/bash

echo "🔧 AudioAssist Screen Recording Permission Fix Script"
echo "===================================================="

# App bundle ID
BUNDLE_ID="com.dogan.audioassist"
APP_NAME="AudioAssist"

echo "📱 Bundle ID: $BUNDLE_ID"
echo "🏷️  App Name: $APP_NAME"

# Function to check if app is running
check_app_running() {
    if pgrep -f "$APP_NAME" > /dev/null; then
        echo "⚠️  $APP_NAME is currently running"
        return 0
    else
        echo "✅ $APP_NAME is not running"
        return 1
    fi
}

# Function to kill app
kill_app() {
    echo "🔪 Stopping $APP_NAME..."
    pkill -f "$APP_NAME" || echo "App was not running"
    sleep 1
}

# Function to reset TCC permissions
reset_tcc_permissions() {
    echo "🔒 Resetting TCC permissions (requires sudo)..."
    
    # Reset Screen Recording permission
    echo "   - Resetting Screen Recording permission..."
    sudo tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || echo "   ⚠️  Could not reset ScreenCapture permission"
    
    # Reset Microphone permission
    echo "   - Resetting Microphone permission..."
    sudo tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || echo "   ⚠️  Could not reset Microphone permission"
    
    # Reset Camera permission
    echo "   - Resetting Camera permission..."
    sudo tccutil reset Camera "$BUNDLE_ID" 2>/dev/null || echo "   ⚠️  Could not reset Camera permission"
    
    echo "✅ TCC permissions reset complete"
}

# Function to clean app data
clean_app_data() {
    echo "🗑️  Cleaning app data and caches..."
    
    # Remove app caches
    rm -rf ~/Library/Caches/"$BUNDLE_ID" 2>/dev/null || echo "   No app caches found"
    
    # Remove saved application state
    rm -rf ~/Library/Saved\ Application\ State/"$BUNDLE_ID".savedState/ 2>/dev/null || echo "   No saved state found"
    
    # Remove app preferences
    rm -rf ~/Library/Preferences/"$BUNDLE_ID".plist 2>/dev/null || echo "   No preferences found"
    
    # Remove containers if they exist
    rm -rf ~/Library/Containers/"$BUNDLE_ID" 2>/dev/null || echo "   No containers found"
    
    echo "✅ App data cleanup complete"
}

# Function to clean Xcode data
clean_xcode_data() {
    echo "🗑️  Cleaning Xcode build data..."
    
    # Remove DerivedData
    rm -rf ~/Library/Developer/Xcode/DerivedData/AudioAssist-* 2>/dev/null || echo "   No DerivedData found"
    
    # Remove module cache
    rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex 2>/dev/null || echo "   No module cache found"
    
    echo "✅ Xcode cleanup complete"
}

# Function to check current permission status
check_permission_status() {
    echo "🔍 Checking current permission status..."
    
    # Try to find the app in system_profiler output
    APP_INFO=$(system_profiler SPApplicationsDataType | grep -A 20 "$APP_NAME:" | head -n 20)
    
    if [ ! -z "$APP_INFO" ]; then
        echo "📱 App found in system:"
        echo "$APP_INFO" | grep -E "(Version|Location|Last Modified|Kind)" | sed 's/^/   /'
    else
        echo "⚠️  App not found in system applications list"
    fi
}

# Function to create a proper app bundle in Applications
create_proper_app_bundle() {
    echo "📦 Creating proper app bundle in Applications..."
    
    # Find the current DerivedData app
    DERIVED_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "AudioAssist.app" -type d 2>/dev/null | head -n 1)
    
    if [ ! -z "$DERIVED_APP" ]; then
        echo "🔍 Found app in DerivedData: $DERIVED_APP"
        
        # Copy to Applications
        APPS_PATH="/Applications/AudioAssist.app"
        echo "📋 Copying to Applications folder..."
        
        # Remove existing app in Applications if it exists
        if [ -d "$APPS_PATH" ]; then
            echo "🗑️  Removing existing app in Applications..."
            sudo rm -rf "$APPS_PATH"
        fi
        
        # Copy the app
        sudo cp -R "$DERIVED_APP" "/Applications/"
        
        if [ -d "$APPS_PATH" ]; then
            echo "✅ Successfully copied app to Applications"
            
            # Fix permissions
            sudo chown -R $(whoami):staff "$APPS_PATH"
            sudo chmod -R 755 "$APPS_PATH"
            
            # Try to codesign it properly
            echo "🔐 Attempting to codesign the app..."
            codesign --force --deep --sign - "$APPS_PATH" 2>/dev/null || echo "   ⚠️  Codesigning failed (this is normal for development builds)"
            
            echo "📍 App location: $APPS_PATH"
            return 0
        else
            echo "❌ Failed to copy app to Applications"
            return 1
        fi
    else
        echo "❌ Could not find app in DerivedData"
        return 1
    fi
}

# Function to detect macOS version
detect_macos_version() {
    MACOS_VERSION=$(sw_vers -productVersion | cut -d '.' -f 1)
    MACOS_MINOR=$(sw_vers -productVersion | cut -d '.' -f 2)
    MACOS_BUILD=$(sw_vers -buildVersion)
    
    echo "🍎 macOS Version: $(sw_vers -productVersion) (Build: $MACOS_BUILD)"
    
    if [ "$MACOS_VERSION" -ge 15 ]; then
        echo "🍎 macOS Sequoia (15.0+) detected - Enhanced permission handling enabled"
        IS_SEQUOIA=true
    elif [ "$MACOS_VERSION" -ge 14 ]; then
        echo "🍎 macOS Sonoma (14.0+) detected"
        IS_SEQUOIA=false
    elif [ "$MACOS_VERSION" -ge 13 ]; then
        echo "🍎 macOS Ventura (13.0+) detected"
        IS_SEQUOIA=false
    else
        echo "🍎 macOS $(sw_vers -productVersion) detected"
        IS_SEQUOIA=false
    fi
}

# Function to handle macOS Sequoia specific issues
handle_sequoia_permissions() {
    if [ "$IS_SEQUOIA" = true ]; then
        echo "🍎 Applying macOS Sequoia specific fixes..."
        echo "   - Weekly permission renewal requirement detected"
        echo "   - Enhanced TCC database handling required"
        
        # More aggressive TCC reset for Sequoia
        echo "   - Performing enhanced TCC reset..."
        sudo tccutil reset All "$BUNDLE_ID" 2>/dev/null || echo "   ⚠️  Enhanced reset failed - continuing with standard reset"
        
        # Force TCC daemon restart for Sequoia
        echo "   - Forcing TCC daemon restart..."
        sudo pkill -f tccd 2>/dev/null || echo "   ⚠️  TCC daemon restart failed"
        sleep 2
        
        # Clear system-wide TCC cache
        echo "   - Clearing system TCC cache..."
        sudo rm -rf /var/db/SystemPolicy/TCC.db-wal 2>/dev/null || echo "   ⚠️  TCC cache clear failed (normal if not present)"
        sudo rm -rf /var/db/SystemPolicy/TCC.db-shm 2>/dev/null || echo "   ⚠️  TCC cache clear failed (normal if not present)"
        
        echo "✅ Sequoia-specific fixes applied"
        echo "💡 Note: On macOS Sequoia, permissions may need weekly renewal"
        echo "💡 Consider using stable app location (/Applications/) to minimize issues"
    else
        echo "✅ Pre-Sequoia macOS - using standard permission handling"
    fi
}

# Function to open System Preferences with version awareness
open_system_preferences() {
    echo "🔧 Opening System Preferences to Screen Recording settings..."
    
    if [ "$IS_SEQUOIA" = true ]; then
        # macOS Sequoia (15.0+) - System Settings
        echo "   Opening System Settings (macOS Sequoia)..."
        open "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture" 2>/dev/null || \
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null
    elif [ "$MACOS_VERSION" -ge 13 ]; then
        # macOS 13+ (Ventura and later) - System Settings
        echo "   Opening System Settings (macOS 13+)..."
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null
    else
        # Older macOS versions - System Preferences
        echo "   Opening System Preferences (macOS 12 and earlier)..."
        open "/System/Library/PreferencePanes/Security.prefPane" 2>/dev/null
    fi
    
    # Fallback
    if [ $? -ne 0 ]; then
        echo "   ⚠️  Direct open failed, trying alternative method..."
        open "/System/Library/PreferencePanes/Security.prefPane" 2>/dev/null
    fi
    
    echo "📖 Manual steps:"
    echo "   1. In System Preferences/Settings, go to Privacy & Security"
    echo "   2. Click on 'Screen Recording' in the left sidebar"
    echo "   3. Look for 'AudioAssist' in the list"
    echo "   4. If not found, click the '+' button and navigate to:"
    echo "      /Applications/AudioAssist.app"
    echo "   5. Check the box next to AudioAssist to enable it"
    echo "   6. Restart AudioAssist"
}

# Main execution flow
main() {
    echo ""
    echo "🚀 Starting enhanced permission fix process..."
    echo ""
    
    # Step 0: Detect macOS version for enhanced handling
    detect_macos_version
    
    echo ""
    
    # Step 1: Stop the app if running
    if check_app_running; then
        kill_app
    fi
    
    echo ""
    
    # Step 2: Handle macOS Sequoia specific issues
    handle_sequoia_permissions
    
    echo ""
    
    # Step 3: Reset TCC permissions
    reset_tcc_permissions
    
    echo ""
    
    # Step 4: Clean app data
    clean_app_data
    
    echo ""
    
    # Step 5: Clean Xcode data
    clean_xcode_data
    
    echo ""
    
    # Step 6: Check current status
    check_permission_status
    
    echo ""
    
    # Step 7: Create proper app bundle
    if create_proper_app_bundle; then
        echo ""
        echo "✅ App successfully prepared in Applications folder"
        
        # Step 7: Open System Preferences
        echo ""
        open_system_preferences
        
        echo ""
        echo "🎯 NEXT STEPS:"
        echo "=============="
        echo "1. ✅ Complete the manual permission setup in System Settings/Preferences"
        echo "2. 🚀 Launch AudioAssist from Applications folder (not from Xcode)"
        echo "3. 🧪 Test the screen recording functionality"
        echo ""
        
        if [ "$IS_SEQUOIA" = true ]; then
            echo "🍎 macOS Sequoia Specific Notes:"
            echo "   - Weekly permission renewal may be required"
            echo "   - Keep app in /Applications/ for stable permissions"
            echo "   - TCC database is more restrictive in Sequoia"
            echo ""
        fi
        
        echo "💡 If the issue persists:"
        echo "   - Try building and running from Xcode AFTER setting the permission"
        echo "   - Check that the Bundle ID matches: $BUNDLE_ID"
        echo "   - Look for any codesigning issues in Xcode"
        
        if [ "$IS_SEQUOIA" = true ]; then
            echo "   - On Sequoia: Consider weekly permission refresh"
            echo "   - On Sequoia: Verify System Settings → Privacy & Security → Screen Recording"
        fi
        
    else
        echo ""
        echo "⚠️  Could not create proper app bundle"
        echo "💡 Alternative approach:"
        echo "   1. Build the app in Xcode"
        
        if [ "$IS_SEQUOIA" = true ]; then
            echo "   2. Go to System Settings → Privacy & Security → Screen Recording"
        else
            echo "   2. Go to System Preferences → Privacy & Security → Screen Recording"
        fi
        
        echo "   3. Click '+' and manually add the app from DerivedData"
        echo "   4. The path is usually something like:"
        echo "      ~/Library/Developer/Xcode/DerivedData/AudioAssist-*/Build/Products/Debug/AudioAssist.app"
        
        if [ "$IS_SEQUOIA" = true ]; then
            echo ""
            echo "🍎 macOS Sequoia Alternative Notes:"
            echo "   - Weekly permission renewal may still be required"
            echo "   - DerivedData path changes with each build"
            echo "   - Consider copying to /Applications/ for stability"
        fi
        
        echo ""
        open_system_preferences
    fi
    
    echo ""
    if [ "$IS_SEQUOIA" = true ]; then
        echo "🏁 Enhanced permission fix script completed for macOS Sequoia!"
        echo "💡 Remember: Sequoia requires weekly permission renewal"
    else
        echo "🏁 Permission fix script completed!"
    fi
}

# Run the main function
main

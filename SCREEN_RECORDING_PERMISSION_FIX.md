# AudioAssist Screen Recording Permission Fix

## Problem Description

AudioAssist needs Screen Recording permission to capture system audio (speakers/headphones) using ScreenCaptureKit. However, development builds from Xcode often have permission issues due to:

1. **Development Build Location**: Apps built from Xcode are stored in `~/Library/Developer/Xcode/DerivedData/`, which can cause permission inconsistencies
2. **Adhoc Code Signing**: Development builds use adhoc code signing instead of proper certificates
3. **Bundle Identifier Changes**: The app's location and signing can confuse macOS's TCC (Transparency, Consent, and Control) system
4. **Cache Issues**: Old permission states can persist even after granting permissions

## Root Cause Analysis

The main issue is that macOS tracks screen recording permissions based on:
- Bundle identifier (`com.dogan.audioassist`)
- App location and executable path
- Code signing identity

When developing with Xcode:
- App location changes with each build (DerivedData path includes build hash)
- Adhoc signing means no stable identity
- TCC database can have stale entries

## Comprehensive Solution

### 1. Enhanced Permission Detection

The app now includes:
- **Development build detection**: Automatically detects if running from DerivedData
- **Multiple permission request attempts**: For development builds, tries multiple strategies
- **Enhanced logging**: Detailed permission status logging for debugging

### 2. Updated Entitlements

Enhanced `AudioAssist.entitlements` with:
```xml
<!-- Screen Recording specific entitlements -->
<key>com.apple.security.temporary-exception.shared-preference.read-write</key>
<array>
    <string>com.apple.TCC</string>
</array>

<!-- Allow access to system services -->
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>com.apple.windowserver.active</string>
    <string>com.apple.tccd</string>
    <string>com.apple.coreservices.quarantine-resolver</string>
</array>

<!-- Disable library validation for development -->
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

### 3. Automated Fix Script

The `fix_screen_recording_permissions.sh` script provides a comprehensive solution:

#### What it does:
1. **Stops the running app** to ensure clean state
2. **Resets TCC permissions** using `sudo tccutil reset`
3. **Cleans app data** (caches, preferences, saved state)
4. **Cleans Xcode build data** (DerivedData, module cache)
5. **Creates proper app bundle** in `/Applications/` folder
6. **Opens System Preferences** to Screen Recording settings

#### Usage:
```bash
# Make executable (if not already)
chmod +x fix_screen_recording_permissions.sh

# Run the script
./fix_screen_recording_permissions.sh
```

### 4. Enhanced UI Guidance

The app now provides:
- **Development build detection** in UI
- **Contextual help messages** based on build type
- **Automated script execution** from within the app
- **Detailed permission status logging**

## Step-by-Step Solution

### Option A: Automated Fix (Recommended)

1. **Run the fix script**:
   ```bash
   cd /path/to/Meeting_MacoS_Swift
   ./fix_screen_recording_permissions.sh
   ```

2. **Follow the script output** - it will guide you through each step

3. **In System Preferences**:
   - Go to **Privacy & Security** → **Screen Recording**
   - Look for "AudioAssist" in the list
   - If not found, click "**+**" and navigate to `/Applications/AudioAssist.app`
   - **Check the box** to enable the permission

4. **Launch the app** from Applications folder (not from Xcode initially)

5. **Test the functionality** - the permission should now work

### Option B: Manual Fix

1. **Stop AudioAssist** if running

2. **Reset permissions** (requires admin password):
   ```bash
   sudo tccutil reset ScreenCapture com.dogan.audioassist
   sudo tccutil reset Microphone com.dogan.audioassist
   sudo tccutil reset Camera com.dogan.audioassist
   ```

3. **Clean app data**:
   ```bash
   rm -rf ~/Library/Caches/com.dogan.audioassist
   rm -rf ~/Library/Saved\ Application\ State/com.dogan.audioassist.savedState/
   rm -rf ~/Library/Preferences/com.dogan.audioassist.plist
   ```

4. **Clean Xcode data**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/AudioAssist-*
   ```

5. **Build and run from Xcode**

6. **Grant permission** when prompted, or manually in System Preferences

### Option C: Production Build Approach

1. **Archive the app** in Xcode (Product → Archive)
2. **Export for local distribution**
3. **Install in Applications folder**
4. **Grant permissions** through System Preferences
5. **Run from Applications folder**

## Verification

After applying the fix, verify it works:

1. **Check permission status** in the app UI
2. **Look for log messages** like:
   ```
   [SC] ✅ Screen recording permission granted
   [SC] 🎵 Audio received: X samples
   ```
3. **Test system audio capture** by playing audio and checking if it's transcribed

## Troubleshooting

### Permission still denied after fix:

1. **Check System Preferences again** - ensure AudioAssist is listed and enabled
2. **Try restarting macOS** - sometimes required for permission changes
3. **Check for multiple entries** in Screen Recording list - remove duplicates
4. **Verify Bundle ID** matches `com.dogan.audioassist`

### App not appearing in System Preferences:

1. **Run the app once** to trigger system registration
2. **Use the "+" button** to manually add from `/Applications/AudioAssist.app`
3. **Check if app is properly signed**: `codesign -dv /Applications/AudioAssist.app`

### Still having issues:

1. **Check Console.app** for TCC-related error messages
2. **Try with a different Bundle ID** (change in Xcode project settings)
3. **Contact system administrator** if on managed Mac

## Technical Details

### Files Modified:
- `AudioAssist.entitlements` - Enhanced with screen recording entitlements
- `SystemAudioCaptureSC.swift` - Improved permission detection and handling
- `ContentView.swift` - Enhanced UI with development build guidance
- `fix_screen_recording_permissions.sh` - Comprehensive automated fix script

### Key Functions:
- `checkPermissions()` - Enhanced permission checking with development build detection
- `updatePermissionStatus()` - UI permission status with development build hints
- `runPermissionFixScript()` - Automated script execution from app

### Permission APIs Used:
- `CGPreflightScreenCaptureAccess()` - Check current permission status
- `CGRequestScreenCaptureAccess()` - Request permission (may show dialog)
- `SCShareableContent.current` - ScreenCaptureKit content access (requires permission)

## Prevention

To avoid this issue in future development:

1. **Test with production-like builds** occasionally
2. **Use consistent Bundle IDs** across development and production
3. **Document permission requirements** for team members
4. **Consider using proper developer certificates** for development builds

## Conclusion

This comprehensive solution addresses the screen recording permission issues commonly encountered with ScreenCaptureKit in development environments. The automated fix script should resolve most permission problems, while the enhanced app provides better user guidance and debugging information.

The key insight is that development builds from Xcode can have permission inconsistencies due to their location in DerivedData and adhoc code signing. Moving the app to Applications folder and properly resetting TCC permissions typically resolves these issues.

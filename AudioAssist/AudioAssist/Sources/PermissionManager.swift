import Foundation
import ScreenCaptureKit
import SwiftUI

// MARK: - Test Stream Output for Permission Testing

/// Minimal SCStreamOutput implementation for permission testing only
/// This class is used solely to test if SCStream can be created with proper permissions
@available(macOS 13.0, *)
private class TestStreamOutput: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // No-op: We only need this for permission testing
    }
}

/// Centralized permission management for screen recording with enhanced detection
/// Handles macOS Sequoia weekly permission requirements and development build issues
@available(macOS 13.0, *)
@MainActor
class PermissionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var hasScreenRecordingPermission = false
    @Published var lastPermissionCheck = Date()
    @Published var permissionCheckInProgress = false
    
    // MARK: - Private Properties
    
    private let permissionCheckInterval: TimeInterval = 900 // 15 minutes for Sequoia compatibility
    private var permissionTimer: Timer?
    private var lastSuccessfulCheck = Date.distantPast
    
    // Bundle information
    private let bundleID: String
    private let bundlePath: String
    private let executablePath: String
    private let isDevelopmentBuild: Bool
    private let isSequoiaOrLater: Bool
    
    // MARK: - Initialization
    
    init() {
        self.bundleID = Bundle.main.bundleIdentifier ?? "com.dogan.audioassist"
        self.bundlePath = Bundle.main.bundlePath
        self.executablePath = Bundle.main.executablePath ?? "Unknown"
        self.isDevelopmentBuild = Bundle.main.bundlePath.contains("DerivedData")
        self.isSequoiaOrLater = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15
        
        print("[PermissionManager] 🔒 Initializing...")
        print("[PermissionManager] 🆔 Bundle ID: \(bundleID)")
        print("[PermissionManager] 📁 Bundle Path: \(bundlePath)")
        print("[PermissionManager] 🚀 Executable Path: \(executablePath)")
        print("[PermissionManager] 🔧 Development build: \(isDevelopmentBuild)")
        print("[PermissionManager] 🍎 macOS Sequoia or later: \(isSequoiaOrLater)")
        
        // Start with immediate permission check (detached task to avoid actor issues)
        Task.detached { @MainActor in
            await self.checkPermissionStatus()
            self.startPeriodicPermissionCheck()
        }
    }
    
    deinit {
        print("[PermissionManager] 🔒 Deinitializing...")
        
        // 🚨 CRITICAL FIX: Synchronous cleanup to prevent SIGABRT
        // Timer'ı senkron olarak temizle
        if Thread.isMainThread {
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else {
            DispatchQueue.main.sync {
                permissionTimer?.invalidate()
                permissionTimer = nil
            }
        }
        
        print("[PermissionManager] 🔒 Deinitialized safely")
    }
    
    // MARK: - Public Methods
    
    /// Force an immediate permission check
    func checkPermissionStatus() async {
        guard !permissionCheckInProgress else {
            print("[PermissionManager] ⚠️ Permission check already in progress")
            return
        }
        
        permissionCheckInProgress = true
        defer { permissionCheckInProgress = false }
        
        let hasPermission = await performEnhancedPermissionCheck()
        
        if hasScreenRecordingPermission != hasPermission {
            hasScreenRecordingPermission = hasPermission
            lastPermissionCheck = Date()
            
            if hasPermission {
                lastSuccessfulCheck = Date()
                print("[PermissionManager] ✅ Permission status changed: GRANTED")
            } else {
                print("[PermissionManager] ❌ Permission status changed: DENIED")
            }
            
            // Notify other components
            NotificationCenter.default.post(
                name: .screenRecordingPermissionChanged,
                object: hasPermission
            )
        }
    }
    
    /// Request permission with enhanced user guidance
    func requestPermissionWithGuidance() async -> Bool {
        print("[PermissionManager] 🔒 Requesting permission with enhanced guidance...")
        
        guard !permissionCheckInProgress else {
            print("[PermissionManager] ⚠️ Permission check already in progress")
            return hasScreenRecordingPermission
        }
        
        permissionCheckInProgress = true
        defer { permissionCheckInProgress = false }
        
        // Show guidance for different scenarios
        if isSequoiaOrLater {
            await showSequoiaPermissionGuidance()
        }
        
        if isDevelopmentBuild {
            await showDevelopmentBuildGuidance()
        }
        
        // Perform enhanced permission request
        let granted = await performEnhancedPermissionRequest()
        
        hasScreenRecordingPermission = granted
        lastPermissionCheck = Date()
        
        if granted {
            lastSuccessfulCheck = Date()
        }
        
        return granted
    }
    
    /// Get detailed permission status information
    func getPermissionStatusInfo() -> PermissionStatusInfo {
        return PermissionStatusInfo(
            hasPermission: hasScreenRecordingPermission,
            lastCheck: lastPermissionCheck,
            lastSuccessfulCheck: lastSuccessfulCheck,
            bundleID: bundleID,
            bundlePath: bundlePath,
            isDevelopmentBuild: isDevelopmentBuild,
            isSequoiaOrLater: isSequoiaOrLater,
            needsWeeklyRenewal: isSequoiaOrLater && Date().timeIntervalSince(lastSuccessfulCheck) > 604800 // 7 days
        )
    }
    
    // MARK: - Private Methods
    
    private func startPeriodicPermissionCheck() {
        // Adjust check frequency based on macOS version
        let interval = isSequoiaOrLater ? 900.0 : 1800.0 // 15 min vs 30 min
        
        // Timer'ı main queue'da çalıştır - SIGABRT hatası için
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.permissionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkPermissionStatus()
                }
            }
        }
        
        print("[PermissionManager] ⏰ Started periodic permission check (every \(interval/60) minutes)")
    }
    
    private func performEnhancedPermissionCheck() async -> Bool {
        print("[PermissionManager] 🔍 Performing enhanced permission check...")
        
        // 🚨 CRITICAL FIX: Don't trust CGPreflightScreenCaptureAccess alone!
        // Apple Developer Forums: CGPreflightScreenCaptureAccess can return stale cache data
        let preflightResult = CGPreflightScreenCaptureAccess()
        print("[PermissionManager] 🔒 CGPreflightScreenCaptureAccess: \(preflightResult)")
        
        // Primary check: SCShareableContent (most reliable)
        do {
            let content = try await SCShareableContent.current
            let hasDisplays = !content.displays.isEmpty
            print("[PermissionManager] 📺 SCShareableContent displays available: \(hasDisplays)")
            
            if hasDisplays {
                print("[PermissionManager] ✅ SCShareableContent accessible - permission confirmed")
                
                // Additional verification: Try to create a minimal SCStream to test real permission
                let realPermissionTest = await performRealSCStreamPermissionTest()
                print("[PermissionManager] 🧪 Real SCStream permission test: \(realPermissionTest)")
                
                return realPermissionTest
            } else {
                print("[PermissionManager] ❌ No displays available via SCShareableContent")
                return false
            }
        } catch {
            print("[PermissionManager] ❌ SCShareableContent check failed: \(error.localizedDescription)")
            
            // Analyze error for permission-specific issues
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("not authorized") || 
               errorString.contains("permission") ||
               errorString.contains("denied") ||
               errorString.contains("tcc") {
                print("[PermissionManager] 🔒 Error confirms permission denial")
                return false
            }
            
            // If SCShareableContent fails for other reasons, fall back to preflight
            // but with a warning that this might be unreliable
            print("[PermissionManager] ⚠️ Falling back to CGPreflightScreenCaptureAccess (may be unreliable)")
            return preflightResult
        }
    }
    
    /// Perform actual SCStream permission test (most reliable method)
    /// This is the definitive test - if SCStream can't be created, permission is really denied
    private func performRealSCStreamPermissionTest() async -> Bool {
        print("[PermissionManager] 🧪 Testing real SCStream permission...")
        
        do {
            // Get shareable content (we already know this works from previous check)
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                print("[PermissionManager] ❌ No displays for SCStream test")
                return false
            }
            
            // Create minimal SCStream configuration for testing
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 1
            
            // Try to create SCStream - this is the real permission test
            let testStream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            // Try to add a minimal output (required for permission test)
            let testQueue = DispatchQueue(label: "permission.test.queue")
            
            do {
                // This is where the real permission check happens
                try testStream.addStreamOutput(TestStreamOutput(), type: .audio, sampleHandlerQueue: testQueue)
                print("[PermissionManager] ✅ SCStream addOutput successful - permission confirmed")
                
                // For permission test, we don't need to start/stop capture
                // Just successfully adding output means permission is granted
                print("[PermissionManager] 🧪 Permission test completed - no need to start/stop stream")
                return true
                
            } catch {
                let nsError = error as NSError
                print("[PermissionManager] ❌ SCStream addOutput failed: \(error)")
                print("[PermissionManager] 🔍 Error domain: \(nsError.domain), code: \(nsError.code)")
                
                // Check for specific permission error codes
                if nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3801 {
                    print("[PermissionManager] 🚨 CONFIRMED: Permission denied (TCC error -3801)")
                    return false
                }
                
                // Other SCStream errors might not be permission-related
                print("[PermissionManager] ⚠️ SCStream error might not be permission-related")
                return false
            }
            
        } catch {
            print("[PermissionManager] ❌ SCStream permission test failed: \(error)")
            return false
        }
    }
    
    private func performEnhancedPermissionRequest() async -> Bool {
        print("[PermissionManager] 🔒 Performing enhanced permission request...")
        
        // For development builds, try multiple approaches with timing
        if isDevelopmentBuild {
            return await performDevelopmentBuildPermissionRequest()
        } else {
            return await performStandardPermissionRequest()
        }
    }
    
    private func performDevelopmentBuildPermissionRequest() async -> Bool {
        print("[PermissionManager] 🔧 Development build permission request strategy...")
        
        // Multiple attempts with progressive delays
        for attempt in 1...5 {
            print("[PermissionManager] 🔒 Development permission attempt \(attempt)/5...")
            
            let granted = CGRequestScreenCaptureAccess()
            print("[PermissionManager] 🔒 CGRequestScreenCaptureAccess result: \(granted)")
            
            // Immediate check
            let immediateStatus = await performEnhancedPermissionCheck()
            if immediateStatus {
                print("[PermissionManager] ✅ SUCCESS on attempt \(attempt)!")
                return true
            }
            
            // Progressive wait times
            let waitTime = UInt64(attempt * 300_000_000) // 0.3s, 0.6s, 0.9s, etc.
            try? await Task.sleep(nanoseconds: waitTime)
            
            // Delayed check
            let delayedStatus = await performEnhancedPermissionCheck()
            if delayedStatus {
                print("[PermissionManager] ✅ SUCCESS on delayed check attempt \(attempt)!")
                return true
            }
        }
        
        return false
    }
    
    private func performStandardPermissionRequest() async -> Bool {
        print("[PermissionManager] 🔒 Standard permission request...")
        
        let granted = CGRequestScreenCaptureAccess()
        print("[PermissionManager] 🔒 CGRequestScreenCaptureAccess result: \(granted)")
        
        // Wait longer for Sequoia
        let waitTime = UInt64(isSequoiaOrLater ? 1_000_000_000 : 500_000_000) // 1s vs 0.5s
        try? await Task.sleep(nanoseconds: waitTime)
        
        return await performEnhancedPermissionCheck()
    }
    
    private func showSequoiaPermissionGuidance() async {
        print("[PermissionManager] 🍎 macOS Sequoia guidance:")
        print("[PermissionManager] 💡 Weekly permission renewal required on macOS 15+")
        print("[PermissionManager] 💡 This is a system security feature")
        
        if Date().timeIntervalSince(lastSuccessfulCheck) > 604800 { // 7 days
            print("[PermissionManager] ⚠️ Permission may have expired (> 7 days since last success)")
        }
    }
    
    private func showDevelopmentBuildGuidance() async {
        print("[PermissionManager] 🔧 Development build guidance:")
        print("[PermissionManager] 💡 Bundle path changes with each build can cause TCC cache issues")
        print("[PermissionManager] 💡 Consider using fix_screen_recording_permissions.sh script")
        print("[PermissionManager] 💡 Or manually add app from Applications folder")
        
        // Detect potential TCC cache issues
        await detectTCCCacheIssues()
    }
    
    /// Detect and report TCC cache issues specific to development builds
    private func detectTCCCacheIssues() async {
        print("[PermissionManager] 🔍 Detecting TCC cache issues...")
        
        // Check if bundle path is in DerivedData (common issue)
        if bundlePath.contains("DerivedData") {
            print("[PermissionManager] ⚠️ TCC Issue: App running from DerivedData")
            print("[PermissionManager] 💡 Each build creates new path, invalidating TCC permissions")
            
            // Extract project name from DerivedData path
            if let projectName = extractProjectNameFromDerivedData() {
                print("[PermissionManager] 📁 Project: \(projectName)")
                print("[PermissionManager] 💡 Solution: Copy app to /Applications/ for stable permissions")
            }
        }
        
        // Check for bundle identifier mismatches
        let expectedBundleID = "com.dogan.audioassist"
        if bundleID != expectedBundleID {
            print("[PermissionManager] ⚠️ TCC Issue: Bundle ID mismatch")
            print("[PermissionManager] 📋 Expected: \(expectedBundleID)")
            print("[PermissionManager] 📋 Actual: \(bundleID)")
        }
        
        // Check executable path stability
        if executablePath.contains("DerivedData") {
            print("[PermissionManager] ⚠️ TCC Issue: Executable path in DerivedData")
            print("[PermissionManager] 💡 This path changes with each build")
        }
        
        // Provide specific solutions
        await provideTCCCacheSolutions()
    }
    
    /// Extract project name from DerivedData path for better debugging
    private func extractProjectNameFromDerivedData() -> String? {
        let pathComponents = bundlePath.components(separatedBy: "/")
        
        for (index, component) in pathComponents.enumerated() {
            if component == "DerivedData" && index + 1 < pathComponents.count {
                let derivedDataFolder = pathComponents[index + 1]
                // DerivedData folder format is usually "ProjectName-randomstring"
                return derivedDataFolder.components(separatedBy: "-").first
            }
        }
        
        return nil
    }
    
    /// Provide specific solutions for TCC cache issues
    private func provideTCCCacheSolutions() async {
        print("[PermissionManager] 💡 TCC Cache Solutions:")
        print("[PermissionManager] 💡 1. IMMEDIATE: Run fix_screen_recording_permissions.sh")
        print("[PermissionManager] 💡 2. MANUAL: Copy app to /Applications/AudioAssist.app")
        print("[PermissionManager] 💡 3. RESET: sudo tccutil reset ScreenCapture \(bundleID)")
        print("[PermissionManager] 💡 4. REFRESH: sudo killall tccd")
        
        if isSequoiaOrLater {
            print("[PermissionManager] 💡 5. SEQUOIA: Weekly permission renewal required")
            print("[PermissionManager] 💡 6. SEQUOIA: Consider using stable app location")
        }
        
        // Check if we can provide automated solution
        await checkAutomatedSolutionAvailability()
    }
    
    /// Check if automated solutions are available
    private func checkAutomatedSolutionAvailability() async {
        // Check if fix script exists
        let scriptPaths = [
            Bundle.main.path(forResource: "fix_screen_recording_permissions", ofType: "sh"),
            "../../../fix_screen_recording_permissions.sh",
            "./fix_screen_recording_permissions.sh"
        ]
        
        for path in scriptPaths {
            if let scriptPath = path, FileManager.default.fileExists(atPath: scriptPath) {
                print("[PermissionManager] ✅ Fix script available at: \(scriptPath)")
                return
            }
        }
        
        print("[PermissionManager] ⚠️ Fix script not found - manual steps required")
    }
    
    /// Enhanced permission request with TCC cache awareness
    func requestPermissionWithTCCCacheHandling() async -> Bool {
        print("[PermissionManager] 🔒 Enhanced permission request with TCC cache handling...")
        
        // First, try standard permission request
        let standardResult = await requestPermissionWithGuidance()
        if standardResult {
            return true
        }
        
        // If failed and it's a development build, try TCC cache solutions
        if isDevelopmentBuild {
            print("[PermissionManager] 🔧 Standard request failed - trying TCC cache solutions...")
            return await handleTCCCacheIssues()
        }
        
        return false
    }
    
    /// Handle TCC cache issues with automated solutions
    private func handleTCCCacheIssues() async -> Bool {
        print("[PermissionManager] 🛠️ Handling TCC cache issues...")
        
        // Solution 1: Multiple permission requests with delays (for cache refresh)
        for attempt in 1...3 {
            print("[PermissionManager] 🔄 TCC cache refresh attempt \(attempt)/3...")
            
            let granted = CGRequestScreenCaptureAccess()
            if granted {
                // Wait for TCC database update
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                let verified = await performEnhancedPermissionCheck()
                if verified {
                    print("[PermissionManager] ✅ TCC cache refresh successful!")
                    return true
                }
            }
            
            // Progressive wait times
            try? await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000)) // 0.5s, 1s, 1.5s
        }
        
        // Solution 2: Try to trigger TCC daemon refresh
        await triggerTCCDaemonRefresh()
        
        // Final verification
        return await performEnhancedPermissionCheck()
    }
    
    /// Attempt to trigger TCC daemon refresh (limited success without sudo)
    private func triggerTCCDaemonRefresh() async {
        print("[PermissionManager] 🔄 Attempting TCC daemon refresh...")
        
        // We can't kill tccd without sudo, but we can try to trigger a refresh
        // by accessing TCC-related system services
        do {
            let _ = try await SCShareableContent.current
            print("[PermissionManager] 📡 TCC service access attempted")
        } catch {
            print("[PermissionManager] ⚠️ TCC service access failed: \(error.localizedDescription)")
        }
        
        // Small delay for any potential refresh
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    // MARK: - Automatic TCC Reset System (Apple Developer Community Solutions)
    
    /// Automatic TCC permission reset when cache issues detected
    /// Based on Apple Developer Forums solutions for persistent permission problems
    func performAutomaticTCCReset() async -> Bool {
        print("[PermissionManager] 🚨 AUTOMATIC TCC RESET - Starting...")
        print("[PermissionManager] 📝 This fixes the common development build permission cache issue")
        
        // Step 1: Detect if we're in the problematic state
        let preflightResult = CGPreflightScreenCaptureAccess()
        let systemSettingsHasPermission = await checkSystemSettingsPermission()
        
        if preflightResult && systemSettingsHasPermission {
            print("[PermissionManager] ✅ Permissions appear to be working correctly")
            return true
        }
        
        print("[PermissionManager] 🔍 Permission mismatch detected:")
        print("[PermissionManager]   - CGPreflightScreenCaptureAccess: \(preflightResult)")
        print("[PermissionManager]   - System Settings Permission: \(systemSettingsHasPermission)")
        
        // Step 2: Execute automatic reset script
        let resetSuccess = await executeAutomaticResetScript()
        
        if resetSuccess {
            print("[PermissionManager] ✅ Automatic TCC reset completed successfully")
            // Trigger a fresh permission check
            await checkPermissionStatus()
            return hasScreenRecordingPermission
        } else {
            print("[PermissionManager] ❌ Automatic reset failed - manual intervention required")
            return false
        }
    }
    
    /// Execute the automatic reset script for TCC cache issues
    private func executeAutomaticResetScript() async -> Bool {
        print("[PermissionManager] 🔧 Executing automatic TCC reset script...")
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/bin/bash"
            
            // Create the reset script content
            let scriptContent = """
            #!/bin/bash
            echo "🚨 AUTOMATIC TCC RESET FOR AUDIOASSIST"
            echo "📝 Based on Apple Developer Community solutions"
            
            # Get bundle identifier
            BUNDLE_ID="com.dogan.audioassist"
            echo "🎯 Target Bundle ID: $BUNDLE_ID"
            
            # Step 1: Remove TCC entries for our app
            echo "🗑️ Removing TCC entries..."
            sqlite3 ~/Library/Application\\ Support/com.apple.TCC/TCC.db "DELETE FROM access WHERE client='$BUNDLE_ID';" 2>/dev/null || true
            
            # Step 2: Clear any cached permissions
            echo "🧹 Clearing permission cache..."
            rm -rf ~/Library/Caches/com.apple.TCC/* 2>/dev/null || true
            
            # Step 3: Restart Dock (lightweight TCC refresh)
            echo "🔄 Refreshing Dock for TCC update..."
            killall Dock 2>/dev/null || true
            
            # Step 4: Clear Xcode DerivedData for this project
            echo "🧹 Clearing Xcode DerivedData..."
            rm -rf ~/Library/Developer/Xcode/DerivedData/AudioAssist-* 2>/dev/null || true
            
            echo "✅ Automatic TCC reset completed"
            echo "🔔 Please restart the app to test the fix"
            """
            
            // Write script to temporary file
            let tempScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("audioassist_tcc_reset.sh")
            
            do {
                try scriptContent.write(to: tempScriptURL, atomically: true, encoding: .utf8)
                
                // Make executable
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptURL.path)
                
                task.arguments = [tempScriptURL.path]
                
                task.terminationHandler = { _ in
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: tempScriptURL)
                    
                    let success = task.terminationStatus == 0
                    print("[PermissionManager] 🔧 Reset script finished with status: \(task.terminationStatus)")
                    continuation.resume(returning: success)
                }
                
                task.launch()
                
            } catch {
                print("[PermissionManager] ❌ Failed to create reset script: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Check if permission exists in System Settings (not just TCC cache)
    func checkSystemSettingsPermission() async -> Bool {
        // This is a more reliable check than CGPreflightScreenCaptureAccess
        // because it doesn't rely on TCC cache
        do {
            let content = try await SCShareableContent.current
            return !content.displays.isEmpty
        } catch {
            print("[PermissionManager] 🔍 System Settings permission check failed: \(error)")
            return false
        }
    }
}

// MARK: - Supporting Types

struct PermissionStatusInfo {
    let hasPermission: Bool
    let lastCheck: Date
    let lastSuccessfulCheck: Date
    let bundleID: String
    let bundlePath: String
    let isDevelopmentBuild: Bool
    let isSequoiaOrLater: Bool
    let needsWeeklyRenewal: Bool
}

// MARK: - Notifications

extension Notification.Name {
    static let screenRecordingPermissionChanged = Notification.Name("screenRecordingPermissionChanged")
}

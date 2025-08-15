import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreAudio

@available(macOS 13.0, *)
final class SystemAudioCaptureSC: NSObject, SCStreamOutput, SCStreamDelegate {

    // Dışarı: 16 kHz, mono, Int16 PCM
    var onPCM16k: ((Data) -> Void)?

    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "sc.audio.queue")
    private var converter: AVAudioConverter?
    
    // Enhanced permission management
    private var permissionManager: PermissionManager?
    
    // 🚨 CRITICAL FIX: Separate output handlers to prevent circular reference
    // This fixes the SCStream frame dropping issue identified in Apple Developer Forums
    private var streamOutputHandler: StreamOutputHandler?
    private var videoOutputHandler: VideoOutputHandler?
    
    // Frame drop detection for monitoring
    private var lastAudioReceived: Date?
    private var frameDropMonitor: Timer?
    
    // 🚨 CRASH PREVENTION: Error tracking
    private var consecutiveErrors: Int = 0
    private let maxConsecutiveErrors = 5
    private var lastErrorTime: Date?
    private let errorCooldownInterval: TimeInterval = 10.0 // 10 seconds
    
    // 🚨 CRASH PREVENTION: Processing state
    private var isProcessingAudio = false
    private let processingQueue = DispatchQueue(label: "sc.processing.queue", qos: .userInitiated)
    
    // 🎧 AUTOMATIC AUDIO DEVICE CHANGE DETECTION
    private var audioDevicePropertyListener: AudioObjectPropertyListenerProc?
    private var currentOutputDeviceID: AudioDeviceID = 0
    private var isMonitoringDeviceChanges = false

    // Hedef format: 48kHz, mono, Int16 interleaved (Deepgram ile uyumlu)
    private let outFmt = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48_000,
        channels: 1,
        interleaved: true
    )!
    
    // MARK: - Helper Classes
    
    // Helper class for handling stream output to prevent circular reference
    private class StreamOutputHandler: NSObject, SCStreamOutput {
        weak var parent: SystemAudioCaptureSC?
        
        init(parent: SystemAudioCaptureSC) {
            self.parent = parent
            super.init()
        }
        
        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            parent?.stream(stream, didOutputSampleBuffer: sampleBuffer, of: type)
        }
    }
    
    // Minimal video output handler to prevent SCStream frame drop errors
    private class VideoOutputHandler: NSObject, SCStreamOutput {
        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            // Ignore video frames - we only want audio
            // This handler exists solely to prevent SCStream from dropping frames
        }
    }
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        print("[SC] 🔧 SystemAudioCaptureSC initialized")
    }
    
    deinit {
        print("[SC] 🔧 SystemAudioCaptureSC deinitializing")
        
        // 🚨 CRITICAL FIX: Stop processing immediately to prevent SIGTERM
        isProcessingAudio = false
        
        // 🚨 THREAD SAFE: Cleanup on appropriate queues
        // Timer'ı senkron olarak temizle
        if Thread.isMainThread {
            frameDropMonitor?.invalidate()
            frameDropMonitor = nil
        } else {
            DispatchQueue.main.sync {
                frameDropMonitor?.invalidate()
                frameDropMonitor = nil
            }
        }
        
        // 🚨 THREAD SAFE: Stop stream on processing queue to avoid deadlock
        processingQueue.sync {
        stream?.stopCapture { _ in }
        stream = nil
        }
        
        // References'ları temizle
        streamOutputHandler = nil
        videoOutputHandler = nil
        converter = nil
        permissionManager = nil
        
        // 🚨 CRASH PREVENTION: Reset error tracking
        consecutiveErrors = 0
        lastErrorTime = nil
        
        // 🎧 Stop device change monitoring
        stopAudioDeviceMonitoring()
        
        print("[SC] 🔧 SystemAudioCaptureSC deinit completed safely")
    }

    // MARK: - Public
    
    /// Get current permission status from the permission manager
    func hasPermission() async -> Bool {
        guard let manager = permissionManager else {
            print("[SC] ⚠️ Permission manager not initialized")
            return false
        }
        
        return await MainActor.run { manager.hasScreenRecordingPermission }
    }
    
    /// Request permission using the enhanced permission manager
    func requestPermission() async -> Bool {
        guard let manager = permissionManager else {
            print("[SC] ⚠️ Permission manager not initialized")
            return false
        }
        
        return await manager.requestPermissionWithGuidance()
    }

    func start() async throws {
        print("[SC] 🚀 Starting SystemAudioCaptureSC...")
        
        // Initialize permission manager if not already done
        if permissionManager == nil {
            await MainActor.run {
                permissionManager = PermissionManager()
            }
            // Give permission manager time to initialize
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Check permissions using enhanced manager
        guard let manager = permissionManager else {
            throw NSError(domain: "SC", code: -3, 
                         userInfo: [NSLocalizedDescriptionKey: "Permission manager initialization failed"])
        }
        
        await manager.checkPermissionStatus()
        let hasPermission = await MainActor.run { manager.hasScreenRecordingPermission }
        
        if !hasPermission {
            print("[SC] ❌ Permission denied - attempting to request...")
            
            // Try to request permission
            let granted = await manager.requestPermissionWithGuidance()
            guard granted else {
                let error = NSError(domain: "SC", code: -2, 
                                  userInfo: [NSLocalizedDescriptionKey: "Screen recording permission denied"])
                print("[SC] ❌ Permission request failed: \(error.localizedDescription)")
                throw error
            }
            print("[SC] ✅ Permission granted after request - continuing...")
        }
        
        print("[SC] 🚀 requesting shareable content…")
        let content = try await SCShareableContent.current
        
        // 🔍 Debug: Mevcut içeriği logla
        print("[SC] 📺 Available displays: \(content.displays.count)")
        for (index, display) in content.displays.enumerated() {
            print("[SC] 📺 Display \(index): ID=\(display.displayID), Frame=\(display.frame)")
        }
        
        print("[SC] 📱 Available applications: \(content.applications.count)")
        print("[SC] 🪟 Available windows: \(content.windows.count)")

        guard let display = content.displays.first else {
            print("[SC] ❌ No displays found!")
            throw NSError(domain: "SC", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No displays found"])
        }

        print("[SC] 🎯 Using display: ID=\(display.displayID)")

        // 👇 Etiket sırasına dikkat: excludingApplications, exceptingWindows
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true        // ✅ var
        // cfg.capturesVideo = false     // ❌ böyle bir alan yok, ekleme
        cfg.sampleRate = 48_000
        cfg.channelCount = 2            // sistem miks genelde stereo
        
        // 🔍 Debug: Konfigürasyonu detaylı logla
        print("[SC] ⚙️ Stream Configuration:")
        print("[SC] ⚙️   - capturesAudio: \(cfg.capturesAudio)")
        print("[SC] ⚙️   - sampleRate: \(cfg.sampleRate) Hz")
        print("[SC] ⚙️   - channelCount: \(cfg.channelCount) channels")
        print("[SC] ⚙️   - Output format: \(outFmt.sampleRate) Hz, \(outFmt.channelCount) ch, \(outFmt.commonFormat.rawValue)")

        print("[SC] 🔧 Creating SCStream...")
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        
        // 🚨 CRITICAL FIX: Use dedicated output handlers to prevent circular reference
        // This is the key fix for SCStream frame dropping issue
        self.streamOutputHandler = StreamOutputHandler(parent: self)
        self.videoOutputHandler = VideoOutputHandler()
        
        print("[SC] 🔧 Adding audio output handler...")
        try s.addStreamOutput(self.streamOutputHandler!, type: .audio, sampleHandlerQueue: audioQueue)
        
        print("[SC] 🔧 Adding video output handler (to prevent frame drops)...")
        let videoQueue = DispatchQueue(label: "video.output.queue", qos: .userInitiated)
        try s.addStreamOutput(self.videoOutputHandler!, type: .screen, sampleHandlerQueue: videoQueue)
        
        print("[SC] 🔧 Starting capture...")
        try await s.startCapture()
        self.stream = s
        
        // Start frame drop monitoring
        startFrameDropMonitoring()
        
        // 🎧 Start automatic audio device change monitoring
        startAudioDeviceMonitoring()

        print("[SC] ✅ SystemAudioCaptureSC started successfully!")
        print("[SC] 🔍 Reference management: audio=\(streamOutputHandler != nil ? "RETAINED" : "NIL"), video=\(videoOutputHandler != nil ? "RETAINED" : "NIL")")
        print("[SC] 🎧 Audio device monitoring: \(isMonitoringDeviceChanges ? "ACTIVE" : "INACTIVE")")
    }
    
    // MARK: - Frame Drop Monitoring
    
    private func startFrameDropMonitoring() {
        stopFrameDropMonitoring()
        
        lastAudioReceived = Date()
        
        // Timer'ı main queue'da çalıştır - SIGTERM hatası için
        DispatchQueue.main.async { [weak self] in
            self?.frameDropMonitor = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkFrameDropStatus()
            }
        }
        
        print("[SC] 🔍 Frame drop monitoring started (5s intervals)")
    }
    
    private func stopFrameDropMonitoring() {
        // Timer'ı main queue'da stop et - SIGTERM hatası için
        DispatchQueue.main.async { [weak self] in
            self?.frameDropMonitor?.invalidate()
            self?.frameDropMonitor = nil
        }
        print("[SC] 🔍 Frame drop monitoring stopped")
    }
    
    private func checkFrameDropStatus() {
        if let lastTime = lastAudioReceived {
            let timeSinceLastAudio = Date().timeIntervalSince(lastTime)
            
            if timeSinceLastAudio > 10.0 {
                print("[SC] 🚨 FRAME DROP DETECTED! No audio for \(String(format: "%.1f", timeSinceLastAudio))s")
                print("[SC] 🔍 Stream state: \(stream != nil ? "EXISTS" : "NIL")")
                print("[SC] 🔍 Output handlers: audio=\(streamOutputHandler != nil ? "RETAINED" : "NIL"), video=\(videoOutputHandler != nil ? "RETAINED" : "NIL")")
            } else {
                print("[SC] 💚 Audio flowing normally (last: \(String(format: "%.1f", timeSinceLastAudio))s ago)")
            }
        }
    }

    func stop() async {
        stopFrameDropMonitoring()
        stopAudioDeviceMonitoring()
        
        try? await stream?.stopCapture()
        stream = nil
        converter = nil
        
        // Release handler references
        streamOutputHandler = nil
        videoOutputHandler = nil
        
        // Keep permission manager alive for reuse
        print("[SC] ⏹️ stopped")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {

        // 🚨 THREAD SAFETY: Process audio on dedicated queue to prevent SIGTERM
        processingQueue.async { [weak self] in
            self?.processAudioSample(sampleBuffer, of: type)
        }
    }
    
    /// 🚨 THREAD SAFE: Process audio sample on dedicated queue
    private func processAudioSample(_ sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 🚨 CRASH PREVENTION: Check if we're already processing
        guard !isProcessingAudio else {
            print("[SC] ⚠️ Skipping audio processing - already in progress")
            return
        }

        guard type == .audio else { 
            print("[SC] ⚠️ Received non-audio type: \(type)")
            return 
        }
        
        guard CMSampleBufferDataIsReady(sampleBuffer) else { 
            print("[SC] ⚠️ Sample buffer data not ready")
            return 
        }
        
        // 🚨 CRASH PREVENTION: Check error cooldown
        if let lastError = lastErrorTime, Date().timeIntervalSince(lastError) < errorCooldownInterval {
            if consecutiveErrors >= maxConsecutiveErrors {
                print("[SC] ⚠️ In error cooldown period, skipping processing")
                return
            }
        }
        
        // 🚨 CRASH PREVENTION: Set processing flag
        isProcessingAudio = true
        defer { isProcessingAudio = false }
        
        // 🎯 Update monitoring - we're receiving audio!
        lastAudioReceived = Date()

        // 🔍 Debug: Ses verisi detayları
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let durationSeconds = CMTimeGetSeconds(duration)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampSeconds = CMTimeGetSeconds(timestamp)
        
        print("[SC] 🎵 Audio received: \(sampleCount) samples, duration: \(String(format: "%.3f", durationSeconds))s, timestamp: \(String(format: "%.3f", timestampSeconds))s")

        // ✅ IMPROVED: Güvenli format çıkarma
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("[SC] ❌ Failed to get format description")
            return 
        }

        guard let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            print("[SC] ❌ Failed to get stream basic description")
            return 
        }
        
        guard let sourceFormat = AVAudioFormat(streamDescription: streamBasicDescription) else {
            print("[SC] ❌ Failed to create source format from stream description")
            return 
        }
        
        print("[SC] 🔍 Source format: \(sourceFormat)")
        print("[SC] 🔍 Target format: \(outFmt)")

        // ✅ IMPROVED: Converter yönetimi (MicCapture.swift gibi)
        if converter == nil || converter?.inputFormat != sourceFormat {
            print("[SC] 🔄 Creating new AVAudioConverter...")
            print("[SC] 🔍 Input format: \(sourceFormat)")
            print("[SC] 🎯 Output format: \(outFmt)")
            
            guard let newConverter = AVAudioConverter(from: sourceFormat, to: outFmt) else {
                handleProcessingError("Failed to create AVAudioConverter", details: [
                    "Source": "sampleRate=\(sourceFormat.sampleRate), channels=\(sourceFormat.channelCount), format=\(sourceFormat.commonFormat.rawValue)",
                    "Target": "sampleRate=\(outFmt.sampleRate), channels=\(outFmt.channelCount), format=\(outFmt.commonFormat.rawValue)"
                ])
            return
        }
        
            self.converter = newConverter
            print("[SC] ✅ AVAudioConverter created successfully")
        }
        
        guard let converter = self.converter else {
            print("[SC] ❌ Converter is nil after creation attempt")
            return
        }
        
        // ✅ SCREENCAPTUREKIT BYPASS: Skip complex buffer conversion, use direct raw data approach
        // ScreenCaptureKit CMSampleBuffer has problematic internal structure, let's extract raw data
        guard let rawPCMData = extractRawPCMData(from: sampleBuffer, sourceFormat: sourceFormat) else {
            handleProcessingError("Failed to extract raw PCM data from ScreenCaptureKit", details: [
                "Source format": "\(sourceFormat)",
                "Sample count": "\(sampleCount)",
                "Duration": "\(durationSeconds)s"
            ])
            return
        }
        
        print("[SC] ✅ Raw PCM data extracted: \(rawPCMData.count) bytes")

        // 🔊 🚨 THREAD SAFE: Send data on main queue to prevent callback issues
        if !rawPCMData.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onPCM16k?(rawPCMData)
            }
            print("[SC] 📤 Successfully sent \(rawPCMData.count) bytes to callback (48kHz mono Int16)")
            
            // ✅ CRASH PREVENTION: Reset error state on successful processing
            resetErrorState()
        } else {
            print("[SC] ⚠️ PCM data is empty, not sending to callback")
        }
    }

    // MARK: - SCStreamDelegate

    // Optional @objc method — uyarı olmaması için @objc şart
    @objc func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[SC] ❌ Stream stopped with error: \(error.localizedDescription)")
        print("[SC] 🔍 Error details: \(error)")
        
        // 🚨 CRASH PREVENTION: Reset state on stream error
        isProcessingAudio = false
        consecutiveErrors += 1
        lastErrorTime = Date()
        
        if consecutiveErrors >= maxConsecutiveErrors {
            print("[SC] 🚨 Maximum consecutive errors reached, entering cooldown period")
        }
    }
    
    // MARK: - Error Handling
    
    /// 🚨 CRASH PREVENTION: Centralized error handling
    private func handleProcessingError(_ message: String, details: [String: String] = [:]) {
        consecutiveErrors += 1
        lastErrorTime = Date()
        
        print("[SC] ❌ PROCESSING ERROR: \(message)")
        for (key, value) in details {
            print("[SC] 🔍 \(key): \(value)")
        }
        
        print("[SC] 🔍 Consecutive errors: \(consecutiveErrors)/\(maxConsecutiveErrors)")
        
        if consecutiveErrors >= maxConsecutiveErrors {
            print("[SC] 🚨 Maximum consecutive errors reached, entering cooldown period (\(errorCooldownInterval)s)")
        }
    }
    
    /// 🚨 CRASH PREVENTION: Reset error state on successful processing
    private func resetErrorState() {
        if consecutiveErrors > 0 {
            print("[SC] ✅ Processing successful, resetting error state (was: \(consecutiveErrors) errors)")
            consecutiveErrors = 0
            lastErrorTime = nil
        }
    }
    
    // MARK: - Audio Device Change Detection
    
    /// 🎧 Start monitoring audio output device changes
    private func startAudioDeviceMonitoring() {
        guard !isMonitoringDeviceChanges else {
            print("[SC] 🎧 Audio device monitoring already active")
            return
        }
        
        // Get current output device
        currentOutputDeviceID = getCurrentOutputDeviceID()
        print("[SC] 🎧 Current output device ID: \(currentOutputDeviceID)")
        
        // Set up property listener for default output device changes
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listenerProc: AudioObjectPropertyListenerProc = { (objectID, numberAddresses, addresses, clientData) -> OSStatus in
            guard let clientData = clientData else { return noErr }
            let systemAudioCapture = Unmanaged<SystemAudioCaptureSC>.fromOpaque(clientData).takeUnretainedValue()
            
            DispatchQueue.main.async {
                systemAudioCapture.handleAudioDeviceChange()
            }
            
            return noErr
        }
        
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        if status == noErr {
            audioDevicePropertyListener = listenerProc
            isMonitoringDeviceChanges = true
            print("[SC] ✅ Audio device change monitoring started successfully")
        } else {
            print("[SC] ❌ Failed to start audio device monitoring: OSStatus \(status)")
        }
    }
    
    /// 🎧 Stop monitoring audio output device changes
    private func stopAudioDeviceMonitoring() {
        guard isMonitoringDeviceChanges, let listener = audioDevicePropertyListener else {
            return
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listener,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        if status == noErr {
            print("[SC] ✅ Audio device monitoring stopped successfully")
        } else {
            print("[SC] ⚠️ Failed to stop audio device monitoring: OSStatus \(status)")
        }
        
        audioDevicePropertyListener = nil
        isMonitoringDeviceChanges = false
    }
    
    /// 🎧 Get current default output device ID
    private func getCurrentOutputDeviceID() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        if status != noErr {
            print("[SC] ⚠️ Failed to get current output device: OSStatus \(status)")
            return 0
        }
        
        return deviceID
    }
    
    /// 🎧 Get device name for logging
    private func getDeviceName(deviceID: AudioDeviceID) -> String {
        guard deviceID != 0 else { return "Unknown" }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        
        guard status == noErr, size > 0 else {
            return "Unknown Device (ID: \(deviceID))"
        }
        
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(size))
        defer { nameBuffer.deallocate() }
        
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, nameBuffer)
        
        guard status == noErr else {
            return "Unknown Device (ID: \(deviceID))"
        }
        
        return String(cString: nameBuffer)
    }
    
    /// 🎧 Handle audio output device change
    private func handleAudioDeviceChange() {
        let newDeviceID = getCurrentOutputDeviceID()
        
        guard newDeviceID != currentOutputDeviceID else {
            print("[SC] 🎧 Device change detected but same device ID, ignoring")
            return
        }
        
        let oldDeviceName = getDeviceName(deviceID: currentOutputDeviceID)
        let newDeviceName = getDeviceName(deviceID: newDeviceID)
        
        print("[SC] 🎧 ✨ AUDIO DEVICE CHANGED!")
        print("[SC] 🎧 Old device: \(oldDeviceName) (ID: \(currentOutputDeviceID))")
        print("[SC] 🎧 New device: \(newDeviceName) (ID: \(newDeviceID))")
        
        currentOutputDeviceID = newDeviceID
        
        // Automatically restart system audio capture to use new device
        Task {
            await restartSystemAudioCaptureForDeviceChange(newDeviceName: newDeviceName)
        }
    }
    
    /// 🎧 Restart system audio capture for device change
    private func restartSystemAudioCaptureForDeviceChange(newDeviceName: String) async {
        print("[SC] 🔄 Restarting system audio capture for device change to: \(newDeviceName)")
        
        // Stop current stream
        await stop()
        
        // Short delay to allow device to stabilize
        try? await Task.sleep(nanoseconds: 750_000_000) // 0.75 seconds
        
        // Restart with new device
        do {
            try await start()
            print("[SC] ✅ System audio capture successfully restarted for device: \(newDeviceName)")
        } catch {
            print("[SC] ❌ Failed to restart system audio capture for device change: \(error.localizedDescription)")
            
            // Try one more time after a longer delay
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            
            do {
                try await start()
                print("[SC] ✅ System audio capture restarted successfully on retry")
            } catch {
                print("[SC] ❌ System audio capture restart failed on retry: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - ScreenCaptureKit Raw Data Processing
    
    /// ✅ Extract raw PCM data directly from ScreenCaptureKit CMSampleBuffer
    /// This bypasses the problematic CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer
    private func extractRawPCMData(from sampleBuffer: CMSampleBuffer, sourceFormat: AVAudioFormat) -> Data? {
        // Get raw data buffer from CMSampleBuffer
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("[SC] ❌ No data buffer in CMSampleBuffer")
            return nil
        }
        
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard status == noErr, let dataPtr = dataPointer, totalLength > 0 else {
            print("[SC] ❌ Failed to get raw data pointer: OSStatus=\(status), length=\(totalLength)")
            return nil
        }
        
        print("[SC] 🔍 Raw data: \(totalLength) bytes, format: \(sourceFormat)")
        
        // Convert from ScreenCaptureKit format (2ch 48kHz Float32 deinterleaved) to target (1ch 48kHz Int16)
        return convertScreenCaptureKitAudio(
            rawData: dataPtr,
            length: totalLength,
            sourceFormat: sourceFormat,
            targetFormat: outFmt
        )
    }
    
    /// ✅ Convert ScreenCaptureKit audio format to Deepgram-compatible format
    private func convertScreenCaptureKitAudio(
        rawData: UnsafeMutablePointer<Int8>,
        length: Int,
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) -> Data? {
        
        // ScreenCaptureKit typically provides: 2ch, 48kHz, Float32, deinterleaved
        // We need: 1ch, 48kHz, Int16, interleaved
        
        let sourceChannels = Int(sourceFormat.channelCount) // Usually 2
        let targetChannels = Int(targetFormat.channelCount) // 1 (mono)
        let frameCount = length / (sourceChannels * MemoryLayout<Float32>.size)
        
        print("[SC] 🔍 Converting: \(sourceChannels)ch Float32 -> \(targetChannels)ch Int16, frames: \(frameCount)")
        
        guard frameCount > 0 else {
            print("[SC] ❌ Invalid frame count: \(frameCount)")
            return nil
        }
        
        // 🚨 THREAD SAFE: Cast raw data to Float32 array with proper bounds checking
        let floatElementCount = length / MemoryLayout<Float32>.size
        guard floatElementCount > 0 else {
            print("[SC] ❌ Invalid float element count: \(floatElementCount)")
            return nil
        }
        
        let floatData = rawData.withMemoryRebound(to: Float32.self, capacity: floatElementCount) { ptr in
            return ptr
        }
        
        var outputData = Data(capacity: frameCount * MemoryLayout<Int16>.size)
        
        // Convert deinterleaved stereo Float32 to mono Int16
        for frame in 0..<frameCount {
            var monoSample: Float32 = 0.0
            
            if sourceChannels == 2 {
                // Deinterleaved stereo: [L0, L1, L2, ...] [R0, R1, R2, ...]
                let leftSample = floatData[frame] // Left channel
                let rightSample = floatData[frame + frameCount] // Right channel (offset by frameCount)
                
                // Mix to mono (average of L+R)
                monoSample = (leftSample + rightSample) * 0.5
            } else {
                // Already mono
                monoSample = floatData[frame]
            }
            
            // Convert Float32 (-1.0 to 1.0) to Int16 (-32768 to 32767)
            let clampedSample = max(-1.0, min(1.0, monoSample))
            let int16Sample = Int16(clampedSample * 32767.0)
            
            // Add to output data (little-endian)
            let littleEndianSample = int16Sample.littleEndian
            let byte1 = UInt8(littleEndianSample & 0xFF)
            let byte2 = UInt8((littleEndianSample >> 8) & 0xFF)
            
            outputData.append(byte1)
            outputData.append(byte2)
        }
        
        print("[SC] ✅ Audio conversion successful: \(frameCount) frames -> \(outputData.count) bytes")
        return outputData
    }
}

// MARK: - Helpers

@available(macOS 13.0, *)
private extension CMSampleBuffer {
    /// 🚨 DEPRECATED: Güvenli olmayan makePCMBuffer - kullanmayın!
    /// makeReliablePCMBuffer kullanın
    func makePCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        print("[SC] ⚠️ DEPRECATED makePCMBuffer called - using makeReliablePCMBuffer instead")
        return makeReliablePCMBuffer(format: format)
    }
    
    /// ✅ SCREENCAPTUREKIT SPECIFIC: Direct PCM buffer creation for ScreenCaptureKit
    /// ScreenCaptureKit CMSampleBuffer has different internal structure
    func makeReliablePCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCapacity = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        
        // 🔍 Debug: Buffer bilgileri
        print("[SC] 🔍 Creating PCM buffer: frames=\(frameCapacity), format=\(format)")
        
        guard frameCapacity > 0 else {
            print("[SC] ❌ Invalid frame capacity: \(frameCapacity)")
            return nil
        }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            print("[SC] ❌ Failed to create AVAudioPCMBuffer")
            return nil
        }
        pcmBuffer.frameLength = frameCapacity
        
        // ✅ SCREENCAPTUREKIT FIX: Use CMSampleBufferGetAudioStreamPacketDescriptions approach
        // This bypasses the problematic CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(self) else {
            print("[SC] ❌ Failed to get CMSampleBuffer data buffer")
            return nil
        }
        
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard status == noErr, let dataPtr = dataPointer else {
            print("[SC] ❌ Failed to get data pointer: OSStatus=\(status)")
            return nil
        }
        
        print("[SC] 🔍 Data buffer: length=\(totalLength), lengthAtOffset=\(lengthAtOffset)")
        
        // ✅ Copy raw audio data directly to PCM buffer
        let audioBufferList = pcmBuffer.mutableAudioBufferList
        let buffer = audioBufferList.pointee.mBuffers
        
        guard let destData = buffer.mData else {
            print("[SC] ❌ PCM buffer data pointer is nil")
            return nil
        }
        
        // Calculate expected data size based on format
        let expectedDataSize = Int(frameCapacity) * Int(format.streamDescription.pointee.mBytesPerFrame)
        let actualCopySize = min(totalLength, expectedDataSize)
        
        print("[SC] 🔍 Copying \(actualCopySize) bytes (expected: \(expectedDataSize), available: \(totalLength))")
        
        // Copy data
        destData.copyMemory(from: dataPtr, byteCount: actualCopySize)
        audioBufferList.pointee.mBuffers.mDataByteSize = UInt32(actualCopySize)
        
        print("[SC] ✅ makeReliablePCMBuffer successful: \(frameCapacity) frames, \(actualCopySize) bytes")
        return pcmBuffer
    }
}
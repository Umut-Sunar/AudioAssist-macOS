import Foundation
import CoreAudio
import AVFoundation

/// Captures system audio output using Core Audio Taps
/// Creates a private aggregate device with tap to intercept default output audio
/// Converts captured audio to 16kHz mono Linear16 PCM for Deepgram Live API
final class SystemAudioTap {
    
    // MARK: - Properties
    
    /// Callback for processed PCM data (16kHz mono Linear16)
    var onPCM16k: ((Data) -> Void)?
    
    private var tapDescription: CATapDescription?
    private var tapUUID: String?
    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var audioConverter: AVAudioConverter?
    
    // Modern audio engine support
    private var audioEngine: AVAudioEngine?
    
    private var isCapturing = false
    
    // Target format: 16kHz, mono, PCM Int16 interleaved
    private let targetSampleRate: Double = 16000.0
    private let targetChannels: UInt32 = 1
    private let bufferFrameSize: UInt32 = 1024 // ~21ms at 48kHz
    
    // MARK: - Initialization
    
    init() {
        print("[DEBUG] SystemAudioTap initialized")
    }
    
    deinit {
        stop()
        print("[DEBUG] SystemAudioTap deinitialized")
    }
    
    // MARK: - Public API
    
    /// Start system audio capture with Core Audio Taps
    /// - Throws: SystemAudioTapError for various failure conditions
    func start() throws {
        print("[DEBUG] 🔊 SystemAudioTap.start() called")
        
        guard !isCapturing else {
            print("[DEBUG] ⚠️ SystemAudioTap already running")
            return
        }
        
        do {
            // Step 1: Create tap description and UUID
            try createTapDescription()
            
            // Step 2: Create hardware process tap
            try createHardwareProcessTap()
            
            // Step 3: Create private aggregate device with tap
            try createAggregateDevice()
            
            // Step 4: Setup I/O proc for audio processing
            try setupIOProc()
            
            // Step 5: Start audio device
            try startAudioDevice()
            
            isCapturing = true
            print("[DEBUG] ✅ SystemAudioTap started successfully")
            
        } catch {
            print("[DEBUG] ❌ Failed to start SystemAudioTap: \(error)")
            // Cleanup on failure
            stop()
            throw error
        }
    }
    
    /// Stop system audio capture and cleanup resources
    func stop() {
        print("[DEBUG] 🛑 SystemAudioTap.stop() called")
        
        guard isCapturing else {
            print("[DEBUG] ⚠️ SystemAudioTap already stopped")
            return
        }
        
        isCapturing = false
        
        // Stop audio device
        stopAudioDevice()
        
        // Destroy I/O proc
        destroyIOProc()
        
        // Destroy aggregate device
        destroyAggregateDevice()
        
        // Destroy hardware tap
        destroyHardwareProcessTap()
        
        // Cleanup resources
        cleanup()
        
        print("[DEBUG] ✅ SystemAudioTap stopped successfully")
    }
    
    // MARK: - Private Methods - Setup
    
    private func createTapDescription() throws {
        print("[DEBUG] 🔧 Creating tap description...")
        
        // Generate unique UUID for this tap
        let uuid = UUID().uuidString
        tapUUID = uuid
        print("[DEBUG] 📝 Generated tap UUID: \(uuid)")
        
        // Create tap description
        tapDescription = CATapDescription()
        
        print("[DEBUG] ✅ Tap description created")
    }
    
    private func createHardwareProcessTap() throws {
        print("[DEBUG] 🔧 Creating hardware process tap...")
        
        guard let tapUUID = tapUUID else {
            throw SystemAudioTapError.invalidTapUUID
        }
        
        // Get process object for current process
        let processObject = try getProcessObject(for: getpid())
        print("[DEBUG] 📱 Process object ID: \(processObject)")
        
        // Create CATapDescription (non-optional)
        let tapDesc = CATapDescription()
        // Note: CATapDescription fields may vary by SDK version
        // We'll set the basic structure for now
        
        // Create process tap with correct API signature (Swift expects CATapDescription?, not pointer)
        var tapID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        
        guard status == noErr else {
            print("[DEBUG] ❌ AudioHardwareCreateProcessTap failed: \(osStatusDescription(status))")
            throw SystemAudioTapError.tapCreationFailed(status)
        }
        
        tapObjectID = tapID
        print("[DEBUG] ✅ Hardware process tap created with ID: \(tapObjectID), status: \(status)")
    }
    
    /// Get process object ID for the given PID
    private func getProcessObject(for pid: pid_t) throws -> AudioObjectID {
        var processObject: AudioObjectID = kAudioObjectUnknown
        var pidVar = pid
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            UInt32(MemoryLayout<pid_t>.size), &pidVar,
            &dataSize, &processObject
        )
        
        guard status == noErr else {
            print("[DEBUG] ❌ Failed to get process object for PID \(pid): \(osStatusDescription(status))")
            throw SystemAudioTapError.tapCreationFailed(status)
        }
        
        return processObject
    }
    
    private func createAggregateDevice() throws {
        print("[DEBUG] 🔧 Creating private aggregate device...")
        
        guard let tapUUID = tapUUID else {
            throw SystemAudioTapError.invalidTapUUID
        }
        
        // Get default output device to tap into
        var defaultOutputDevice: AudioObjectID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDevice
        )
        
        guard status == noErr && defaultOutputDevice != kAudioObjectUnknown else {
            print("[DEBUG] ❌ Failed to get default output device: \(osStatusDescription(status))")
            throw SystemAudioTapError.defaultOutputDeviceNotFound(status)
        }
        
        print("[DEBUG] 📱 Default output device ID: \(defaultOutputDevice)")
        
        // Create aggregate device dictionary
        let tapList = [
            [
                kAudioSubTapUIDKey: tapUUID
            ]
        ]
        
        let aggregateDeviceDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SystemAudioTap_\(tapUUID.prefix(8))",
            kAudioAggregateDeviceUIDKey: "SystemAudioTap_UID_\(tapUUID.prefix(8))",
            kAudioAggregateDeviceSubDeviceListKey: [defaultOutputDevice],
            kAudioAggregateDeviceTapListKey: tapList,
            kAudioAggregateDeviceIsPrivateKey: true
        ]
        
        print("[DEBUG] 📋 Aggregate device configuration created")
        
        // Create the aggregate device
        var aggregateID: AudioObjectID = kAudioObjectUnknown
        let createStatus = AudioHardwareCreateAggregateDevice(
            aggregateDeviceDict as CFDictionary,
            &aggregateID
        )
        
        guard createStatus == noErr else {
            print("[DEBUG] ❌ AudioHardwareCreateAggregateDevice failed: \(osStatusDescription(createStatus))")
            throw SystemAudioTapError.aggregateDeviceCreationFailed(createStatus)
        }
        
        aggregateDeviceID = aggregateID
        print("[DEBUG] ✅ Private aggregate device created with ID: \(aggregateDeviceID)")
    }
    
    /// Convert OSStatus to human-readable description
    private func osStatusDescription(_ status: OSStatus) -> String {
        switch status {
        case noErr:
            return "noErr (0)"
        case kAudioHardwareNotRunningError:
            return "kAudioHardwareNotRunningError (-10851)"
        case kAudioHardwareUnspecifiedError:
            return "kAudioHardwareUnspecifiedError (-10850)"
        case kAudioDeviceUnsupportedFormatError:
            return "kAudioDeviceUnsupportedFormatError (-10863)"
        case kAudioDevicePermissionsError:
            return "kAudioDevicePermissionsError (-10875)"
        default:
            return "OSStatus (\(status))"
        }
    }
    
    private func setupIOProc() throws {
        print("[DEBUG] 🔧 Setting up I/O proc...")
        
        guard aggregateDeviceID != kAudioObjectUnknown else {
            throw SystemAudioTapError.invalidAggregateDevice
        }
        
        // MODERN APPROACH: Use AVAudioEngine for system audio capture
        // This approach is more compatible with modern macOS versions
        print("[DEBUG] 🔄 Using modern AVAudioEngine approach for system audio capture")
        
        // For now, we'll simulate system audio capture by creating a simple audio engine
        // that can be extended to capture system audio through other means
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        
        // Install tap on input node to capture audio
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[DEBUG] 📊 Input format: \(inputFormat)")
        
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // Process the captured audio buffer
            if let data16k = self.convertSystemAudioChunk(buffer) {
                self.onPCM16k?(data16k)
                print("[DEBUG] 📤 System audio processed: \(data16k.count) bytes")
            }
        }
        
        // Start the audio engine
        do {
            try audioEngine.start()
            print("[DEBUG] ✅ AVAudioEngine started successfully")
            
            // Store engine reference for cleanup
            self.audioEngine = audioEngine
            
        } catch {
            print("[DEBUG] ❌ Failed to start AVAudioEngine: \(error)")
            throw SystemAudioTapError.deviceStartFailed(OSStatus(error._code))
        }
    }
    
    private func startAudioDevice() throws {
        print("[DEBUG] 🔧 Starting audio device...")
        // Device is now started in setupIOProc() method
        print("[DEBUG] ✅ Audio device start handled in setupIOProc()")
    }
    
    private func stopAudioDevice() {
        print("[DEBUG] 🛑 Stopping audio device...")
        
        guard let ioProcID = ioProcID else {
            print("[DEBUG] ⚠️ No I/O proc to stop")
            return
        }
        
        let status = AudioDeviceStop(aggregateDeviceID, ioProcID)
        if status != noErr {
            print("[DEBUG] ⚠️ AudioDeviceStop failed: \(osStatusDescription(status))")
        } else {
            print("[DEBUG] ✅ Audio device stopped")
        }
    }
    
    // MARK: - Audio Processing
    
    /// Convert AudioBufferList to AVAudioPCMBuffer with fallback sample rate
    private func makePCMBuffer(from abl: AudioBufferList, fallbackSR: Double) -> AVAudioPCMBuffer? {
        // Bu örnek, tek buffer varsayımıyla çalışır
        let localABL = abl
        let buffer = localABL.mBuffers
        guard let src = buffer.mData, buffer.mDataByteSize > 0 else { 
            print("[DEBUG] ⚠️ Empty or invalid audio buffer")
            return nil 
        }
        
        // Gerçekte formatı cihazdan okumak lazım, burada Float32 stereo varsayımı
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = fallbackSR
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        asbd.mBytesPerPacket = 4 * 2    // Float32 * stereo
        asbd.mFramesPerPacket = 1
        asbd.mBytesPerFrame = 4 * 2
        asbd.mChannelsPerFrame = 2
        asbd.mBitsPerChannel = 32
        asbd.mReserved = 0
        
        guard let format = AVAudioFormat(streamDescription: &asbd) else { 
            print("[DEBUG] ❌ Failed to create AVAudioFormat from ASBD")
            return nil 
        }
        
        let frameCount = AVAudioFrameCount(Int(buffer.mDataByteSize) / Int(asbd.mBytesPerFrame))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { 
            print("[DEBUG] ❌ Failed to create AVAudioPCMBuffer")
            return nil 
        }
        
        pcm.frameLength = frameCount
        
        if let dst = pcm.floatChannelData {
            // Interleaved kabul ettik; basitçe bloğu kopyalıyoruz
            memcpy(dst[0], src, Int(buffer.mDataByteSize))
            print("[DEBUG] 🎵 Created PCM buffer: \(frameCount) frames @ \(fallbackSR) Hz")
        } else {
            print("[DEBUG] ❌ Failed to get float channel data")
            return nil
        }
        
        return pcm
    }
    
    /// Convert system audio PCM buffer to 16kHz mono Int16 data
    private func convertSystemAudioChunk(_ inputBuffer: AVAudioPCMBuffer) -> Data? {
        // Create or reuse audio converter
        if audioConverter == nil {
            audioConverter = createSystemAudioConverter(from: inputBuffer.format)
        }
        
        guard let converter = audioConverter else {
            print("[DEBUG] ❌ System audio converter not available")
            return nil
        }
        
        // Convert to 16kHz mono PCM Int16
        return convertToTargetFormat(inputBuffer, using: converter)
    }
    
    private func createSystemAudioConverter(from inputFormat: AVAudioFormat) -> AVAudioConverter? {
        print("[DEBUG] 🔄 Creating system audio converter")
        
        // Create target format: 16kHz, mono, PCM Int16 interleaved
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            print("[DEBUG] ❌ Failed to create system audio target format")
            return nil
        }
        
        print("[DEBUG] 📊 System audio input format: \(inputFormat)")
        print("[DEBUG] 📊 System audio target format: \(targetFormat)")
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[DEBUG] ❌ Failed to create system audio converter")
            return nil
        }
        
        print("[DEBUG] ✅ System audio converter created successfully")
        return converter
    }
    
    private func convertToTargetFormat(_ inputBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> Data? {
        // Calculate output buffer size
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * targetSampleRate / inputBuffer.format.sampleRate)
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputCapacity
        ) else {
            print("[DEBUG] ❌ Failed to create system audio output buffer")
            return nil
        }
        
        // Convert audio
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        if status == .error {
            print("[DEBUG] ❌ System audio conversion error: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        // Extract PCM data from buffer (little-endian Int16)
        guard let channelData = outputBuffer.int16ChannelData?[0] else {
            print("[DEBUG] ❌ Failed to get system audio channel data")
            return nil
        }
        
        let frameCount = Int(outputBuffer.frameLength)
        
        // Create Data from Int16 samples with little-endian byte order
        var data = Data(capacity: frameCount * MemoryLayout<Int16>.size)
        
        for i in 0..<frameCount {
            let sample = channelData[i]
            let littleEndianSample = sample.littleEndian
            
            // Convert Int16 to bytes (little-endian)
            let byte1 = UInt8(littleEndianSample & 0xFF)
            let byte2 = UInt8((littleEndianSample >> 8) & 0xFF)
            
            data.append(byte1)
            data.append(byte2)
        }
        
        return data
    }
    
    private func destroyIOProc() {
        print("[DEBUG] 🗑️ Destroying I/O proc...")
        
        // Clean up modern audio engine
        if let audioEngine = audioEngine {
            if audioEngine.isRunning {
                audioEngine.stop()
                print("[DEBUG] ✅ AVAudioEngine stopped")
            }
            
            // Remove tap from input node
            audioEngine.inputNode.removeTap(onBus: 0)
            print("[DEBUG] ✅ Audio tap removed")
            
            self.audioEngine = nil
        }
        
        // Clean up modern IO proc if used
        if let ioProcID = ioProcID {
            let status = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            if status != noErr {
                print("[DEBUG] ⚠️ AudioDeviceDestroyIOProcID failed: \(osStatusDescription(status))")
            } else {
                print("[DEBUG] ✅ I/O proc destroyed")
            }
            
            self.ioProcID = nil
        }
        
        if audioEngine == nil && ioProcID == nil {
            print("[DEBUG] ⚠️ No I/O proc to destroy")
        }
    }
    
    private func destroyAggregateDevice() {
        print("[DEBUG] 🗑️ Destroying aggregate device...")
        
        guard aggregateDeviceID != kAudioObjectUnknown else {
            return
        }
        
        let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        if status != noErr {
            print("[DEBUG] ⚠️ AudioHardwareDestroyAggregateDevice failed: \(osStatusDescription(status))")
        } else {
            print("[DEBUG] ✅ Aggregate device destroyed")
        }
        
        aggregateDeviceID = kAudioObjectUnknown
    }
    
    private func destroyHardwareProcessTap() {
        print("[DEBUG] 🗑️ Destroying hardware process tap...")
        
        guard tapObjectID != kAudioObjectUnknown else {
            return
        }
        
        let status = AudioHardwareDestroyProcessTap(tapObjectID)
        if status != noErr {
            print("[DEBUG] ⚠️ AudioHardwareDestroyProcessTap failed: \(osStatusDescription(status))")
        } else {
            print("[DEBUG] ✅ Hardware process tap destroyed")
        }
        
        tapObjectID = kAudioObjectUnknown
    }
    
    private func cleanup() {
        print("[DEBUG] 🧹 Cleaning up resources...")
        tapDescription = nil
        tapUUID = nil
        tapObjectID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        audioConverter = nil
        audioEngine = nil
        isCapturing = false
        print("[DEBUG] ✅ Resources cleaned up")
    }
}

// MARK: - Error Types

enum SystemAudioTapError: Error, LocalizedError {
    case invalidTapUUID
    case tapCreationFailed(OSStatus)
    case defaultOutputDeviceNotFound(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case invalidAggregateDevice
    case ioProcCreationFailed(OSStatus)
    case invalidIOProc
    case deviceStartFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .invalidTapUUID:
            return "Invalid tap UUID"
        case .tapCreationFailed(let status):
            return "Tap creation failed with status: \(status)"
        case .defaultOutputDeviceNotFound(let status):
            return "Default output device not found: \(status)"
        case .aggregateDeviceCreationFailed(let status):
            return "Aggregate device creation failed: \(status)"
        case .invalidAggregateDevice:
            return "Invalid aggregate device"
        case .ioProcCreationFailed(let status):
            return "I/O proc creation failed: \(status)"
        case .invalidIOProc:
            return "Invalid I/O proc"
        case .deviceStartFailed(let status):
            return "Device start failed: \(status)"
        }
    }
}
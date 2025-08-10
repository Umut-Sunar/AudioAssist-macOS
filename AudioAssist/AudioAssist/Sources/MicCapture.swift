import AVFoundation
import CoreAudio

/// Captures microphone audio input using AVAudioEngine
/// Handles device changes (AirPods connect/disconnect) with pop-free transitions
/// Converts audio to 16kHz mono Linear16 PCM for Deepgram Live API
class MicCapture {
    
    // MARK: - Properties
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioConverter: AVAudioConverter?
    private var onPCMCallback: ((Data) -> Void)?
    
    private var isCapturing = false
    
    // Target format: 48kHz, mono, PCM Int16 interleaved (match successful project)
    private let targetSampleRate: Double = 48000.0
    private let targetChannels: UInt32 = 1
    private let bufferSize: UInt32 = 2048
    
    // MARK: - Initialization
    
    init() {
        print("[DEBUG] MicCapture initialized")
        // No audio session setup needed on macOS
    }
    
    deinit {
        stop()
        print("[DEBUG] MicCapture deinitialized")
    }
    
    // MARK: - Public API
    
    /// Start microphone capture with PCM callback
    /// - Parameter onPCM16k: Callback that receives 48kHz mono Linear16 PCM data
    func start(onPCM16k: @escaping (Data) -> Void) {
        print("[DEBUG] 🎤 MicCapture.start() called")
        
        guard !isCapturing else {
            print("[DEBUG] ⚠️ MicCapture already running")
            return
        }
        
        // Store callback
        self.onPCMCallback = onPCM16k
        
        // On macOS, directly start audio capture (no permission dialog needed for microphone in non-sandboxed apps)
        startAudioCapture()
    }
    
    /// Stop microphone capture
    func stop() {
        print("[DEBUG] 🛑 MicCapture.stop() called")
        
        guard isCapturing else {
            print("[DEBUG] ⚠️ MicCapture already stopped")
            return
        }
        
        stopAudioCapture()
    }
    
    // MARK: - Private Methods
    
    private func startAudioCapture() {
        print("[DEBUG] 🚀 Starting audio capture")
        
        // Create audio engine
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else {
            print("[DEBUG] ❌ Failed to create AVAudioEngine")
            return
        }
        
        // Get input node
        inputNode = audioEngine.inputNode
        
        guard let inputNode = inputNode else {
            print("[DEBUG] ❌ Failed to get input node")
            return
        }
        
        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[DEBUG] 📊 Input format: \(inputFormat)")
        print("[DEBUG] 📊 Input sample rate: \(inputFormat.sampleRate) Hz")
        print("[DEBUG] 📊 Input channels: \(inputFormat.channelCount)")
        print("[DEBUG] 📊 Input format description: \(inputFormat.formatDescription)")
        
        // Create converter
        audioConverter = makeConverter(from: inputFormat)
        
        guard audioConverter != nil else {
            print("[DEBUG] ❌ Failed to create audio converter")
            return
        }
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, at: time)
        }
        
        // Start audio engine
        do {
            try audioEngine.start()
            isCapturing = true
            print("[DEBUG] ✅ Audio engine started successfully")
            print("[DEBUG] 🎤 Microphone capture is now active")
        } catch {
            print("[DEBUG] ❌ Failed to start audio engine: \(error.localizedDescription)")
            cleanup()
        }
    }
    
    private func stopAudioCapture() {
        print("[DEBUG] 🛑 Stopping audio capture")
        
        // Remove tap
        inputNode?.removeTap(onBus: 0)
        
        // Stop audio engine
        audioEngine?.stop()
        
        cleanup()
        
        print("[DEBUG] ✅ Audio capture stopped")
    }
    
    private func cleanup() {
        isCapturing = false
        audioEngine = nil
        inputNode = nil
        audioConverter = nil
        onPCMCallback = nil
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let audioConverter = audioConverter else {
            print("[DEBUG] ⚠️ Audio converter not available")
            return
        }
        
        print("[DEBUG] 🎵 Processing audio buffer: \(buffer.frameLength) frames")
        
        // Convert audio chunk to 48kHz mono PCM Int16
        if let pcmData = convertChunk(buffer, using: audioConverter) {
            // Debug PCM data
            if pcmData.count >= 4 {
                let samples = pcmData.withUnsafeBytes { bytes in
                    Array(bytes.bindMemory(to: Int16.self).prefix(2))
                }
                print("[DEBUG] 📊 Converted PCM Preview: \(samples) (first 2 samples)")
            }
            
            // Send PCM data via callback
            onPCMCallback?(pcmData)
            
            print("[DEBUG] 📤 Processed audio chunk: \(pcmData.count) bytes (\(pcmData.count / 2) samples)")
        } else {
            print("[DEBUG] ⚠️ Failed to convert audio chunk")
        }
    }
    
    // MARK: - Helper Functions
    
    /// Creates an AVAudioConverter from input format to target format (48kHz mono PCM Int16)
    /// - Parameter inputFormat: The source audio format
    /// - Returns: Configured AVAudioConverter or nil if creation fails
    private func makeConverter(from inputFormat: AVAudioFormat) -> AVAudioConverter? {
        print("[DEBUG] 🔄 Creating audio converter")
        
        // Create target format: 48kHz, mono, PCM Int16 interleaved
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            print("[DEBUG] ❌ Failed to create target audio format")
            return nil
        }
        
        print("[DEBUG] 📊 Target format: \(targetFormat)")
        print("[DEBUG] 📊 Target sample rate: \(targetFormat.sampleRate) Hz")
        print("[DEBUG] 📊 Target channels: \(targetFormat.channelCount)")
        print("[DEBUG] 📊 Target format description: \(targetFormat.formatDescription)")
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[DEBUG] ❌ Failed to create AVAudioConverter")
            return nil
        }
        
        print("[DEBUG] ✅ Audio converter created successfully")
        return converter
    }
    
    /// Converts an audio buffer chunk using the provided converter
    /// - Parameters:
    ///   - buffer: Input audio buffer
    ///   - converter: AVAudioConverter to use for conversion
    /// - Returns: Converted PCM data as Data or nil if conversion fails
    private func convertChunk(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> Data? {
        // Calculate output buffer size
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate)
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputCapacity
        ) else {
            print("[DEBUG] ❌ Failed to create output buffer")
            return nil
        }
        
        // Convert audio
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error {
            print("[DEBUG] ❌ Audio conversion error: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        // Extract PCM data from buffer
        guard let channelData = outputBuffer.int16ChannelData?[0] else {
            print("[DEBUG] ❌ Failed to get channel data")
            return nil
        }
        
        let frameCount = Int(outputBuffer.frameLength)
        
        // Create Data from Int16 samples
        var data = Data(capacity: frameCount * MemoryLayout<Int16>.size)
        
        // Ensure little-endian byte order for Deepgram compatibility
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
}

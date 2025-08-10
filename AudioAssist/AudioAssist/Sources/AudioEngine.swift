import AVFoundation
import CoreAudio

/// Events from AudioEngine to UI
enum AudioEngineEvent {
    case connected
    case disconnected
    case error(Error)
    case results(String) // JSON transcript results
    case metadata(String) // JSON metadata
    case finalized(String) // JSON from finalize command
}

/// Coordinates audio capture from multiple sources and processing pipeline
/// Manages microphone + system audio capture, mixing, and streaming to Deepgram
class AudioEngine {
    
    // MARK: - Properties
    
    private let deepgramClient: DeepgramClient
    private let micCapture: MicCapture
    private let systemAudioCapture: SystemAudioCaptureSC

    private var isRunning = false
    
    // Event callback for UI updates
    var onEvent: ((AudioEngineEvent) -> Void)?
    
    // MARK: - Initialization
    
    init(config: DGConfig) {
        print("[DEBUG] AudioEngine initialized with config")
        
        // Initialize components
        self.deepgramClient = DeepgramClient()
        self.micCapture = MicCapture()
        self.systemAudioCapture = SystemAudioCaptureSC()
        
        setupDeepgramEvents()
    }
    
    // MARK: - Public API
    
    /// Start audio capture and Deepgram connection
    func start() {
        print("[DEBUG] 🚀 AudioEngine.start() called")
        
        guard !isRunning else {
            print("[DEBUG] ⚠️ AudioEngine already running")
            return
        }
        
        isRunning = true
        
        // Connect to Deepgram first
        print("[DEBUG] 🌐 Connecting to Deepgram...")
        deepgramClient.connect { [weak self] event in
            self?.handleDeepgramEvent(event)
        }
        
        // Start microphone capture
        print("[DEBUG] 🎤 Starting microphone capture...")
        micCapture.start { [weak self] pcmData in
            print("[DEBUG] 🎤 Mic PCM data: \(pcmData.count) bytes (samples: \(pcmData.count/2))")
            // Send microphone PCM data to Deepgram
            self?.deepgramClient.sendPCM(pcmData)
        }
        
        // Start system audio capture with ScreenCaptureKit
        print("[DEBUG] 🔊 Starting system audio capture...")
        Task {
            if #available(macOS 13.0, *) {
                do {
                    // Set up callback before starting
                    systemAudioCapture.onPCM16k = { [weak self] pcmData in
                        print("[DEBUG] 🔊 System PCM data: \(pcmData.count) bytes (48kHz mono Int16: \(pcmData.count/2) samples)")
                        // Send system audio PCM data to Deepgram
                        self?.deepgramClient.sendPCM(pcmData)
                    }
                    
                    print("[DEBUG] 🔧 SystemAudioCapture callback set")
                    
                    try await systemAudioCapture.start()
                    print("[DEBUG] ✅ System audio capture started successfully")
                    
                } catch {
                    print("[DEBUG] ❌ Failed to start system audio capture: \(error)")
                    print("[DEBUG] 🔍 Error type: \(type(of: error))")
                    print("[DEBUG] 🔍 Error description: \(error.localizedDescription)")
                    
                    if let nsError = error as NSError? {
                        print("[DEBUG] 🔍 Error domain: \(nsError.domain)")
                        print("[DEBUG] 🔍 Error code: \(nsError.code)")
                        print("[DEBUG] 🔍 Error userInfo: \(nsError.userInfo)")
                    }
                    // Continue with microphone-only mode
                }
            } else {
                print("[DEBUG] ⚠️ ScreenCaptureKit requires macOS 13.0+")
            }
        }
        
        print("[DEBUG] ✅ AudioEngine initialization completed")
    }
    
    /// Stop audio capture and close connections
    func stop() {
        print("[DEBUG] 🛑 AudioEngine.stop() called")
        
        guard isRunning else {
            print("[DEBUG] ⚠️ AudioEngine already stopped")
            return
        }
        
        isRunning = false
        
        // Stop microphone capture
        print("[DEBUG] 🎤 Stopping microphone capture...")
        micCapture.stop()
        print("[DEBUG] ✅ Microphone capture stopped")
        
        // Stop system audio capture
        if #available(macOS 13.0, *) {
            print("[DEBUG] 🔊 Stopping system audio capture...")
            Task {
                await systemAudioCapture.stop()
                print("[DEBUG] ✅ System audio capture stopped")
            }
        }
        
        // Close Deepgram connection
        print("[DEBUG] 🌐 Closing Deepgram connection...")
        deepgramClient.closeSocket()
        print("[DEBUG] ✅ Deepgram connection closed")
        
        print("[DEBUG] ✅ AudioEngine stopped successfully")
    }
    
    // MARK: - Private Methods
    
    private func setupDeepgramEvents() {
        // Configure Deepgram event handling
        // Events will be handled in handleDeepgramEvent
    }
    
    private func handleDeepgramEvent(_ event: DGEvent) {
        print("[DEBUG] AudioEngine received Deepgram event: \(event.description)")
        
        // Convert DGEvent to AudioEngineEvent and forward to UI
        switch event {
        case .connected:
            onEvent?(.connected)
            
        case .disconnected:
            onEvent?(.disconnected)
            
        case .error(let message):
            let error = NSError(domain: "DeepgramError", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            onEvent?(.error(error))
            
        case .results(let json):
            onEvent?(.results(json))
            
        case .metadata(let json):
            onEvent?(.metadata(json))
            
        case .fromFinalize(let json):
            onEvent?(.finalized(json))
        }
    }
}

/// Helper function to create Deepgram configuration
func makeDGConfig() -> DGConfig {
    let apiKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"] ?? ""
    return DGConfig(
        apiKey: apiKey,
        sampleRate: 48000,  // Match successful project: 48kHz
        channels: 1,
        multichannel: false,
        model: "nova-2",    // Use nova-2 for Turkish support
        language: "tr",
        interim: true,
        endpointingMs: 300,
        punctuate: true,
        smartFormat: true,
        diarize: true       // Enable diarization like successful project
    )
}

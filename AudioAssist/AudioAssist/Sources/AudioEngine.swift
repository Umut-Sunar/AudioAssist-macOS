import AVFoundation
import CoreAudio

/// Events from AudioEngine to UI
enum AudioEngineEvent {
    case microphoneConnected
    case systemAudioConnected
    case microphoneDisconnected
    case systemAudioDisconnected
    case error(Error, source: AudioSourceType)
    case results(String, source: AudioSourceType) // JSON transcript results
    case metadata(String, source: AudioSourceType) // JSON metadata
    case finalized(String, source: AudioSourceType) // JSON from finalize command
}

/// Coordinates audio capture from multiple sources and processing pipeline
/// Manages microphone + system audio capture with dual Deepgram connections
class AudioEngine {
    
    // MARK: - Properties
    
    private let microphoneClient: DeepgramClient
    private let systemAudioClient: DeepgramClient
    private let micCapture: MicCapture
    private let systemAudioCapture: SystemAudioCaptureSC

    private var isRunning = false
    
    // Event callback for UI updates
    var onEvent: ((AudioEngineEvent) -> Void)?
    
    // MARK: - Initialization
    
    init(config: DGConfig) {
        print("[DEBUG] AudioEngine initialized with dual WebSocket config")
        
        // Create separate configs for each source
        let micConfig = config.withSource(.microphone)
        let sysConfig = config.withSource(.systemAudio)
        
        // Initialize dual Deepgram clients
        self.microphoneClient = DeepgramClient(config: micConfig, sourceType: .microphone)
        self.systemAudioClient = DeepgramClient(config: sysConfig, sourceType: .systemAudio)
        
        // Initialize audio capture components
        self.micCapture = MicCapture()
        self.systemAudioCapture = SystemAudioCaptureSC()
        
        setupDeepgramEvents()
    }
    
    deinit {
        print("[DEBUG] 🔧 AudioEngine deinitializing...")
        
        // Stop all streams safely
        if isRunning {
            stop()
        }
        
        // Clean up references
        onEvent = nil
        
        print("[DEBUG] 🔧 AudioEngine deinitialized safely")
    }
    
    // MARK: - Public API
    
    /// Start audio capture and dual Deepgram connections
    func start() {
        print("[DEBUG] 🚀 AudioEngine.start() called - Dual WebSocket mode")
        
        guard !isRunning else {
            print("[DEBUG] ⚠️ AudioEngine already running")
            return
        }
        
        // Check API key before starting
        if !APIKeyManager.hasValidAPIKey() {
            print("[DEBUG] ❌ Cannot start AudioEngine: API key missing")
            let status = APIKeyManager.getAPIKeyStatus()
            print("[DEBUG] 🔍 API Key Status: source=\(status.source), key=\(status.maskedKey)")
            onEvent?(.error(NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "DEEPGRAM_API_KEY is missing"]), source: .microphone))
            return
        }
        
        isRunning = true
        
        // Start both streams independently with error handling
        do {
            startMicrophoneStream()
            startSystemAudioStream()
            print("[DEBUG] ✅ AudioEngine dual stream initialization completed")
        } catch {
            print("[DEBUG] ❌ Error starting audio streams: \(error)")
            isRunning = false
            onEvent?(.error(error as NSError, source: .microphone))
        }
    }
    
    /// Start microphone stream with dedicated Deepgram connection
    private func startMicrophoneStream() {
        print("[DEBUG] 🎤 Starting microphone stream...")
        
        // Connect microphone client to Deepgram
        microphoneClient.connect { [weak self] event in
            self?.handleMicrophoneEvent(event)
        }
        
        // Start microphone capture
        micCapture.start { [weak self] pcmData in
            print("[DEBUG] 🎤 Mic PCM data: \(pcmData.count) bytes (samples: \(pcmData.count/2))")
            // Send microphone PCM data to dedicated Deepgram connection
            self?.microphoneClient.sendPCM(pcmData)
        }
    }
    
    /// Start system audio stream with dedicated Deepgram connection
    private func startSystemAudioStream() {
        print("[DEBUG] 🔊 Starting system audio stream...")
        
        // Connect system audio client to Deepgram
        systemAudioClient.connect { [weak self] event in
            self?.handleSystemAudioEvent(event)
        }
        
        // Start system audio capture with ScreenCaptureKit
        Task {
            if #available(macOS 13.0, *) {
                do {
                    // Set up callback before starting
                    systemAudioCapture.onPCM16k = { [weak self] pcmData in
                        print("[DEBUG] 🔊 System PCM data: \(pcmData.count) bytes (48kHz mono Int16: \(pcmData.count/2) samples)")
                        // Send system audio PCM data to dedicated Deepgram connection
                        self?.systemAudioClient.sendPCM(pcmData)
                    }
                    
                    print("[DEBUG] 🔧 SystemAudioCapture callback set")
                    print("[DEBUG] 🎧 Automatic audio device change detection is built-in to SystemAudioCapture")
                    
                    try await systemAudioCapture.start()
                    print("[DEBUG] ✅ System audio capture started successfully")
                    print("[DEBUG] 🎧 System will automatically restart when audio output device changes (e.g., AirPods)")
                    
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
    }
    
    /// Stop audio capture and close dual connections
    func stop() {
        print("[DEBUG] 🛑 AudioEngine.stop() called - Dual WebSocket mode")
        
        guard isRunning else {
            print("[DEBUG] ⚠️ AudioEngine already stopped")
            return
        }
        
        isRunning = false
        
        // Stop microphone capture and connection - safely
        print("[DEBUG] 🎤 Stopping microphone stream...")
        do {
            micCapture.stop()
            microphoneClient.closeSocket()
            print("[DEBUG] ✅ Microphone stream stopped")
        } catch {
            print("[DEBUG] ⚠️ Error stopping microphone: \(error)")
        }
        
        // Stop system audio capture and connection - safely
        if #available(macOS 13.0, *) {
            print("[DEBUG] 🔊 Stopping system audio stream...")
            Task { @MainActor in
                do {
                    await systemAudioCapture.stop()
                    systemAudioClient.closeSocket()
                    print("[DEBUG] ✅ System audio stream stopped")
                } catch {
                    print("[DEBUG] ⚠️ Error stopping system audio: \(error)")
                }
            }
        }
        
        print("[DEBUG] ✅ AudioEngine dual streams stopped successfully")
    }
    
    // MARK: - Private Methods
    
    private func setupDeepgramEvents() {
        // Dual stream event handling is configured in startMicrophoneStream() and startSystemAudioStream()
        print("[DEBUG] AudioEngine dual stream event handling configured")
    }
    
    /// Handle microphone Deepgram events
    private func handleMicrophoneEvent(_ event: DGEvent) {
        print("[DEBUG] AudioEngine received microphone event: \(event.description)")
        
        // Convert DGEvent to AudioEngineEvent and forward to UI
        switch event {
        case .connected(let source):
            onEvent?(.microphoneConnected)
            
        case .disconnected(let source):
            onEvent?(.microphoneDisconnected)
            
        case .error(let message, let source):
            let error = NSError(domain: "DeepgramError", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            onEvent?(.error(error, source: source))
            
        case .results(let json, let source):
            onEvent?(.results(json, source: source))
            
        case .metadata(let json, let source):
            onEvent?(.metadata(json, source: source))
            
        case .fromFinalize(let json, let source):
            onEvent?(.finalized(json, source: source))
        }
    }
    
    /// Handle system audio Deepgram events
    private func handleSystemAudioEvent(_ event: DGEvent) {
        print("[DEBUG] AudioEngine received system audio event: \(event.description)")
        
        // Convert DGEvent to AudioEngineEvent and forward to UI
        switch event {
        case .connected(let source):
            onEvent?(.systemAudioConnected)
            
        case .disconnected(let source):
            onEvent?(.systemAudioDisconnected)
            
        case .error(let message, let source):
            let error = NSError(domain: "DeepgramError", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            onEvent?(.error(error, source: source))
            
        case .results(let json, let source):
            onEvent?(.results(json, source: source))
            
        case .metadata(let json, let source):
            onEvent?(.metadata(json, source: source))
            
        case .fromFinalize(let json, let source):
            onEvent?(.finalized(json, source: source))
        }
    }
}

/// Helper function to create Deepgram configuration
func makeDGConfig() -> DGConfig {
    let apiKey = APIKeyManager.getDeepgramAPIKey()
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

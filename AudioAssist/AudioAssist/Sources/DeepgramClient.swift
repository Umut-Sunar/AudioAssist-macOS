import Foundation
import Network

/// Configuration for Deepgram Live API connection
struct DGConfig {
    let apiKey: String
    let sampleRate: Int
    let channels: Int
    let multichannel: Bool
    let model: String
    let language: String
    let interim: Bool
    let endpointingMs: Int
    let punctuate: Bool
    let smartFormat: Bool
    let diarize: Bool
    
    init(apiKey: String, 
         sampleRate: Int = 48000,  // Match successful project: 48kHz
         channels: Int = 1, 
         multichannel: Bool = false, 
         model: String = "nova-2", 
         language: String = "tr", 
         interim: Bool = true, 
         endpointingMs: Int = 300, 
         punctuate: Bool = true, 
         smartFormat: Bool = true, 
         diarize: Bool = true) {      // Enable diarization like successful project
        self.apiKey = apiKey
        self.sampleRate = sampleRate
        self.channels = channels
        self.multichannel = multichannel
        self.model = model
        self.language = language
        self.interim = interim
        self.endpointingMs = endpointingMs
        self.punctuate = punctuate
        self.smartFormat = smartFormat
        self.diarize = diarize
    }
    
    /// Generates the WebSocket URL with query parameters
    var websocketURL: URL? {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        
        // Core required parameters
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "channels", value: String(channels)),
            URLQueryItem(name: "model", value: model)
        ]
        
        // Optional parameters (only add if not default values)
        if language != "en" {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }
        
        if interim {
            queryItems.append(URLQueryItem(name: "interim_results", value: "true"))
        }
        
        if endpointingMs != 10 { // Deepgram default is 10ms
            queryItems.append(URLQueryItem(name: "endpointing", value: String(endpointingMs)))
        }
        
        if punctuate {
            queryItems.append(URLQueryItem(name: "punctuate", value: "true"))
        }
        
        if smartFormat {
            queryItems.append(URLQueryItem(name: "smart_format", value: "true"))
        }
        
        if diarize {
            queryItems.append(URLQueryItem(name: "diarize", value: "true"))
        }
        
        if multichannel {
            queryItems.append(URLQueryItem(name: "multichannel", value: "true"))
        }
        
        components?.queryItems = queryItems
        return components?.url
    }
}

/// Events received from Deepgram Live API
enum DGEvent {
    case connected(source: AudioSourceType)
    case disconnected(source: AudioSourceType)
    case error(String, source: AudioSourceType)
    case results(String, source: AudioSourceType) // JSON transcript results
    case metadata(String, source: AudioSourceType) // JSON metadata
    case fromFinalize(String, source: AudioSourceType) // JSON from finalize command
    
    var description: String {
        switch self {
        case .connected(let source):
            return "Connected to Deepgram (\(source.debugId))"
        case .disconnected(let source):
            return "Disconnected from Deepgram (\(source.debugId))"
        case .error(let message, let source):
            return "Error (\(source.debugId)): \(message)"
        case .results(let json, let source):
            return "Results (\(source.debugId)): \(json.prefix(100))"
        case .metadata(let json, let source):
            return "Metadata (\(source.debugId)): \(json)"
        case .fromFinalize(let json, let source):
            return "Finalize (\(source.debugId)): \(json)"
        }
    }
}

/// Handles WebSocket connection to Deepgram Live API
/// Manages authentication, real-time audio streaming, and transcript reception
class DeepgramClient {
    private let config: DGConfig
    private let sourceType: AudioSourceType
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var keepAliveTimer: Timer?
    private var onEventCallback: ((DGEvent) -> Void)?
    
    private enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case closing
    }
    
    private var connectionState: ConnectionState = .disconnected
    
    deinit {
        print("[DEBUG] 🔧 DeepgramClient (\(sourceType.debugId)) deinitializing")
        
        // 🚨 CRITICAL FIX: Synchronous cleanup to prevent SIGABRT
        // Timer'ı senkron olarak temizle
        if Thread.isMainThread {
            keepAliveTimer?.invalidate()
            keepAliveTimer = nil
        } else {
            DispatchQueue.main.sync {
                keepAliveTimer?.invalidate()
                keepAliveTimer = nil
            }
        }
        
        // WebSocket'i temizle
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
        
        print("[DEBUG] 🔧 DeepgramClient (\(sourceType.debugId)) deinitialized safely")
    }
    
    init(sourceType: AudioSourceType = .microphone) {
        // Use APIKeyManager to get API key from multiple sources
        let apiKey = APIKeyManager.getDeepgramAPIKey()
        
        self.config = DGConfig(apiKey: apiKey)
        self.sourceType = sourceType
        print("[DEBUG] DeepgramClient (\(sourceType.debugId)) initialized with API key: \(apiKey.isEmpty ? "MISSING" : "***\(apiKey.suffix(4))")")
        
        if apiKey.isEmpty {
            let status = APIKeyManager.getAPIKeyStatus()
            print("[DEBUG] ⚠️ DEEPGRAM_API_KEY not found in any source (Info.plist, environment, .env)!")
            print("[DEBUG] 🔍 API Key Status: source=\(status.source), key=\(status.maskedKey)")
        }
    }
    
    /// Initialize with explicit Deepgram configuration (preferred)
    init(config: DGConfig, sourceType: AudioSourceType) {
        self.config = config
        self.sourceType = sourceType
        let apiKey = config.apiKey
        let maskedKey = apiKey.isEmpty ? "MISSING" : "***\(apiKey.suffix(4))"
        print("[DEBUG] DeepgramClient (\(sourceType.debugId)) initialized (injected config) — sampleRate=\(config.sampleRate), channels=\(config.channels), multichannel=\(config.multichannel), model=\(config.model), lang=\(config.language), apiKey=\(maskedKey)")
        
        if apiKey.isEmpty {
            print("[DEBUG] ⚠️ DEEPGRAM_API_KEY missing in injected config!")
        }
    }
    
    /// Connect to Deepgram Live WebSocket
    /// - Parameter onEvent: Callback for receiving events
    func connect(onEvent: @escaping (DGEvent) -> Void) {
        print("[DEBUG] DeepgramClient (\(sourceType.debugId)).connect() called")
        
        guard !config.apiKey.isEmpty else {
            print("[DEBUG] ❌ Cannot connect (\(sourceType.debugId)): API key is missing")
            onEvent(.error("DEEPGRAM_API_KEY is missing. Please set it in your environment variables.", source: sourceType))
            return
        }
        
        guard let url = config.websocketURL else {
            print("[DEBUG] ❌ Cannot connect (\(sourceType.debugId)): Invalid WebSocket URL")
            onEvent(.error("Failed to create WebSocket URL", source: sourceType))
            return
        }
        
        print("[DEBUG] 🔗 Connecting (\(sourceType.debugId)) to: \(url.absoluteString)")
        
        // Store callback
        self.onEventCallback = onEvent
        
        // Create URL request with Authorization header
        var request = URLRequest(url: url)
        request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        // Add additional headers for better compatibility
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("deepgram-swift-client", forHTTPHeaderField: "User-Agent")
        
        print("[DEBUG] 🔑 Authorization header set (\(sourceType.debugId)): Token ***\(config.apiKey.suffix(4))")
        print("[DEBUG] 📋 Request headers (\(sourceType.debugId)): \(request.allHTTPHeaderFields ?? [:])")
        
        // Create URLSession and WebSocket task
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration)
        webSocketTask = urlSession?.webSocketTask(with: request)
        
        connectionState = .connecting
        
        // Start WebSocket connection
        webSocketTask?.resume()
        
        // Start receiving messages
        startReceiving()
        
        // Setup KeepAlive timer (5 seconds)
        setupKeepAliveTimer()
        
        print("[DEBUG] ✅ WebSocket connection initiated (\(sourceType.debugId))")
        // Don't call onEvent(.connected) here - wait for actual connection in startReceiving()
    }
    
    /// Send PCM audio data as binary frame
    /// - Parameter data: Raw PCM audio data
    func sendPCM(_ data: Data) {
        // Enhanced connection state check (like successful project)
        guard connectionState == .connected else {
            print("[DEBUG] ⚠️ Cannot send PCM (\(sourceType.debugId)): Not connected (state: \(connectionState))")
            return
        }
        
        guard let webSocketTask = webSocketTask else {
            print("[DEBUG] ❌ Cannot send PCM (\(sourceType.debugId)): WebSocket task is nil")
            return
        }
        
        // Check WebSocket readyState (like successful project)
        print("[DEBUG] 📡 WebSocket readyState check before sending")
        
        // Validate PCM data
        guard !data.isEmpty else {
            print("[DEBUG] ⚠️ Skipping empty PCM data (\(sourceType.debugId))")
            return
        }
        
        // Debug PCM data format
        if data.count >= 4 {
            let samples = data.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Int16.self).prefix(2))
            }
            // Frequent log disabled for performance
            // print("[DEBUG] 📊 PCM Sample Preview (\(sourceType.debugId)): \(samples) (first 2 samples)")
        }
        
        // Temporary log for debugging - will be disabled after testing
        print("[DEBUG] 📤 Sending PCM data (\(sourceType.debugId)): \(data.count) bytes (\(data.count / 2) samples)")
        
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask.send(message) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("[DEBUG] ❌ Failed to send PCM data (\(self.sourceType.debugId)): \(error.localizedDescription)")
                self.onEventCallback?(.error("Failed to send PCM data: \(error.localizedDescription)", source: self.sourceType))
            } else {
                // Frequent log disabled for performance
                // print("[DEBUG] ✅ Successfully sent PCM data (\(self.sourceType.debugId)): \(data.count) bytes")
            }
        }
    }
    
    /// Send Finalize control message
    func sendFinalize() {
        sendControlMessage(type: "Finalize")
    }
    
    /// Send CloseStream control message
    func sendCloseStream() {
        sendControlMessage(type: "CloseStream")
    }
    
    /// Close WebSocket connection and cleanup resources
    func closeSocket() {
        print("[DEBUG] 🔌 DeepgramClient (\(sourceType.debugId)).closeSocket() called")
        
        connectionState = .closing
        
        // Stop KeepAlive timer - main queue'da
        DispatchQueue.main.async { [weak self] in
            self?.keepAliveTimer?.invalidate()
            self?.keepAliveTimer = nil
        }
        print("[DEBUG] ⏹️ KeepAlive timer stopped (\(sourceType.debugId))")
        
        // Send CloseStream message before closing
        sendCloseStream()
        
        // Close WebSocket
        webSocketTask?.cancel(with: .goingAway, reason: "Client initiated close".data(using: .utf8))
        webSocketTask = nil
        
        // Invalidate URLSession
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        connectionState = .disconnected
        
        print("[DEBUG] ✅ WebSocket connection closed and resources cleaned up (\(sourceType.debugId))")
        onEventCallback?(.disconnected(source: sourceType))
    }
    
    // MARK: - Private Methods
    
    private func sendControlMessage(type: String) {
        guard connectionState == .connected else {
            print("[DEBUG] ⚠️ Cannot send \(type) (\(sourceType.debugId)): Not connected (state: \(connectionState))")
            return
        }
        
        guard let webSocketTask = webSocketTask else {
            print("[DEBUG] ❌ Cannot send \(type) (\(sourceType.debugId)): WebSocket task is nil")
            return
        }
        
        let controlMessage = ["type": type]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: controlMessage, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask.send(message) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    print("[DEBUG] ❌ Failed to send \(type) (\(self.sourceType.debugId)): \(error.localizedDescription)")
                    self.onEventCallback?(.error("Failed to send \(type): \(error.localizedDescription)", source: self.sourceType))
                } else {
                    print("[DEBUG] 📤 Sent \(type) control message (\(self.sourceType.debugId)): \(jsonString)")
                }
            }
        } catch {
            print("[DEBUG] ❌ Failed to serialize \(type) message (\(sourceType.debugId)): \(error.localizedDescription)")
            onEventCallback?(.error("Failed to serialize \(type) message", source: sourceType))
        }
    }
    
    private func setupKeepAliveTimer() {
        print("[DEBUG] ⏰ Setting up KeepAlive timer (\(sourceType.debugId)) (5 seconds)")
        
        // Timer'ı main queue'da çalıştır - SIGABRT hatası için
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendKeepAlive()
            }
        }
    }
    
    private func sendKeepAlive() {
        guard connectionState == .connected else {
            print("[DEBUG] ⚠️ Skipping KeepAlive (\(sourceType.debugId)): Not connected (state: \(connectionState))")
            return
        }
        
        sendControlMessage(type: "KeepAlive")
    }
    
    private func startReceiving() {
        guard let webSocketTask = webSocketTask else {
            print("[DEBUG] ❌ Cannot start receiving (\(sourceType.debugId)): WebSocket task is nil")
            return
        }
        
        webSocketTask.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                self.handleReceivedMessage(message)
                // Continue receiving
                self.startReceiving()
                
            case .failure(let error):
                print("[DEBUG] ❌ WebSocket receive error (\(self.sourceType.debugId)): \(error.localizedDescription)")
                self.connectionState = .disconnected
                self.onEventCallback?(.error("WebSocket receive error: \(error.localizedDescription)", source: self.sourceType))
            }
        }
        
        // Mark as connected after starting to receive - but only send event once
        if connectionState != .connected {
            connectionState = .connected
            print("[DEBUG] ✅ WebSocket is now connected and receiving messages (\(sourceType.debugId))")
            onEventCallback?(.connected(source: sourceType))
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("[DEBUG] 📥 Received text message (\(sourceType.debugId)): \(text.prefix(100))")
            parseJSONMessage(text)
            
        case .data(let data):
            print("[DEBUG] 📥 Received binary message (\(sourceType.debugId)): \(data.count) bytes")
            // Deepgram Live typically doesn't send binary data back, but handle if needed
            
        @unknown default:
            print("[DEBUG] ⚠️ Received unknown message type (\(sourceType.debugId))")
        }
    }
    
    private func parseJSONMessage(_ jsonString: String) {
        do {
            guard let jsonData = jsonString.data(using: .utf8) else {
                print("[DEBUG] ❌ Failed to convert JSON string to data (\(sourceType.debugId))")
                return
            }
            
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            
            if let dict = jsonObject as? [String: Any] {
                // Check message type
                if let type = dict["type"] as? String {
                    print("[DEBUG] 📋 Message type (\(sourceType.debugId)): \(type)")
                    
                    switch type {
                    case "Results":
                        onEventCallback?(.results(jsonString, source: sourceType))
                    case "Metadata":
                        onEventCallback?(.metadata(jsonString, source: sourceType))
                    default:
                        print("[DEBUG] ℹ️ Unknown message type (\(sourceType.debugId)): \(type)")
                        onEventCallback?(.results(jsonString, source: sourceType)) // Default to results
                    }
                } else if dict["is_final"] != nil || dict["channel"] != nil {
                    // This looks like a transcript result
                    onEventCallback?(.results(jsonString, source: sourceType))
                } else {
                    // Generic message
                    onEventCallback?(.metadata(jsonString, source: sourceType))
                }
            }
        } catch {
            print("[DEBUG] ❌ Failed to parse JSON message (\(sourceType.debugId)): \(error.localizedDescription)")
            print("[DEBUG] 📄 Raw message (\(sourceType.debugId)): \(jsonString)")
            // Still pass it as results in case it's a malformed but useful message
            onEventCallback?(.results(jsonString, source: sourceType))
        }
    }
}

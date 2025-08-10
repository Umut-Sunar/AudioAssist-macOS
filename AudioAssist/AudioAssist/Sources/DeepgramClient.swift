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
    case connected
    case disconnected
    case error(String)
    case results(String) // JSON transcript results
    case metadata(String) // JSON metadata
    case fromFinalize(String) // JSON from finalize command
    
    var description: String {
        switch self {
        case .connected:
            return "Connected to Deepgram"
        case .disconnected:
            return "Disconnected from Deepgram"
        case .error(let message):
            return "Error: \(message)"
        case .results(let json):
            return "Results: \(json)"
        case .metadata(let json):
            return "Metadata: \(json)"
        case .fromFinalize(let json):
            return "Finalize: \(json)"
        }
    }
}

/// Handles WebSocket connection to Deepgram Live API
/// Manages authentication, real-time audio streaming, and transcript reception
class DeepgramClient {
    private let config: DGConfig
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
    
    init() {
        // Try to read API key from environment
        let apiKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"] ?? ""
        
        self.config = DGConfig(apiKey: apiKey)
        print("[DEBUG] DeepgramClient initialized with API key: \(apiKey.isEmpty ? "MISSING" : "***\(apiKey.suffix(4))")")
        
        if apiKey.isEmpty {
            print("[DEBUG] ⚠️ DEEPGRAM_API_KEY not found in environment variables!")
        }
    }
    
    /// Connect to Deepgram Live WebSocket
    /// - Parameter onEvent: Callback for receiving events
    func connect(onEvent: @escaping (DGEvent) -> Void) {
        print("[DEBUG] DeepgramClient.connect() called")
        
        guard !config.apiKey.isEmpty else {
            print("[DEBUG] ❌ Cannot connect: API key is missing")
            onEvent(.error("DEEPGRAM_API_KEY is missing. Please set it in your environment variables."))
            return
        }
        
        guard let url = config.websocketURL else {
            print("[DEBUG] ❌ Cannot connect: Invalid WebSocket URL")
            onEvent(.error("Failed to create WebSocket URL"))
            return
        }
        
        print("[DEBUG] 🔗 Connecting to: \(url.absoluteString)")
        
        // Store callback
        self.onEventCallback = onEvent
        
        // Create URL request with Authorization header
        var request = URLRequest(url: url)
        request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        // Add additional headers for better compatibility
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("deepgram-swift-client", forHTTPHeaderField: "User-Agent")
        
        print("[DEBUG] 🔑 Authorization header set: Token ***\(config.apiKey.suffix(4))")
        print("[DEBUG] 📋 Request headers: \(request.allHTTPHeaderFields ?? [:])")
        
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
        
        print("[DEBUG] ✅ WebSocket connection initiated")
        // Don't call onEvent(.connected) here - wait for actual connection in startReceiving()
    }
    
    /// Send PCM audio data as binary frame
    /// - Parameter data: Raw PCM audio data
    func sendPCM(_ data: Data) {
        // Enhanced connection state check (like successful project)
        guard connectionState == .connected else {
            print("[DEBUG] ⚠️ Cannot send PCM: Not connected (state: \(connectionState))")
            return
        }
        
        guard let webSocketTask = webSocketTask else {
            print("[DEBUG] ❌ Cannot send PCM: WebSocket task is nil")
            return
        }
        
        // Check WebSocket readyState (like successful project)
        print("[DEBUG] 📡 WebSocket readyState check before sending")
        
        // Validate PCM data
        guard !data.isEmpty else {
            print("[DEBUG] ⚠️ Skipping empty PCM data")
            return
        }
        
        // Debug PCM data format
        if data.count >= 4 {
            let samples = data.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Int16.self).prefix(2))
            }
            print("[DEBUG] 📊 PCM Sample Preview: \(samples) (first 2 samples)")
        }
        
        print("[DEBUG] 📤 Sending PCM data: \(data.count) bytes (\(data.count / 2) samples)")
        
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask.send(message) { [weak self] error in
            if let error = error {
                print("[DEBUG] ❌ Failed to send PCM data: \(error.localizedDescription)")
                self?.onEventCallback?(.error("Failed to send PCM data: \(error.localizedDescription)"))
            } else {
                print("[DEBUG] ✅ Successfully sent PCM data: \(data.count) bytes")
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
        print("[DEBUG] 🔌 DeepgramClient.closeSocket() called")
        
        connectionState = .closing
        
        // Stop KeepAlive timer
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        print("[DEBUG] ⏹️ KeepAlive timer stopped")
        
        // Send CloseStream message before closing
        sendCloseStream()
        
        // Close WebSocket
        webSocketTask?.cancel(with: .goingAway, reason: "Client initiated close".data(using: .utf8))
        webSocketTask = nil
        
        // Invalidate URLSession
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        connectionState = .disconnected
        
        print("[DEBUG] ✅ WebSocket connection closed and resources cleaned up")
        onEventCallback?(.disconnected)
    }
    
    // MARK: - Private Methods
    
    private func sendControlMessage(type: String) {
        guard connectionState == .connected else {
            print("[DEBUG] ⚠️ Cannot send \(type): Not connected (state: \(connectionState))")
            return
        }
        
        guard let webSocketTask = webSocketTask else {
            print("[DEBUG] ❌ Cannot send \(type): WebSocket task is nil")
            return
        }
        
        let controlMessage = ["type": type]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: controlMessage, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask.send(message) { [weak self] error in
                if let error = error {
                    print("[DEBUG] ❌ Failed to send \(type): \(error.localizedDescription)")
                    self?.onEventCallback?(.error("Failed to send \(type): \(error.localizedDescription)"))
                } else {
                    print("[DEBUG] 📤 Sent \(type) control message: \(jsonString)")
                }
            }
        } catch {
            print("[DEBUG] ❌ Failed to serialize \(type) message: \(error.localizedDescription)")
            onEventCallback?(.error("Failed to serialize \(type) message"))
        }
    }
    
    private func setupKeepAliveTimer() {
        print("[DEBUG] ⏰ Setting up KeepAlive timer (5 seconds)")
        
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }
    
    private func sendKeepAlive() {
        guard connectionState == .connected else {
            print("[DEBUG] ⚠️ Skipping KeepAlive: Not connected (state: \(connectionState))")
            return
        }
        
        sendControlMessage(type: "KeepAlive")
    }
    
    private func startReceiving() {
        guard let webSocketTask = webSocketTask else {
            print("[DEBUG] ❌ Cannot start receiving: WebSocket task is nil")
            return
        }
        
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleReceivedMessage(message)
                // Continue receiving
                self?.startReceiving()
                
            case .failure(let error):
                print("[DEBUG] ❌ WebSocket receive error: \(error.localizedDescription)")
                self?.connectionState = .disconnected
                self?.onEventCallback?(.error("WebSocket receive error: \(error.localizedDescription)"))
            }
        }
        
        // Mark as connected after starting to receive
        connectionState = .connected
        print("[DEBUG] ✅ WebSocket is now connected and receiving messages")
        onEventCallback?(.connected)
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("[DEBUG] 📥 Received text message: \(text)")
            parseJSONMessage(text)
            
        case .data(let data):
            print("[DEBUG] 📥 Received binary message: \(data.count) bytes")
            // Deepgram Live typically doesn't send binary data back, but handle if needed
            
        @unknown default:
            print("[DEBUG] ⚠️ Received unknown message type")
        }
    }
    
    private func parseJSONMessage(_ jsonString: String) {
        do {
            guard let jsonData = jsonString.data(using: .utf8) else {
                print("[DEBUG] ❌ Failed to convert JSON string to data")
                return
            }
            
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            
            if let dict = jsonObject as? [String: Any] {
                // Check message type
                if let type = dict["type"] as? String {
                    print("[DEBUG] 📋 Message type: \(type)")
                    
                    switch type {
                    case "Results":
                        onEventCallback?(.results(jsonString))
                    case "Metadata":
                        onEventCallback?(.metadata(jsonString))
                    default:
                        print("[DEBUG] ℹ️ Unknown message type: \(type)")
                        onEventCallback?(.results(jsonString)) // Default to results
                    }
                } else if dict["is_final"] != nil || dict["channel"] != nil {
                    // This looks like a transcript result
                    onEventCallback?(.results(jsonString))
                } else {
                    // Generic message
                    onEventCallback?(.metadata(jsonString))
                }
            }
        } catch {
            print("[DEBUG] ❌ Failed to parse JSON message: \(error.localizedDescription)")
            print("[DEBUG] 📄 Raw message: \(jsonString)")
            // Still pass it as results in case it's a malformed but useful message
            onEventCallback?(.results(jsonString))
        }
    }
}

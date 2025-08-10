import SwiftUI
import Combine

// UIState ObservableObject class for managing state
final class UIState: ObservableObject {
    @Published var transcriptLog = ""
    let engine: AudioEngine

    init(engine: AudioEngine = AudioEngine(config: makeDGConfig())) {
        self.engine = engine
        self.engine.onEvent = { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch event {
                case .results(let json):
                    self.extractAndDisplayTranscript(json)
                case .finalized(let json):  
                    self.extractAndDisplayTranscript(json, isFinal: true)
                case .metadata(_):   
                    self.transcriptLog += "[META] Metadata received\n"
                case .connected:            
                    self.transcriptLog += "[INFO] ✅ Deepgram connected\n"
                case .disconnected:
                    self.transcriptLog += "[INFO] 🔌 Deepgram disconnected\n"
                case .error(let err):       
                    self.transcriptLog += "[ERR] ❌ \(err.localizedDescription)\n"
                }
            }
        }
    }
    
    /// Extract and display clean transcript from Deepgram JSON
    private func extractAndDisplayTranscript(_ jsonString: String, isFinal: Bool = false) {
        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("[DEBUG] ⚠️ Failed to parse JSON: \(jsonString.prefix(100))")
            return
        }
        
        // Extract transcript from Deepgram response structure
        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String else {
            print("[DEBUG] ⚠️ No transcript found in JSON")
            return
        }
        
        // Skip empty transcripts
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranscript.isEmpty else {
            print("[DEBUG] ⚠️ Empty transcript, skipping")
            return
        }
        
        // Extract additional info
        let confidence = firstAlternative["confidence"] as? Double ?? 0.0
        let speechFinal = json["speech_final"] as? Bool ?? false
        let isFinalResult = json["is_final"] as? Bool ?? false
        
        // Extract speaker info if available
        var speaker: Int = 0
        if let words = firstAlternative["words"] as? [[String: Any]],
           let firstWord = words.first,
           let speakerNum = firstWord["speaker"] as? Int {
            speaker = speakerNum
        }
        
        // Format timestamp
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        // Determine transcript type and styling
        let typeIndicator: String
        let confidenceText = String(format: "%.0f%%", confidence * 100)
        
        if speechFinal {
            typeIndicator = "🎯 FINAL"
        } else if isFinalResult {
            typeIndicator = "✅ DONE"
        } else {
            typeIndicator = "⏳ LIVE"
        }
        
        // Format display message
        let displayMessage = """
        [\(timestamp)] \(typeIndicator) [Speaker \(speaker)] (\(confidenceText))
        📝 \(cleanTranscript)
        
        """
        
        // Add to transcript log
        transcriptLog += displayMessage
        
        // Debug log
        print("[DEBUG] 📝 Transcript: \(cleanTranscript) (confidence: \(confidenceText), speaker: \(speaker))")
    }
}

struct ContentView: View {
    @StateObject private var ui = UIState()
    @State private var showAPIKeyAlert = false
    @State private var showPermissionAlert = false
    @State private var hasScreenRecordingPermission = false
    
    // Timer to periodically check permission status
    private let permissionTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Start") { 
                    // Check and update permission status
                    updatePermissionStatus()
                    
                    if !hasScreenRecordingPermission {
                        showPermissionAlert = true
                    } else {
                        ui.engine.start() 
                    }
                }
                Button("Stop")  { ui.engine.stop()  }
                
                // Permission status indicator
                HStack {
                    Image(systemName: hasScreenRecordingPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasScreenRecordingPermission ? .green : .orange)
                    Text(hasScreenRecordingPermission ? "Screen Recording: ✅" : "Screen Recording: ❌")
                        .font(.caption)
                }
                
                // Refresh button to check permission status
                Button("Refresh Permission") {
                    updatePermissionStatus()
                }
                .font(.caption)
                
                // Request permission button (to make app appear in System Preferences)
                if !hasScreenRecordingPermission {
                    Button("Request Permission") {
                        requestScreenRecordingPermission()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }

            ScrollView {
                Text(ui.transcriptLog.isEmpty ? "Transcript will appear here…" : ui.transcriptLog)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .padding()
        .onAppear {
            // Check API key
            let key = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"]
            if key == nil || key?.isEmpty == true { 
                showAPIKeyAlert = true 
            }
            
            // Check initial permission status
            updatePermissionStatus()
        }
        .onReceive(permissionTimer) { _ in
            // Periodically check permission status
            updatePermissionStatus()
        }
        .alert("Deepgram API Key Missing", isPresented: $showAPIKeyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("""
                 Please set your DEEPGRAM_API_KEY environment variable in your Xcode scheme or system environment.
                 Xcode: Product > Scheme > Edit Scheme > Run > Environment Variables
                 Add: DEEPGRAM_API_KEY = your_api_key_here
                 """)
        }
        .alert("Screen Recording Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Preferences", role: .none) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("""
                 AudioAssist needs Screen Recording permission to capture system audio (speakers/headphones).
                 
                 Steps:
                 1. Click "Open System Preferences"
                 2. Find "AudioAssist" in the list
                 3. Check the box next to it
                 4. Restart the app
                 """)
        }
    }
    
    // MARK: - Helper Functions
    
    private func updatePermissionStatus() {
        let newStatus = CGPreflightScreenCaptureAccess()
        print("[DEBUG] 🔒 Permission status check: \(newStatus ? "✅ Granted" : "❌ Denied")")
        
        DispatchQueue.main.async {
            hasScreenRecordingPermission = newStatus
        }
    }
    
    private func requestScreenRecordingPermission() {
        print("[DEBUG] 🔒 Requesting Screen Recording permission...")
        
        // Check current status first
        let currentStatus = CGPreflightScreenCaptureAccess()
        print("[DEBUG] 🔒 Current permission status: \(currentStatus ? "✅ Granted" : "❌ Denied")")
        
        if currentStatus {
            print("[DEBUG] 🔒 Permission already granted")
            updatePermissionStatus()
            return
        }
        
        // Force permission request - this will trigger the dialog and make app appear in System Preferences
        print("[DEBUG] 🔒 Triggering permission request dialog...")
        let granted = CGRequestScreenCaptureAccess()
        print("[DEBUG] 🔒 Permission request result: \(granted ? "✅ Granted" : "❌ Denied")")
        
        if !granted {
            print("[DEBUG] 🔒 Permission denied or dialog dismissed")
            print("[DEBUG] 🔒 App should now appear in System Preferences → Security & Privacy → Screen Recording")
        }
        
        // Update status after request
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            updatePermissionStatus()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { 
        ContentView() 
    }
}

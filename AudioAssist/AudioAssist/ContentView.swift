import SwiftUI
import Combine

// MARK: - String Extension for Repeat
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

// MARK: - Transcript Event Types (Deepgram Best Practices)
enum TranscriptEventType {
    case live      // Interim results - variable, real-time
    case done      // Segment complete - sentence finished
    case final     // Speech complete - final, unchangeable
    
    var icon: String {
        switch self {
        case .live: return "⏳"
        case .done: return "✅"
        case .final: return "🎯"
        }
    }
    
    var label: String {
        switch self {
        case .live: return "Canlı"
        case .done: return "Tamamlandı"
        case .final: return "Final"
        }
    }
    
    var color: Color {
        switch self {
        case .live: return .orange
        case .done: return .green
        case .final: return .blue
        }
    }
}

// MARK: - Transcript Display Model
struct TranscriptDisplay: Identifiable {
    let id = UUID()
    let type: TranscriptEventType
    let text: String
    let confidence: Double
    let source: AudioSourceType
    let speaker: Int
    let timestamp: Date
    
    var shouldDisplay: Bool {
        // LIVE: Only show high confidence results
        if type == .live && confidence < 0.7 { return false }
        // Skip empty text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }
    
    var displayText: String {
        switch type {
        case .live:
            // For LIVE: Show only last few words with "..." prefix
            let words = text.components(separatedBy: " ")
            if words.count > 3 {
                let lastWords = words.suffix(3).joined(separator: " ")
                return "...\(lastWords)"
            }
            return text
        case .done, .final:
            // For DONE/FINAL: Show full text
            return text
        }
    }
}

// MARK: - Modern Transcript Display View
struct TranscriptDisplayView: View {
    let transcripts: [TranscriptDisplay]
    let partialTranscript: String
    let audioBridgeStatus: String
    @Binding var searchText: String
    
    private var filteredTranscripts: [TranscriptDisplay] {
        if searchText.isEmpty {
            return transcripts
        }
        return transcripts.filter { transcript in
            transcript.text.localizedCaseInsensitiveContains(searchText) ||
            transcript.source.displayName.localizedCaseInsensitiveContains(searchText) ||
            transcript.type.label.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Debug Info Header
            HStack {
                Text("📊 Transcript'ler: \(transcripts.count)")
                if !searchText.isEmpty {
                    Text("🔍 Filtrelenmiş: \(filteredTranscripts.count)")
                        .foregroundColor(.blue)
                }
                Text("Partial: \(partialTranscript.isEmpty ? "YOK" : "VAR")")
                Text("Bridge: \(audioBridgeStatus)")
            }
            .font(.caption2)
            .foregroundColor(.gray)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Transcript'lerde ara...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button("Temizle") {
                        searchText = ""
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Transcript List
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Empty State
                    if filteredTranscripts.isEmpty && partialTranscript.isEmpty {
                        if !transcripts.isEmpty && !searchText.isEmpty {
                            // Search results empty
                            VStack(spacing: 16) {
                                Text("🔍")
                                    .font(.system(size: 48))
                                    .opacity(0.6)
                                Text("Arama sonucu bulunamadı")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("'\(searchText)' için transcript bulunamadı")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                        } else {
                            EmptyTranscriptView(audioBridgeStatus: audioBridgeStatus)
                        }
                    } else {
                        // Final Transcripts
                        ForEach(filteredTranscripts) { transcript in
                            TranscriptItemView(transcript: transcript)
                        }
                        
                        // Partial Transcript
                        if !partialTranscript.isEmpty {
                            PartialTranscriptView(text: partialTranscript)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Individual Transcript Item View - DEEPGRAM APPROACH A & B
struct TranscriptItemView: View {
    let transcript: TranscriptDisplay
    @State private var pulseOpacity: Double = 1.0
    
    private var styling: TranscriptStyling {
        TranscriptStyling(for: transcript)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Speaker Avatar with status indicator
            ZStack {
                Circle()
                    .fill(styling.avatarColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(styling.avatarText)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                
                // Status indicator for DONE transcripts (YAKLAŞIM B)
                if transcript.type == .done {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                        .offset(x: 12, y: -12)
                        .opacity(pulseOpacity)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Header with enhanced status
                HStack {
                    HStack(spacing: 4) {
                        Text(styling.icon)
                            .font(.caption)
                        Text(styling.sourceLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(styling.labelColor)
                    }
                    
                    HStack(spacing: 4) {
                        Text("(\(styling.label))")
                            .font(.caption)
                            .foregroundColor(styling.labelColor)
                        
                        // Additional status for DONE transcripts
                        if transcript.type == .done {
                            Text("...")
                                .font(.caption)
                                .foregroundColor(styling.labelColor)
                                .opacity(pulseOpacity)
                        }
                    }
                    
                    if transcript.speaker > 0 {
                        Text("[Speaker \(transcript.speaker)]")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Text(transcript.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                // Transcript Text with conditional opacity (YAKLAŞIM B: Ghost effect)
                Text(transcript.text)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .opacity(transcript.type == .done ? 0.7 : 1.0) // Hayalet efekti
                
                // Confidence and status
                HStack {
                    if transcript.confidence > 0 {
                        Text("Güven: \(Int(transcript.confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Status indicator for DONE transcripts
                    if transcript.type == .done {
                        Text("Final kontrol ediliyor...")
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                            .italic()
                    }
                }
            }
        }
        .padding(16)
        .background(styling.backgroundColor)
        .cornerRadius(12)
        .overlay(
            Rectangle()
                .fill(styling.borderColor)
                .frame(width: 4)
                .frame(maxHeight: .infinity, alignment: .leading),
            alignment: .leading
        )
        .opacity(transcript.type == .done ? 0.85 : 1.0) // Overall ghost effect for DONE
        .onAppear {
            // Pulse animation for DONE transcripts
            if transcript.type == .done {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.3
                }
            }
        }
    }
}

// MARK: - Partial Transcript View - DEEPGRAM APPROACH A
struct PartialTranscriptView: View {
    let text: String
    @State private var showCursor = true
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Animated Icon
            Text("⏳")
                .font(.title2)
                .rotationEffect(.degrees(360))
                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: text)
            
            VStack(alignment: .leading, spacing: 8) {
                // Header with enhanced live indicators
                HStack {
                    HStack(spacing: 6) {
                        Text("Kullanıcı")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                        
                        Text("(konuşuyor...)")
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                            .italic()
                    }
                    
                    Spacer()
                    
                    // Live indicator with pulse
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(showCursor ? 1.2 : 0.8)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: showCursor)
                        
                        Text("CANLI")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
                
                // Text with animated cursor - YAKLAŞIM A: Single Line Live Display
                HStack(alignment: .bottom, spacing: 2) {
                    Text(text)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    // Animated typing cursor
                    Text("|")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .opacity(showCursor ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: showCursor)
                    
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Character count indicator
                HStack {
                    Text("\(text.count) karakter")
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.7))
                    
                    Spacer()
                    
                    Text("Yazılıyor...")
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.7))
                        .italic()
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.yellow.opacity(0.05),
                    Color.orange.opacity(0.08),
                    Color.red.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .frame(maxHeight: .infinity, alignment: .leading),
            alignment: .leading
        )
        .shadow(color: Color.orange.opacity(0.2), radius: 4, x: 0, y: 2)
        .onAppear {
            showCursor = true
        }
    }
}

// MARK: - Empty State View
struct EmptyTranscriptView: View {
    let audioBridgeStatus: String
    
    var body: some View {
        VStack(spacing: 20) {
            // Large Icon
            Text("🎤")
                .font(.system(size: 64))
                .opacity(0.6)
            
            // Main Message
            VStack(spacing: 8) {
                Text(audioBridgeStatus == "active" 
                    ? "Konuşmaya başlayın, transcript'ler burada görünecek..."
                    : "Audio Bridge'ı başlatın ve konuşmaya başlayın...")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                if audioBridgeStatus != "active" {
                    Text("Start butonuna tıklayarak Audio Bridge'ı başlatın")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Status Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(audioBridgeStatus == "active" ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(audioBridgeStatus == "active" ? "🟢 Aktif" : "🔴 Durdu")
                    .font(.caption)
                    .foregroundColor(audioBridgeStatus == "active" ? .green : .red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(audioBridgeStatus == "active" ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Transcript Styling Helper
struct TranscriptStyling {
    let backgroundColor: Color
    let borderColor: Color
    let labelColor: Color
    let avatarColor: Color
    let avatarText: String
    let icon: String
    let sourceLabel: String
    let label: String
    
    init(for transcript: TranscriptDisplay) {
        let isMicrophone = transcript.source == .microphone
        let isSpeaker = transcript.source == .systemAudio
        
        if transcript.type == .final {
            backgroundColor = isMicrophone ? Color.green.opacity(0.1) : Color.blue.opacity(0.1)
            borderColor = isMicrophone ? Color.green : Color.blue
            labelColor = isMicrophone ? Color.green : Color.blue
            avatarColor = isMicrophone ? Color.green : Color.blue
            avatarText = isMicrophone ? "M" : "H"
            icon = isMicrophone ? "🎤" : "🔊"
            sourceLabel = isMicrophone ? "Mikrofon" : "Hoparlör"
            label = "Final"
        } else if transcript.type == .done {
            // YAKLAŞIM B: "Hayalet" efekti - henüz final olmamış transcript'ler
            backgroundColor = isMicrophone ? Color.green.opacity(0.08) : Color.blue.opacity(0.08)
            borderColor = isMicrophone ? Color.green.opacity(0.6) : Color.blue.opacity(0.6)
            labelColor = isMicrophone ? Color.green.opacity(0.8) : Color.blue.opacity(0.8)
            avatarColor = isMicrophone ? Color.green.opacity(0.8) : Color.blue.opacity(0.8)
            avatarText = isMicrophone ? "M" : "H"
            icon = isMicrophone ? "🎤" : "🔊"
            sourceLabel = isMicrophone ? "Mikrofon" : "Hoparlör"
            label = "Kontrol Ediliyor..."
        } else {
            backgroundColor = isMicrophone ? Color.orange.opacity(0.1) : Color.purple.opacity(0.1)
            borderColor = isMicrophone ? Color.orange.opacity(0.8) : Color.purple.opacity(0.8)
            labelColor = isMicrophone ? Color.orange : Color.purple
            avatarColor = isMicrophone ? Color.orange : Color.purple
            avatarText = isMicrophone ? "M" : "H"
            icon = isMicrophone ? "🎤" : "🔊"
            sourceLabel = isMicrophone ? "Mikrofon" : "Hoparlör"
            label = "Canlı"
        }
    }
}

// UIState ObservableObject class for managing state - DEEPGRAM APPROACH A
final class UIState: ObservableObject {
    @Published var transcriptLog = ""
    @Published var transcripts: [TranscriptDisplay] = []  // 📝 KALICI LİSTE - Sadece DONE/FINAL
    @Published var partialTranscript: String = ""        // ⏳ TEK CANLI TRANSCRIPT - Sadece LIVE
    @Published var audioBridgeStatus: String = "inactive"
    
    let engine: AudioEngine
    
    // 🚨 DEEPGRAM APPROACH A: Enhanced duplicate prevention for utterance management
    private var currentUtterances: [String: UtteranceState] = [:]  // Track active utterances by ID
    private var recentTranscripts: [(source: AudioSourceType, text: String, timestamp: Date, type: TranscriptEventType)] = []
    private let duplicateTimeWindow: TimeInterval = 5.0 // Increased to 5 seconds
    
    // 📊 TRANSCRIPT HISTORY: Keep track of final transcripts only
    private var transcriptHistory: [TranscriptDisplay] = []
    private let maxHistorySize = 100 // Keep last 100 transcripts
    
    // 🎯 UTTERANCE STATE: Track speech utterances following Deepgram best practices
    private struct UtteranceState {
        let startTime: Date
        var currentText: String
        var confidence: Double
        var source: AudioSourceType
        var speaker: Int
        var hasBeenFinalized: Bool = false
    }

    init(engine: AudioEngine = AudioEngine(config: makeDGConfig())) {
        self.engine = engine
        self.engine.onEvent = { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch event {
                case .results(let json, let source):
                    self.extractAndDisplayTranscript(json, source: source)
                case .finalized(let json, let source):  
                    self.extractAndDisplayTranscript(json, source: source, isFinal: true)
                case .metadata(_, let source):   
                    self.transcriptLog += "[META] Metadata received from \(source.displayName)\n"
                case .microphoneConnected:            
                    self.transcriptLog += "[INFO] 🎤 Mikrofon bağlandı\n"
                    self.audioBridgeStatus = "active"
                case .systemAudioConnected:            
                    self.transcriptLog += "[INFO] 🔊 Hoparlör bağlandı\n"
                    self.audioBridgeStatus = "active"
                case .microphoneDisconnected:
                    self.transcriptLog += "[INFO] 🎤 Mikrofon bağlantısı kesildi\n"
                    self.audioBridgeStatus = "inactive"
                case .systemAudioDisconnected:
                    self.transcriptLog += "[INFO] 🔊 Hoparlör bağlantısı kesildi\n"
                    self.audioBridgeStatus = "inactive"
                case .error(let err, let source):       
                    self.transcriptLog += "[ERR] ❌ \(source.displayName): \(err.localizedDescription)\n"
                }
            }
        }
    }
    
    /// DEEPGRAM APPROACH A: Extract and display transcript using utterance-based management
    /// Implements Deepgram's recommended single live transcript + permanent list pattern
    private func extractAndDisplayTranscript(_ jsonString: String, source: AudioSourceType, isFinal: Bool = false) {
        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("[APPROACH-A] ⚠️ Failed to parse JSON: \(jsonString.prefix(100))")
            return
        }
        
        // Extract transcript from Deepgram response structure
        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String else {
            print("[APPROACH-A] ⚠️ No transcript found in JSON")
            return
        }
        
        // Skip empty transcripts
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranscript.isEmpty else {
            print("[APPROACH-A] ⚠️ Empty transcript, skipping")
            return
        }
        
        // Extract metadata
        let confidence = firstAlternative["confidence"] as? Double ?? 0.0
        let speechFinal = json["speech_final"] as? Bool ?? false
        let isFinalResult = json["is_final"] as? Bool ?? false
        let currentTime = Date()
        
        // Extract speaker info
        var speaker: Int = 0
        if let words = firstAlternative["words"] as? [[String: Any]],
           let firstWord = words.first,
           let speakerNum = firstWord["speaker"] as? Int {
            speaker = speakerNum
        }
        
        // 🎯 DEEPGRAM APPROACH A: UTTERANCE MANAGEMENT
        let utteranceId = "\(source.rawValue)-\(speaker)"
        
        // 🔄 DETERMINE EVENT TYPE (Deepgram Best Practices)
        let eventType: TranscriptEventType
        if speechFinal {
            eventType = .final    // 🎯 Speech completely finished
        } else if isFinalResult {
            eventType = .done     // ✅ Sentence/segment complete
        } else {
            eventType = .live     // ⏳ Interim results
        }
        
        print("[APPROACH-A] 📝 Processing: '\(cleanTranscript.prefix(50))' | Type: \(eventType) | Confidence: \(Int(confidence*100))%")
        
        // 🚨 ADVANCED DUPLICATE PREVENTION
        if isAdvancedDuplicate(text: cleanTranscript, source: source, type: eventType, speaker: speaker) {
            print("[APPROACH-A] 🚫 Advanced duplicate filtered: \(cleanTranscript.prefix(30))")
            return
        }
        
        // ⏳ HANDLE LIVE TRANSCRIPTS (Yaklaşım A - Tek Satırlık Canlı Gösterim)
        if eventType == .live {
            // 📍 Confidence check for live transcripts
            guard confidence >= 0.7 else {
                print("[APPROACH-A] 🚫 Live transcript confidence too low: \(Int(confidence*100))%")
                return
            }
            
            // 📱 UPDATE SINGLE LIVE TRANSCRIPT (In-place mutation)
            partialTranscript = cleanTranscript
            print("[APPROACH-A] ⏳ Live transcript updated: '\(cleanTranscript.prefix(30))...'")
            
            // Track current utterance
            currentUtterances[utteranceId] = UtteranceState(
                startTime: currentTime,
                currentText: cleanTranscript,
                confidence: confidence,
                source: source,
                speaker: speaker
            )
            
            // Don't add to permanent list yet
            return
        }
        
        // ✅ HANDLE DONE/FINAL TRANSCRIPTS (Move to permanent list)
        if eventType == .done || eventType == .final {
            // 🧹 Clear partial transcript (utterance completed)
            if currentUtterances[utteranceId] != nil {
                partialTranscript = ""
                currentUtterances.removeValue(forKey: utteranceId)
                print("[APPROACH-A] 🧹 Partial transcript cleared - utterance completed")
            }
            
            // 📝 CREATE PERMANENT TRANSCRIPT
            let permanentTranscript = TranscriptDisplay(
            type: eventType,
            text: cleanTranscript,
            confidence: confidence,
            source: source,
            speaker: speaker,
            timestamp: currentTime
        )
        
            // ✅ ADD TO PERMANENT LIST
            transcriptHistory.append(permanentTranscript)
            
            // 🗂️ Keep history size manageable
        if transcriptHistory.count > maxHistorySize {
            transcriptHistory.removeFirst(transcriptHistory.count - maxHistorySize)
        }
            
            // 📢 UPDATE UI
            transcripts = transcriptHistory
            
            print("[APPROACH-A] ✅ Added to permanent list: '\(cleanTranscript.prefix(30))...' | Type: \(eventType)")
        }
        
        // 📊 TRACK FOR DUPLICATE PREVENTION
        recentTranscripts.append((source: source, text: cleanTranscript, timestamp: currentTime, type: eventType))
        
        // 🧹 CLEANUP OLD ENTRIES
        recentTranscripts.removeAll { currentTime.timeIntervalSince($0.timestamp) > duplicateTimeWindow }
        
        // Format timestamp
        let timestamp = DateFormatter.localizedString(from: currentTime, dateStyle: .none, timeStyle: .medium)
        
        // Format confidence text
        let confidenceText = String(format: "%.0f%%", confidence * 100)
        
        // 🎨 LEGACY TRANSCRIPT LOG (for old view compatibility)
        let sourceIcon = source.icon
        let sourceName = source.displayName
        let eventIcon = eventType.icon
        
        // Simple log message for legacy view
        let logMessage = "[\(timestamp)] \(eventIcon) [\(sourceIcon) \(sourceName)] [Speaker \(speaker)] (\(confidenceText)) - \(cleanTranscript)\n"
        transcriptLog += logMessage
        
        // Debug log with enhanced information
        print("[APPROACH-A] 📝 Processed: '\(cleanTranscript.prefix(30))...' | Type: \(eventType) | Confidence: \(confidenceText) | Speaker: \(speaker)")
    }
    
    /// ADVANCED DUPLICATE DETECTION - Deepgram Approach A
    /// Handles cross-source, partial overlap, and event progression duplicates
    private func isAdvancedDuplicate(text: String, source: AudioSourceType, type: TranscriptEventType, speaker: Int) -> Bool {
        let currentTime = Date()
        
        for recent in recentTranscripts {
            // Skip if outside time window
            if currentTime.timeIntervalSince(recent.timestamp) > duplicateTimeWindow {
                continue
            }
            
            // 1️⃣ EXACT TEXT MATCH (same source)
            if recent.text == text && recent.source == source {
                print("[APPROACH-A] 🚫 Exact match from same source")
                return true
            }
            
            // 2️⃣ CROSS-SOURCE DUPLICATE (same text from different sources)
            if recent.text == text && recent.source != source {
                print("[APPROACH-A] 🚫 Cross-source duplicate detected")
                return true
            }
            
            // 3️⃣ PARTIAL OVERLAP (live transcript evolution)
            if type == .live {
                // Check if current text contains previous text (growing utterance)
                if text.contains(recent.text) && recent.text.count > 5 {
                    print("[APPROACH-A] 🚫 Growing utterance overlap")
                    return true
                }
                
                // Check if previous text contains current text (shrinking utterance)
                if recent.text.contains(text) && text.count > 5 {
                    print("[APPROACH-A] 🚫 Shrinking utterance overlap")
                    return true
                }
            }
            
            // 4️⃣ EVENT PROGRESSION (LIVE → DONE → FINAL)
            if recent.text == text && isEventProgression(from: recent.type, to: type) {
                print("[APPROACH-A] 🚫 Event progression duplicate: \(recent.type) → \(type)")
                return true
            }
            
            // 5️⃣ SIMILARITY THRESHOLD (fuzzy matching)
            let similarity = textSimilarity(text, recent.text)
            if similarity > 0.9 && recent.source == source {
                print("[APPROACH-A] 🚫 High similarity duplicate: \(Int(similarity*100))%")
                return true
            }
        }
        
        return false
    }
    
    /// Check if this is a valid event progression (LIVE → DONE → FINAL)
    private func isEventProgression(from oldType: TranscriptEventType, to newType: TranscriptEventType) -> Bool {
        switch (oldType, newType) {
        case (.live, .done), (.live, .final), (.done, .final):
            return true
        default:
            return false
        }
    }
    
    /// Calculate text similarity using word overlap
    private func textSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let words2 = Set(text2.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        
        guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        return Double(intersection.count) / Double(union.count)
    }
    
    /// Get transcript statistics for debugging
    func getTranscriptStats() -> String {
        let liveCount = transcriptHistory.filter { $0.type == .live }.count
        let doneCount = transcriptHistory.filter { $0.type == .done }.count
        let finalCount = transcriptHistory.filter { $0.type == .final }.count
        
        return """
        📊 Transcript Statistics:
        • LIVE: \(liveCount)
        • DONE: \(doneCount)  
        • FINAL: \(finalCount)
        • Total: \(transcriptHistory.count)
        • Duplicates Filtered: \(recentTranscripts.count)
        """
    }
}

struct ContentView: View {
    @StateObject private var ui = UIState()
    @StateObject private var permissionManager = PermissionManager()
    @State private var showAPIKeyAlert = false
    @State private var showPermissionAlert = false
    @State private var showTranscriptView = true
    @State private var searchText = ""
    @State private var autoClearTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Start") { 
                    // Check API key first
                    if !APIKeyManager.hasValidAPIKey() {
                        showAPIKeyAlert = true
                        return
                    }
                    
                    // Check permission status using PermissionManager
                    if !permissionManager.hasScreenRecordingPermission {
                        showPermissionAlert = true
                    } else {
                        // Start safely with error handling
                        do {
                            ui.engine.start()
                        } catch {
                            print("[ContentView] ❌ Error starting engine: \(error)")
                        }
                    }
                }
                Button("Stop") { 
                    // Stop safely with error handling
                    do {
                        ui.engine.stop()
                    } catch {
                        print("[ContentView] ❌ Error stopping engine: \(error)")
                    }
                }
                
                // 📊 Transcript Statistics Button
                Button("📊 Stats") {
                    let stats = ui.getTranscriptStats()
                    print("[DEBUG] \(stats)")
                    // You can also show this in an alert or overlay if desired
                }
                .font(.caption)
                .foregroundColor(.blue)
                .help("Show transcript statistics and filtering information")
                
                // Toggle between old and new transcript view
                Button(showTranscriptView ? "📝 Old View" : "🎨 New View") {
                    showTranscriptView.toggle()
                }
                .font(.caption)
                .foregroundColor(.purple)
                .help("Toggle between old text view and new modern transcript view")
                
                // Demo button to test transcript display
                Button("🎭 Demo Data") {
                    addDemoTranscripts()
                }
                .font(.caption)
                .foregroundColor(.orange)
                .help("Add sample transcript data to test the new display system")
                
                // Export transcripts button
                Button("📤 Export") {
                    exportTranscripts()
                }
                .font(.caption)
                .foregroundColor(.green)
                .help("Export all transcripts to text file")
                
                // Clear transcripts button
                Button("🗑️ Clear") {
                    clearTranscripts()
                }
                .font(.caption)
                .foregroundColor(.red)
                .help("Clear all transcripts")
                
                // Auto-clear toggle
                Button(autoClearTimer != nil ? "⏰ Auto-Clear: ON" : "⏰ Auto-Clear: OFF") {
                    toggleAutoClear()
                }
                .font(.caption)
                .foregroundColor(autoClearTimer != nil ? .orange : .gray)
                .help("Toggle automatic transcript clearing every 5 minutes")
                
                // Permission status indicator
                HStack {
                    Image(systemName: permissionManager.hasScreenRecordingPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(permissionManager.hasScreenRecordingPermission ? .green : .orange)
                    Text(permissionManager.hasScreenRecordingPermission ? "Screen Recording: ✅" : "Screen Recording: ❌")
                        .font(.caption)
                }
                
                // Refresh button to check permission status
                Button("Refresh Permission") {
                    Task {
                        await permissionManager.checkPermissionStatus()
                    }
                }
                .font(.caption)
                
                // Request permission button (to make app appear in System Preferences)
                if !permissionManager.hasScreenRecordingPermission {
                    Button("Request Permission") {
                        Task {
                            // Use enhanced TCC cache handling for better success rate
                            await permissionManager.requestPermissionWithTCCCacheHandling()
                        }
                    }
                }
                
                // 🚨 ALWAYS VISIBLE: Automatic TCC Reset Button (Apple Developer Community Solution)
                // This button is always shown because CGPreflightScreenCaptureAccess can give false positives
                // due to TCC cache issues, especially in development builds
                Button("🔧 Auto-Fix TCC") {
                    Task {
                        let success = await permissionManager.performAutomaticTCCReset()
                        if success {
                            print("[ContentView] ✅ Automatic TCC reset successful - permission should work now")
                        } else {
                            print("[ContentView] ❌ Automatic TCC reset failed - manual intervention needed")
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
                .help("Automatically fixes common TCC permission cache issues - always available for development builds")
            }

            // Transcript Display Area
            if showTranscriptView {
                // Modern Transcript View
                TranscriptDisplayView(
                    transcripts: ui.transcripts,
                    partialTranscript: ui.partialTranscript,
                    audioBridgeStatus: ui.audioBridgeStatus,
                    searchText: $searchText
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Old Text View
            ScrollView {
                Text(ui.transcriptLog.isEmpty ? "Transcript will appear here…" : ui.transcriptLog)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .padding()
        .onAppear {
            // Check API key using APIKeyManager
            if !APIKeyManager.hasValidAPIKey() {
                showAPIKeyAlert = true 
                
                // Debug: Show API key status
                let status = APIKeyManager.getAPIKeyStatus()
                print("[ContentView] 🔍 API Key Status: hasKey=\(status.hasKey), source=\(status.source), key=\(status.maskedKey)")
            }
            
            // 🚨 AUTO-DETECT TCC PERMISSION ISSUES ON STARTUP
            Task {
                print("[ContentView] 🔍 Checking for TCC permission issues on startup...")
                
                // Wait a moment for UI to settle
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Check for the common permission cache mismatch
                let preflightResult = CGPreflightScreenCaptureAccess()
                let hasSystemPermission = await permissionManager.checkSystemSettingsPermission()
                
                if !preflightResult && hasSystemPermission {
                    print("[ContentView] 🚨 TCC cache mismatch detected - offering automatic fix")
                    
                    // Automatically attempt to fix the issue
                    let autoFixSuccess = await permissionManager.performAutomaticTCCReset()
                    
                    if autoFixSuccess {
                        print("[ContentView] ✅ Auto-fix successful - permissions should work now")
                    } else {
                        print("[ContentView] ⚠️ Auto-fix failed - user will need to use manual buttons")
                    }
                } else {
                    print("[ContentView] ✅ No permission issues detected on startup")
                }
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            autoClearTimer?.invalidate()
            autoClearTimer = nil
        }
        .alert("Deepgram API Key Missing", isPresented: $showAPIKeyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            let status = APIKeyManager.getAPIKeyStatus()
            Text("""
                 DEEPGRAM_API_KEY is required for speech-to-text functionality.
                 
                 📍 Current Status: \(status.source) - \(status.maskedKey)
                 
                 🔧 Setup Options:
                 1. BUILD SETTINGS (Recommended for Archive):
                    • Xcode → Project → Build Settings
                    • Add User-Defined Setting: DEEPGRAM_API_KEY = your_key
                 
                 2. XCODE SCHEME (Development only):
                    • Product → Scheme → Edit Scheme → Run → Environment Variables
                    • Add: DEEPGRAM_API_KEY = your_key
                 
                 3. SYSTEM ENVIRONMENT:
                    • Terminal: export DEEPGRAM_API_KEY="your_key"
                 """)
        }
        .alert("Screen Recording Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Preferences", role: .none) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            Button("Run Fix Script", role: .none) {
                runPermissionFixScript()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let statusInfo = permissionManager.getPermissionStatusInfo()
            
            if statusInfo.isDevelopmentBuild {
                var message = """
                     AudioAssist needs Screen Recording permission to capture system audio.
                     
                     🔧 DEVELOPMENT BUILD DETECTED
                     
                     This is a development build from Xcode, which can cause permission issues.
                     
                     RECOMMENDED: Click "Run Fix Script" to automatically:
                     • Reset permissions
                     • Clean app data
                     • Copy app to Applications folder
                     • Open System Preferences
                     
                     MANUAL STEPS:
                     1. Click "Open System Preferences"
                     2. Go to Privacy & Security → Screen Recording
                     3. Look for "AudioAssist" or manually add it using "+"
                     4. Enable the permission and restart the app
                     
                     Bundle ID: \(statusInfo.bundleID)
                     App Path: \(statusInfo.bundlePath)
                     """
                
                if statusInfo.isSequoiaOrLater {
                    message += "\n\n🍎 macOS Sequoia: Weekly permission renewal required"
                }
                
                if statusInfo.needsWeeklyRenewal {
                    message += "\n⚠️ Permission may have expired (> 7 days)"
                }
                
                return Text(message)
            } else {
                let statusInfo = permissionManager.getPermissionStatusInfo()
                var message = """
                     AudioAssist needs Screen Recording permission to capture system audio (speakers/headphones).
                     
                     Steps:
                     1. Click "Open System Preferences"
                     2. Find "AudioAssist" or "\(statusInfo.bundleID)" in the list
                     3. Check the box next to it
                     4. Restart the app
                     
                     Bundle ID: \(statusInfo.bundleID)
                     """
                
                if statusInfo.isSequoiaOrLater {
                    message += "\n\n🍎 macOS Sequoia: Weekly permission renewal required"
                }
                
                if statusInfo.needsWeeklyRenewal {
                    message += "\n⚠️ Permission may have expired (> 7 days)"
                }
                
                return Text(message)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func addDemoTranscripts() {
        let demoTranscripts = [
            TranscriptDisplay(
                type: .live,
                text: "Bu bir canlı transcript örneğidir...",
                confidence: 0.85,
                source: .microphone,
                speaker: 1,
                timestamp: Date()
            ),
            TranscriptDisplay(
                type: .done,
                text: "Bu transcript tamamlandı ve kalıcı listeye eklendi.",
                confidence: 0.92,
                source: .microphone,
                speaker: 1,
                timestamp: Date().addingTimeInterval(-30)
            ),
            TranscriptDisplay(
                type: .final,
                text: "Bu final transcript konuşma tamamen bitti.",
                confidence: 0.95,
                source: .systemAudio,
                speaker: 2,
                timestamp: Date().addingTimeInterval(-60)
            ),
            TranscriptDisplay(
                type: .done,
                text: "Hoparlörden gelen ses transcript'i.",
                confidence: 0.88,
                source: .systemAudio,
                speaker: 2,
                timestamp: Date().addingTimeInterval(-90)
            )
        ]
        
        ui.transcripts = demoTranscripts
        ui.partialTranscript = "Şu anda konuşuyor... bu partial transcript..."
        ui.audioBridgeStatus = "active"
        
        print("[Demo] ✅ Demo transcript data added")
    }
    
    private func exportTranscripts() {
        guard !ui.transcripts.isEmpty else {
            print("[Export] ⚠️ No transcripts to export")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var exportText = "AudioAssist Transcript Export\n"
        exportText += "Generated: \(Date().formatted())\n"
        exportText += "Total Transcripts: \(ui.transcripts.count)\n"
        exportText += "=" * 50 + "\n\n"
        
        for (index, transcript) in ui.transcripts.enumerated() {
            exportText += "[\(index + 1)] \(transcript.timestamp.formatted())\n"
            exportText += "Type: \(transcript.type.label)\n"
            exportText += "Source: \(transcript.source.displayName)\n"
            exportText += "Speaker: \(transcript.speaker)\n"
            exportText += "Confidence: \(Int(transcript.confidence * 100))%\n"
            exportText += "Text: \(transcript.text)\n"
            exportText += "-" * 30 + "\n\n"
        }
        
        // Save to file
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "transcripts_\(timestamp).txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try exportText.write(to: url, atomically: true, encoding: .utf8)
                    print("[Export] ✅ Transcripts exported to: \(url.path)")
                } catch {
                    print("[Export] ❌ Export failed: \(error)")
                }
            }
        }
    }
    
    private func clearTranscripts() {
        ui.transcripts = []
        ui.partialTranscript = ""
        print("[Clear] ✅ All transcripts cleared")
    }
    
    private func toggleAutoClear() {
        if autoClearTimer != nil {
            autoClearTimer?.invalidate()
            autoClearTimer = nil
            print("[Auto-Clear] ❌ Disabled")
        } else {
            autoClearTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
                clearTranscripts()
            }
            print("[Auto-Clear] ✅ Enabled (every 5 minutes)")
        }
    }
    
    private func runPermissionFixScript() {
        print("[DEBUG] 🔧 Running permission fix script...")
        
        let scriptPath = Bundle.main.path(forResource: "fix_screen_recording_permissions", ofType: "sh") ?? 
                        "../../../fix_screen_recording_permissions.sh"
        
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [scriptPath]
        
        // Run in background to avoid blocking UI
        DispatchQueue.global(qos: .background).async {
            do {
                try task.run()
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    print("[DEBUG] ✅ Permission fix script completed")
                    // Update permission status after script runs
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        await permissionManager.checkPermissionStatus()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("[DEBUG] ❌ Failed to run permission fix script: \(error)")
                    ui.transcriptLog += "[ERROR] Failed to run permission fix script. Please run it manually from Terminal.\n"
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { 
        ContentView() 
    }
}

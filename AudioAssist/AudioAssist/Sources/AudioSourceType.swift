import Foundation

/// Audio source types for dual stream processing
/// Identifies whether audio comes from microphone or system audio
enum AudioSourceType: String, CaseIterable {
    case microphone = "microphone"
    case systemAudio = "systemAudio"
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .microphone:
            return "Mikrofon"
        case .systemAudio:
            return "Hoparlör"
        }
    }
    
    /// Icon for UI display
    var icon: String {
        switch self {
        case .microphone:
            return "🎤"
        case .systemAudio:
            return "🔊"
        }
    }
    
    /// Debug identifier for logging
    var debugId: String {
        switch self {
        case .microphone:
            return "MIC"
        case .systemAudio:
            return "SYS"
        }
    }
    
    /// Unique identifier for Deepgram connection tracking
    var connectionId: String {
        return "deepgram_\(rawValue)"
    }
}

/// Extension to DGConfig for source-specific configuration
extension DGConfig {
    /// Create a source-specific configuration
    /// - Parameter source: Audio source type
    /// - Returns: New DGConfig with source-specific settings
    func withSource(_ source: AudioSourceType) -> DGConfig {
        return DGConfig(
            apiKey: self.apiKey,
            sampleRate: self.sampleRate,
            channels: self.channels,
            multichannel: self.multichannel,
            model: self.model,
            language: self.language,
            interim: self.interim,
            endpointingMs: self.endpointingMs,
            punctuate: self.punctuate,
            smartFormat: self.smartFormat,
            diarize: self.diarize
        )
    }
}

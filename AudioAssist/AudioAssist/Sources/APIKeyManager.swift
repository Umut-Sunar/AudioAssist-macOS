import Foundation

/// API Key yönetimi için merkezi sınıf
/// Archive modunda çalışacak şekilde farklı kaynaklardan API key okur
struct APIKeyManager {
    
    /// Deepgram API key'ini farklı kaynaklardan okur (öncelik sırasına göre)
    /// 1. Info.plist (Production builds için)
    /// 2. Environment variables (Development için)
    /// 3. Bundle içi .env dosyası (Fallback)
    /// 4. Hardcoded fallback (geliştirme için)
    static func getDeepgramAPIKey() -> String {
        
        // Debug: Tüm kaynakları kontrol et
        print("[APIKeyManager] 🔍 Checking all API key sources...")
        print("[APIKeyManager] 📱 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("[APIKeyManager] 📁 Bundle Path: \(Bundle.main.bundlePath)")
        print("[APIKeyManager] 🔧 Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        
        // 1. Environment variable'dan oku (Development için öncelik - Xcode Scheme'den)
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], 
           !envKey.isEmpty {
            print("[APIKeyManager] ✅ API Key found in ENVIRONMENT: ***\(envKey.suffix(4))")
            return envKey
        }
        
        // 2. Info.plist'den oku (Production/Archive builds için)
        if let plistKey = Bundle.main.infoDictionary?["DEEPGRAM_API_KEY"] as? String, 
           !plistKey.isEmpty, 
           plistKey != "$(DEEPGRAM_API_KEY)" { // Build variable placeholder değilse
            print("[APIKeyManager] ✅ API Key found in Info.plist: ***\(plistKey.suffix(4))")
            return plistKey
        }
        
        // 3. Bundle içinden .env dosyasını oku (Fallback için)
        if let envKey = loadFromEnvFile() {
            print("[APIKeyManager] ✅ API Key found in .env file: ***\(envKey.suffix(4))")
            return envKey
        }
        
        // 4. Hardcoded fallback (geliştirme için - acil durum)
        let fallbackKey = "b284403be6755d63a0c2dc440464773186b10cea"
        print("[APIKeyManager] ⚠️ Using HARDCODED FALLBACK API key: ***\(fallbackKey.suffix(4))")
        print("[APIKeyManager] 💡 This is for development only - configure proper API key source!")
        return fallbackKey
    }
    
    /// API key'in mevcut olup olmadığını kontrol eder
    static func hasValidAPIKey() -> Bool {
        return !getDeepgramAPIKey().isEmpty
    }
    
    /// API key durumu hakkında detaylı bilgi verir (debugging için)
    static func getAPIKeyStatus() -> (hasKey: Bool, source: String, maskedKey: String) {
        
        // Info.plist kontrolü
        if let plistKey = Bundle.main.infoDictionary?["DEEPGRAM_API_KEY"] as? String, 
           !plistKey.isEmpty, 
           plistKey != "$(DEEPGRAM_API_KEY)" {
            return (true, "Info.plist", "***\(plistKey.suffix(4))")
        }
        
        // Environment variable kontrolü
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], 
           !envKey.isEmpty {
            return (true, "Environment", "***\(envKey.suffix(4))")
        }
        
        // .env dosyası kontrolü
        if let envKey = loadFromEnvFile() {
            return (true, ".env file", "***\(envKey.suffix(4))")
        }
        
        return (false, "None", "MISSING")
    }
    
    // MARK: - Private Helper Methods
    
    /// Bundle içindeki .env dosyasından API key okur
    private static func loadFromEnvFile() -> String? {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil) else {
            print("[DEBUG] 🔍 APIKeyManager: .env file not found in bundle")
            return nil
        }
        
        guard let content = try? String(contentsOfFile: path) else {
            print("[DEBUG] ❌ APIKeyManager: Failed to read .env file")
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            if trimmed.hasPrefix("DEEPGRAM_API_KEY=") {
                let key = String(trimmed.dropFirst("DEEPGRAM_API_KEY=".count))
                let cleanKey = key.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                
                if !cleanKey.isEmpty {
                    print("[DEBUG] 🔍 APIKeyManager: Found API key in .env file")
                    return cleanKey
                }
            }
        }
        
        print("[DEBUG] 🔍 APIKeyManager: DEEPGRAM_API_KEY not found in .env file")
        return nil
    }
}

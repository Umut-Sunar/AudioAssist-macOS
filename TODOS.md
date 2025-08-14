# 🎯 AudioAssist - TODO ve İyileştirme Listesi

## 📋 Proje Durumu Özeti

**Mevcut Durum:** %70 Tamamlanmış
- ✅ **Çalışan:** Mikrofon yakalama, Sistem ses yakalama (teknik), Deepgram entegrasyonu, İzin yönetimi, UI/UX
- ❌ **Sorunlu:** Ses akışı karışıklığı, Cihaz değişikliği otomasyonu, Kod temizliği, Performance

---

## 🚨 KRİTİK SORUNLAR (ACİL)

### 1. **Çifte Ses Gönderimi Sorunu** 
**Dosya:** `AudioEngine.swift` (satır 63-78)
**Sorun:** Hem mikrofon hem sistem sesi aynı Deepgram stream'ine gönderiliyor
```swift
// MEVCUT SORUNLU KOD:
micCapture.start { [weak self] pcmData in
    self?.deepgramClient.sendPCM(pcmData)      // Mikrofon sesi
}
systemAudioCapture.onPCM16k = { [weak self] pcmData in  
    self?.deepgramClient.sendPCM(pcmData)      // Sistem sesi
}
```
**Sonuç:** Echo, ses karışması, transkripsiyon kalitesi düşüklüğü

**✅ ÇÖZÜM:**
- [ ] Ses kaynağı seçimi enum'u ekle (`AudioSource: microphone, system, mixed`)
- [ ] Kullanıcının hangi kaynağı dinlemek istediğini seçmesine izin ver
- [ ] Ayrı Deepgram bağlantıları veya channel marking sistemi

### 2. **SystemAudioTap.swift - Yanlış İmplementasyon**
**Dosya:** `SystemAudioTap.swift` (satır 281)
**Sorun:** `audioEngine.inputNode` kullanıyor - bu MİKROFON sesini yakalar, sistem sesini değil
```swift
// YANLIŞ:
let inputNode = audioEngine.inputNode  // Bu mikrofon!
```
**✅ ÇÖZÜM:**
- [ ] `SystemAudioTap.swift` dosyasını tamamen kaldır
- [ ] Sadece `SystemAudioCaptureSC.swift` kullan (doğru implementasyon)

---

## 🔧 TEMEL İYİLEŞTİRMELER (1 HAFTA)

### 3. **Cihaz Değişikliği Otomasyonu**
**Durum:** Mikrofon otomatik ✅, Hoparlör manuel ❌
**İhtiyaç:** Kullanıcı AirPods/harici hoparlör değiştirdiğinde otomatik geçiş

**✅ YAPILACAKLAR:**
- [ ] `DeviceMonitor` sınıfı oluştur
- [ ] Audio device change notification'larını izle
- [ ] SystemAudioCaptureSC'yi yeniden başlat
- [ ] UI'da aktif cihazları göster

```swift
// YENİ SINIF:
class DeviceMonitor {
    func startMonitoring() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { _ in
            self.handleDeviceChange()
        }
    }
}
```

### 4. **Kod Temizliği**
**✅ KALDIRILACAKLAR:**
- [ ] `SystemAudioTap.swift` - Yanlış implementasyon
- [ ] `Resampler.swift` - Boş implementasyon, kullanılmıyor
- [ ] Gereksiz debug log'ları production'da devre dışı bırak

**✅ İYİLEŞTİRİLECEKLER:**
- [ ] İzin kontrolü timer'ını optimize et (2s → 5s)
- [ ] Memory leak kontrolü ekle
- [ ] Error handling'i standardize et

### 5. **SystemAudioCaptureSC İyileştirmeleri**
**Dosya:** `SystemAudioCaptureSC.swift`

**✅ YAPILACAKLAR:**
- [ ] Aktif display seçimi (şu anda sadece ilk display)
```swift
// MEVCUT:
guard let display = content.displays.first else { ... }

// ÖNER İLEN:
let activeDisplay = content.displays.first { 
    $0.frame.contains(NSEvent.mouseLocation) 
} ?? content.displays.first
```
- [ ] Multi-display desteği
- [ ] Display değişikliği algılama

---

## 🎛️ YENİ ÖZELLİKLER (2 HAFTA)

### 6. **Ses Kaynağı Yönetimi**
**✅ YAPILACAKLAR:**
- [ ] Kullanıcı ses kaynağını seçebilsin (Mikrofon/Hoparlör/İkisi)
- [ ] UI'da ses seviyesi göstergesi
- [ ] Sessizlik algılama
- [ ] Otomatik gain kontrolü

```swift
// YENİ ENUM:
enum AudioSource {
    case microphone
    case system  
    case mixed
}

// YENİ SES KALİTESİ KONTROLÜ:
class AudioQualityMonitor {
    func checkAudioLevels() -> (mic: Float, system: Float)
    func detectSilence() -> Bool
    func adjustGain(for source: AudioSource)
}
```

### 7. **Akıllı Cihaz Seçimi**
**✅ YAPILACAKLAR:**
- [ ] En iyi mikrofonu otomatik seç
- [ ] En iyi hoparlörü otomatik seç  
- [ ] Cihaz kalitesi skorlaması
- [ ] Kullanıcı tercihlerini hatırla

```swift
// YENİ SİSTEM:
class SmartDeviceSelector {
    func selectOptimalMicrophone() -> AVAudioInputNode?
    func selectOptimalSpeakers() -> SCDisplay?
    func rankDevicesByQuality() -> [AudioDevice]
}
```

### 8. **Gelişmiş UI/UX**
**Dosya:** `ContentView.swift`

**✅ YAPILACAKLAR:**
- [ ] Ses kaynağı seçici toggle
- [ ] Canlı ses seviyesi göstergesi
- [ ] Aktif cihaz durumu
- [ ] Transkripsiyon kalitesi göstergesi
- [ ] Konuşmacı ayrımı görselleştirme

---

## 🔍 TEST ve DEBUG (DEVAM EDEN)

### 9. **Kapsamlı Test Sistemi**
**✅ YAPILACAKLAR:**
- [ ] Sistem ses yakalama test prosedürü
- [ ] Cihaz değişikliği test senaryoları
- [ ] Memory leak test'leri
- [ ] Performance benchmark'ları

**Test Prosedürü:**
```
1. Uygulama başlat → Console log'larını izle
2. Mikrofon test → `[DEBUG] 🎤 Mic PCM data:` mesajlarını ara
3. Sistem ses test → Müzik çal, `[SC] 🎵 Received audio:` ara
4. Cihaz değişikliği test → AirPods tak/çıkar, otomatik geçiş kontrol et
```

### 10. **Debug ve Monitoring İyileştirmeleri**
**✅ YAPILACAKLAR:**
- [ ] Structured logging sistemi
- [ ] Performance metrikleri
- [ ] Crash reporting
- [ ] Audio quality metrics

---

## 🚀 PRODUCTİON HAZIRLIĞI (3 HAFTA)

### 11. **Performance Optimizasyonu**
**✅ YAPILACAKLAR:**
- [ ] Audio processing thread optimizasyonu
- [ ] Memory kullanımı optimizasyonu  
- [ ] CPU kullanımı azaltma
- [ ] Battery life optimization

### 12. **Güvenlik ve İzinler**
**Dosya:** `AudioAssist.entitlements`, `ContentView.swift`

**✅ YAPILACAKLAR:**
- [ ] Production entitlements temizliği
- [ ] Sandbox uyumluluğu kontrolü
- [ ] Güvenlik audit
- [ ] App Store hazırlığı

### 13. **Error Handling ve Recovery**
**✅ YAPILACAKLAR:**
- [ ] Graceful degradation (sistem sesi çalışmazsa mikrofon devam etsin)
- [ ] Automatic recovery mechanisms
- [ ] User-friendly error messages
- [ ] Fallback strategies

---

## 📁 DOSYA YAPISI REORGANIZASYONU

### Mevcut Dosya Durumu:
```
✅ İyi Durumda:
- AudioEngine.swift (koordinasyon iyi, ses akışı düzeltilmeli)
- MicCapture.swift (çok iyi implementasyon)
- SystemAudioCaptureSC.swift (doğru yaklaşım, iyileştirme gerekli)
- DeepgramClient.swift (profesyonel implementasyon)
- ContentView.swift (kapsamlı UI, optimizasyon gerekli)

❌ Kaldırılacak:
- SystemAudioTap.swift (yanlış implementasyon)
- Resampler.swift (boş implementasyon)

🆕 Eklenecek:
- DeviceMonitor.swift
- AudioQualityMonitor.swift
- SmartDeviceSelector.swift
- AudioSourceManager.swift
```

---

## 🎯 PRİORİTE SIRASI

### **🚨 ACİL (1-2 Gün)**
1. Çifte ses gönderimi sorunu çöz
2. SystemAudioTap.swift'i kaldır  
3. Test prosedürü ile ses yakalama doğrula

### **🔧 ORTA VADELİ (1 Hafta)**
4. Cihaz değişikliği monitoring
5. Kod temizliği
6. SystemAudioCaptureSC iyileştirmeleri

### **🎛️ UZUN VADELİ (2-3 Hafta)**  
7. Ses kaynağı yönetimi
8. Akıllı cihaz seçimi
9. Gelişmiş UI/UX
10. Production hazırlığı

---

## 📊 İLERLEME TAKİBİ

### Tamamlanan:
- [ ] Çifte ses sorunu çözüldü
- [ ] SystemAudioTap kaldırıldı
- [ ] Cihaz monitoring eklendi
- [ ] Ses kaynağı seçimi eklendi
- [ ] UI iyileştirmeleri yapıldı
- [ ] Performance optimizasyonu
- [ ] Production release

### Notlar:
- Her major değişiklikten sonra test et
- Git commit'leri küçük ve açıklayıcı olsun
- Performance regression'ları sürekli kontrol et
- User feedback'i topla ve önceliklendir

---

**Son Güncelleme:** $(date)
**Proje Durumu:** Geliştirme Aşamasında
**Hedef Release:** TBD

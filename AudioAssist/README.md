# AudioAssist - macOS Meeting Transcription App

## Cursor "Pinned" Charter (İlk ve Kalıcı Talimat)

**Amaç:** macOS 14.4+ üzerinde sanal sürücü gerektirmeden (BlackHole yok) sistem sesi (Core Audio Taps) + mikrofon yakalayıp, 16 kHz mono Linear16 PCM'e çeviren ve Deepgram Live WebSocket'e anlık gönderen minimal Swift uygulaması. Transcript JSON'ları UI'da ve konsolda görünür.

## Teknoloji ve Kısıtlar

* **Dil/SDK:** Swift 5.9+, macOS 14.4+ (Sonoma)
* **Frameworkler:** CoreAudio, AVFAudio, URLSessionWebSocketTask
* **Üçüncü parti kütüphane yok** (yalnızca Apple frameworkleri)
* **Mock / simulated server yok** — her şey gerçek kaynaklar ve gerçek Deepgram ile
* **App Sandbox:** Kapalı (local dev)
* **Info.plist:**
  * `NSAudioCaptureUsageDescription = "Sistem sesini toplantı asistanı için yakalayacağız."`
  * `NSMicrophoneUsageDescription = "Mikrofonu toplantı asistanı için kullanacağız."`

## Deepgram Live (Güncel Ayarlar)

* **Endpoint:** `wss://api.deepgram.com/v1/listen`
* **Header:** `Authorization: Token $DEEPGRAM_API_KEY`
* **Query Parameters:**
  * `encoding=linear16&sample_rate=16000` (zorunlu birlikte)
  * `channels=1` (MVP) veya `channels=2&multichannel=true` (ileride mic+system ayrı kanal)
  * `model=nova-3`
  * `interim_results=true`, `endpointing=300`, `punctuate=true`, `smart_format=true`, `language=tr` (ihtiyaca göre)

* **Kontrol Mesajları (text frames):**
  * **KeepAlive:** sessizlikte 3–5 sn'de bir `{"type":"KeepAlive"}`
  * **Finalize:** segment finali için `{"type":"Finalize"}`
  * **CloseStream:** akışı temiz kapatma için `{"type":"CloseStream"}`; sonra WS close

## Kalite Çubukları (Done Tanımı)

* İlk çalıştırmada izin pencereleri çıkar ve onaylanır
* "Start" komutuyla: sistem sesi + mikrofon yakalanır, DG WS bağlanır, transcript akışı görünür
* **Hata/yeniden bağlanma:** WS düşerse exponential backoff ile 1s→2s→5s dene
* **Cihaz değişimi** (AirPods tak/çıkar): 200 ms içinde ilgili capture pop-free yeniden başlar
* Kodda `[DEBUG]` log'lar var; her adım derlenebilir ve manuel test adımları yazılı

## Yapılmayacaklar

* Sanal ses aygıtı kurmak (BlackHole/Soundflower)
* Sahte/audio file replays, simüle edilmiş kaynaklar
* Üçüncü parti ses/WS kütüphanesi eklemek
* Test için fake Deepgram endpoint

## Repo Yapısı

```
AudioAssist/
  AudioAssist.xcodeproj
  AudioAssist/
    App.swift (SwiftUI giriş)
    ContentView.swift (Transcript alanı + Start/Stop düğmeleri)
    Info.plist
    Sources/
      DeepgramClient.swift ✅ (Deepgram Live WebSocket)
      MicCapture.swift ✅ (AVAudioEngine + 16kHz PCM)
      SystemAudioTap.swift
      Resampler.swift
      AudioEngine.swift
  README.md
  ENVIRONMENT.md ✅ (API key setup guide)
  test_api_key.sh ✅ (API key test script)
```

## Ortam/Build Ayarları

* **Xcode Target Deployment Target:** macOS 14.4
* **Scheme Env Var:** `DEEPGRAM_API_KEY` (Dev makinede doldur)
* **App Sandbox:** Kapalı (debug için)
* **Hardened Runtime:** Dev'de gerekli değil
* **Signing:** Yerel dev (hesap zorunlu değil)

## Sprint Planı

### Sprint 1 — "Proje iskeleti + Info.plist + UI iskeleti" ✅

**Amaç:** Boş uygulama açılıyor, menü/toolbar'dan Start/Stop var, Info.plist izin metinleri hazır.

**Kabul Kriteri:** App açılır, butonlar çalışır, crash yok.

**Test:** Build & Run; Xcode konsoldaki "[DEBUG] start/stop" loglarını gör.

### Sprint 2 — "DeepgramClient v2 (güncel Live protokolü)" ✅

**Amaç:** WS bağlansın, KeepAlive/Finalize/CloseStream metin çerçeveleri, binary PCM gönderimi.

**Kabul Kriteri:** Key verildiğinde bağlanır, connected/closed/error eventleri UI/konsola düşer.

**Test:** Deepgram'a bağlan, 10 sn bekle; KeepAlive gönderildiğini ve bağlantının düşmediğini logdan gör.

### Sprint 3 — "MicCapture: AVAudioEngine + 16 kHz Linear16 dönüşüm" ✅

**Amaç:** Mikrofon izni çıkar; 16 kHz mono i16 PCM üret; DeepgramClient.sendPCM ile gönder.

**Kabul Kriteri:** Mikrofon izni penceresi çıkar; mikrofona konuşunca transcript akmaya başlar.

**Test:** Konuş, UI'da JSON/Transcript gör; sessizlikte KeepAlive yüzünden WS kapanmamalı.

### Sonraki Sprintler

1. **Sprint 4** — Sistem sesi yakalama (SystemAudioTap.swift)
2. **Sprint 5** — Audio resampling (Resampler.swift)
3. **Sprint 6** — Audio Engine koordinasyon (AudioEngine.swift)
4. **Sprint 7** — Hata yönetimi ve yeniden bağlanma
5. **Sprint 8** — Cihaz değişimi handling
7. **Sprint 9** — UI geliştirmeleri ve transcript formatting
8. **Sprint 10** — Test ve optimizasyon

## Geliştirme Notları

* Her sprint bir mesaj olacak
* Cursor'dan yalnızca o sprintin kapsamını yapmasını iste
* Her sprint "Amaç / Yap / Kabul Kriteri / Test / Sakın Yapma" bölümleri içerir
* Kodda `[DEBUG]` log'ları her adımda kullan
* Gerçek cihazlarla test et, simülasyon yok

## Çalıştırma

1. **API Key Ayarla:** [ENVIRONMENT.md](ENVIRONMENT.md) dokümanını takip ederek Deepgram API key'ini ayarla
2. Xcode'da projeyi aç
3. Build & Run
4. Mikrofon ve sistem ses izinlerini ver
5. Start butonuna bas ve Deepgram bağlantısını test et

### Environment Setup
Detaylı environment variable ayarları için [ENVIRONMENT.md](ENVIRONMENT.md) dosyasına bakın.

---

**Not:** Bu README ve charter Cursor'ın "Pinned Instruction" alanına da aynen eklenmelidir.

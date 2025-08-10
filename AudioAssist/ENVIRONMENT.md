# Environment Setup - Deepgram API Configuration

## Deepgram API Key Setup

AudioAssist uygulaması Deepgram Live API'sine bağlanmak için bir API key gerektirir. Bu key'i güvenli bir şekilde environment variable olarak ayarlamanız gerekmektedir.

### 1. Deepgram API Key Alma

1. [Deepgram Console](https://console.deepgram.com/) adresine gidin
2. Hesabınıza giriş yapın (yoksa ücretsiz hesap oluşturun)
3. Sol menüden **API Keys** seçeneğine tıklayın
4. **Create a New API Key** butonuna tıklayın
5. Key'e bir isim verin (örn: "AudioAssist-MacOS")
6. **Create Key** butonuna tıklayın
7. Oluşturulan key'i kopyalayın (örnek format: `b284403be6755d63a0c2dc440464773186b10cea`)

⚠️ **UYARI:** API key'inizi güvenli bir yerde saklayın. Bu key'i kimseyle paylaşmayın.

### 2. Xcode Environment Variable Ayarı (Önerilen)

#### Adım 1: Scheme Düzenleme
1. Xcode'da AudioAssist projesini açın
2. Üst menüden **Product** → **Scheme** → **Edit Scheme...** seçin
3. Sol panelden **Run** seçeneğine tıklayın
4. Sağ panelde **Environment Variables** sekmesine geçin

#### Adım 2: Environment Variable Ekleme
1. **+** butonuna tıklayın
2. **Name** alanına: `DEEPGRAM_API_KEY`
3. **Value** alanına Deepgram API key'inizi yapıştırın
4. **Checkmark** kutusunu işaretli bırakın
5. **Close** butonuna tıklayın

```
Name: DEEPGRAM_API_KEY
Value: b284403be6755d63a0c2dc440464773186b10cea
✓ Enabled
```

### 3. Sistem Environment Variable Ayarı (Alternatif)

#### macOS Terminal (.zshrc veya .bash_profile)

```bash
# ~/.zshrc veya ~/.bash_profile dosyasına ekleyin
export DEEPGRAM_API_KEY="b284403be6755d63a0c2dc440464773186b10cea"

# Değişiklikleri aktif etmek için:
source ~/.zshrc  # veya source ~/.bash_profile
```

#### Xcode'u Terminal'den Başlatma
```bash
# Terminal'de environment variable'ı set edin
export DEEPGRAM_API_KEY="b284403be6755d63a0c2dc440464773186b10cea"

# Xcode'u aynı terminal session'dan başlatın
open /Applications/Xcode.app
```

### 4. API Key Doğrulama

Uygulama başladığında API key'in doğru şekilde okunup okunmadığını kontrol etmek için:

1. Xcode konsolunda şu log'u arayın:
```
[DEBUG] DeepgramClient initialized with API key: ***0cea
```

2. Eğer key eksikse şu log'u göreceksiniz:
```
[DEBUG] ⚠️ DEEPGRAM_API_KEY not found in environment variables!
```

3. UI'da da "Deepgram API Key Missing" alert'i çıkacaktır.

### 5. API Key Test Etme

#### Terminal'den Hızlı Test (Önerilen)

Proje klasöründe bulunan test scriptini kullanın:

```bash
cd /path/to/AudioAssist
./test_api_key.sh
```

Bu script:
- Environment variable'ın ayarlandığını kontrol eder
- Deepgram API'sine test isteği gönderir
- API key'in geçerli olup olmadığını doğrular
- Hata durumunda detaylı yönlendirme sağlar

#### Uygulama İçinde Test

API key'inizin çalışıp çalışmadığını test etmek için:

1. **Start** butonuna basın
2. Console'da şu log'ları kontrol edin:
```
[DEBUG] 🔗 Connecting to: wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=16000...
[DEBUG] 🔑 Authorization header set: Token ***0cea
[DEBUG] ✅ WebSocket connection initiated
[DEBUG] ✅ WebSocket is now connected and receiving messages
```

3. UI'da "Deepgram: Connected" durumunu görmelisiniz
4. 5 saniyede bir KeepAlive mesajları gönderildiğini kontrol edin:
```
[DEBUG] 📤 Sent KeepAlive control message: {"type":"KeepAlive"}
```

### 6. Güvenlik Notları

- ✅ **API key'i kod içine yazmayın**
- ✅ **Environment variable kullanın**
- ✅ **API key'i version control'e (git) eklemeyin**
- ✅ **API key'i güvenli bir şekilde saklayın**
- ❌ **API key'i başkalarıyla paylaşmayın**
- ❌ **API key'i public repository'lerde paylaşmayın**

### 7. Sorun Giderme

#### Problem: "DEEPGRAM_API_KEY is missing" hatası
**Çözüm:** 
- Xcode scheme'de environment variable'ın doğru ayarlandığından emin olun
- Key'de boşluk veya özel karakter olmadığından emin olun
- Xcode'u yeniden başlatın

#### Problem: "WebSocket receive error" hatası
**Çözüm:**
- API key'in geçerli olduğundan emin olun
- Deepgram hesabınızda kredi olduğunu kontrol edin
- İnternet bağlantınızı kontrol edin

#### Problem: Bağlantı kuruluyor ama transcript gelmiyor
**Çözüm:**
- Henüz ses gönderilmiyor (Sprint 3'te mikrofon yakalama eklenecek)
- Bu normal bir durumdur, WebSocket bağlantısı çalışıyor

### 8. Deepgram Live API Parametreleri

Mevcut konfigürasyon:
```swift
- Endpoint: wss://api.deepgram.com/v1/listen
- Model: nova-2
- Language: tr (Türkçe)
- Sample Rate: 16000 Hz
- Channels: 1 (Mono)
- Encoding: linear16
- Interim Results: true
- Endpointing: 300ms
- Punctuate: true
- Smart Format: true
```

Bu parametreler `DeepgramClient.swift` dosyasındaki `DGConfig` struct'ında tanımlanmıştır ve gerektiğinde değiştirilebilir.

---

**Not:** Bu dokümantasyon Sprint 2 kapsamında hazırlanmıştır. API key doğru şekilde ayarlandıktan sonra Deepgram Live WebSocket bağlantısı tamamen çalışır durumda olacaktır.

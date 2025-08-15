# 🔧 Build Settings API Key Setup

Bu rehber, Archive modunda çalışacak şekilde Deepgram API key'ini Build Settings ile nasıl ayarlayacağınızı gösterir.

## ✅ Yapılan Değişiklikler

1. **APIKeyManager.swift** oluşturuldu - API key'i farklı kaynaklardan okur
2. **Info.plist** güncellendi - `$(DEEPGRAM_API_KEY)` placeholder eklendi
3. **makeDGConfig()** güncellendi - APIKeyManager kullanıyor
4. **DeepgramClient** güncellendi - APIKeyManager kullanıyor
5. **ContentView** güncellendi - Gelişmiş API key kontrolü ve mesajları

## 🔑 Build Settings Kurulumu

### Adım 1: Xcode'da Build Settings'i Açın

1. Xcode'da **AudioAssist** projesini açın
2. Sol panelden **AudioAssist** projesine tıklayın (en üstteki)
3. **TARGETS** altından **AudioAssist**'i seçin
4. **Build Settings** sekmesine tıklayın

### Adım 2: User-Defined Setting Ekleyin

1. Build Settings'in en altına inin
2. **User-Defined** bölümüne gelince **+** butonuna tıklayın
3. Yeni setting için şu bilgileri girin:
   ```
   Setting Name: DEEPGRAM_API_KEY
   Value: your_deepgram_api_key_here
   ```

### Adım 3: Debug ve Release İçin Ayrı Değerler (İsteğe Bağlı)

Eğer farklı environment'lar için farklı API key'ler kullanmak istiyorsanız:

1. **DEEPGRAM_API_KEY** satırının sol tarafındaki ok işaretine tıklayın
2. **Debug** ve **Release** için ayrı değerler girebilirsiniz:
   ```
   Debug: your_development_api_key
   Release: your_production_api_key
   ```

### Adım 4: APIKeyManager.swift'i Projeye Ekleyin

1. Xcode'da sol panelden **AudioAssist/Sources** klasörüne sağ tıklayın
2. **Add Files to "AudioAssist"** seçin
3. **APIKeyManager.swift** dosyasını seçin ve **Add** butonuna tıklayın

## 🧪 Test Etme

### Development'ta Test:
```bash
# Terminal'de
cd AudioAssist
xcodebuild -project AudioAssist.xcodeproj -scheme AudioAssist -configuration Debug
```

### Archive'da Test:
1. Xcode'da **Product** → **Archive** yapın
2. Archive tamamlandığında **Distribute App** → **Copy App** seçin
3. Kopyalanan `.app` dosyasını çalıştırın
4. Console'da şu log'u göreceksiniz:
   ```
   [DEBUG] 🔑 APIKeyManager: API Key loaded from Info.plist: ***xxxx
   ```

## 🔍 API Key Durumu Kontrolü

Uygulama şu sırayla API key arar:

1. **Info.plist** (Build Settings'den gelen değer) - Archive modunda çalışır
2. **Environment Variables** - Development modunda çalışır  
3. **Bundle içi .env dosyası** - Fallback olarak

Console'da şu log'ları göreceksiniz:
```
[DEBUG] 🔑 APIKeyManager: API Key loaded from Info.plist: ***1234
[ContentView] 🔍 API Key Status: hasKey=true, source=Info.plist, key=***1234
```

## ❌ Sorun Giderme

### Problem: "No API key found in any source"
**Çözüm:**
1. Build Settings'te `DEEPGRAM_API_KEY` değerinin doğru girildiğinden emin olun
2. Xcode'u temizleyin: **Product** → **Clean Build Folder**
3. Projeyi yeniden build edin

### Problem: "API Key loaded from environment" (Archive'da)
**Çözüm:**
- Bu normal, Development modunda environment variable'lar öncelikli
- Archive modunda Info.plist devreye girecek

### Problem: Build Settings'te User-Defined bölümü yok
**Çözüm:**
1. Build Settings'te sağ üst köşedeki **All** ve **Combined** seçeneklerini seçin
2. En alta inin, **User-Defined** bölümü görünecek

## 🎯 Başarı Göstergeleri

✅ **Development modunda:**
```
[DEBUG] 🔑 APIKeyManager: API Key loaded from environment: ***xxxx
```

✅ **Archive modunda:**
```
[DEBUG] 🔑 APIKeyManager: API Key loaded from Info.plist: ***xxxx
```

✅ **UI'da API key alert'i çıkmıyor**

✅ **Deepgram bağlantısı başarılı:**
```
[DEBUG] 🔗 Connecting to: wss://api.deepgram.com/v1/listen...
[DEBUG] ✅ WebSocket connection initiated
```

## 🔒 Güvenlik Notları

- ✅ API key Build Settings'te saklanır (version control'e girmez)
- ✅ Info.plist'te sadece placeholder var: `$(DEEPGRAM_API_KEY)`
- ✅ Kod içinde hardcode API key yok
- ✅ Console'da maskelenmiş key gösterilir: `***1234`

---

**Kurulum tamamlandığında hem Development hem de Archive modunda API key çalışacaktır! 🎉**

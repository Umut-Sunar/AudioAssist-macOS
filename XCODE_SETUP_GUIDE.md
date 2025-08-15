# 🔧 Xcode Setup Guide - AudioAssist Çoklu Instance ve API Key Sorunu

Bu rehber, AudioAssist'in çoklu instance açılması ve API key sorunlarını çözmek için gerekli Xcode ayarlarını adım adım açıklar.

## 📋 **1. Environment Variable Ayarı (API Key)**

### Adım 1.1: Scheme Düzenleme
1. Xcode'da AudioAssist projesini açın
2. **Product** menüsü → **Scheme** → **Edit Scheme...** seçin
3. Sol panelde **Run** seçin
4. Sağ panelde **Arguments** sekmesine geçin
5. **Environment Variables** bölümünü bulun

### Adım 1.2: API Key Ekleme
1. **Environment Variables** bölümünde **"+"** butonuna tıklayın
2. **Name:** `DEEPGRAM_API_KEY`
3. **Value:** `b284403be6755d63a0c2dc440464773186b10cea`
4. **Checkmark** kutucuğunu işaretli bırakın
5. **Close** butonuna tıklayın

## 🛠️ **2. Build Script Ekleme (Otomatik Kopyalama)**

### Adım 2.1: Build Phases Açma
1. Xcode'da projeyi seçin (sol panelde en üstteki AudioAssist)
2. **AudioAssist** target'ını seçin (ortadaki panelde)
3. **Build Phases** sekmesine geçin

### Adım 2.2: Script Ekleme
1. Sol üstteki **"+"** butonuna tıklayın
2. **New Run Script Phase** seçin
3. Yeni oluşan **Run Script** bölümünü genişletin
4. **Shell** alanında `/bin/bash` yazılı olduğundan emin olun
5. **Script** alanına şunu yazın:
```bash
${PROJECT_DIR}/AudioAssist/xcode_build_script.sh
```

### Adım 2.3: Script Sıralaması
1. Yeni eklenen **Run Script** fazını sürükleyerek **Compile Sources**'tan sonraya taşıyın
2. Sıralama şöyle olmalı:
   - Compile Sources
   - **Run Script** (yeni eklediğiniz)
   - Copy Bundle Resources

## ⚙️ **3. Debug Ayarları Optimizasyonu**

### Adım 3.1: Scheme Debug Ayarları
1. **Product** → **Scheme** → **Edit Scheme...**
2. **Run** → **Info** sekmesi
3. **Launch** ayarını **"Wait for the executable to be launched"** yerine **"Automatically"** seçin
4. **Debug executable** kutucuğunu **İŞARETLİ** bırakın (bu normal)

### Adım 3.2: Build Settings Kontrolü
1. Proje seçili iken **Build Settings** sekmesine geçin
2. **Search** alanına `PRODUCT_BUNDLE_IDENTIFIER` yazın
3. Değerin `com.dogan.audioassist` olduğundan emin olun
4. **Search** alanına `CODE_SIGN_STYLE` yazın
5. **Automatic** seçili olduğundan emin olun

## 🔒 **4. Entitlements Kontrolü**

### Dosya Kontrolü
`AudioAssist.entitlements` dosyasında şunlar olmalı:
```xml
<key>com.apple.security.app-sandbox</key>
<false/>

<key>com.apple.security.device.audio-input</key>
<true/>

<key>com.apple.security.network.client</key>
<true/>
```

## 🧪 **5. Test Prosedürü**

### Adım 5.1: Temizlik
1. **Product** → **Clean Build Folder** (`Cmd+Shift+K`)
2. Xcode'u kapatın
3. Terminal'de cleanup script'ini çalıştırın:
```bash
./cleanup_and_reset.sh
```

### Adım 5.2: Build ve Test
1. Xcode'u tekrar açın
2. **Product** → **Build** (`Cmd+B`)
3. Build loglarında şu mesajları arayın:
```
🔧 AudioAssist Build Script Starting...
✅ Successfully copied to Applications
```

### Adım 5.3: Run ve Doğrulama
1. **Product** → **Run** (`Cmd+R`)
2. Console'da şu mesajları arayın:
```
[AppDelegate] 🚀 Application launching...
[AppDelegate] ✅ Single instance guarantee applied
[APIKeyManager] ✅ API Key found in ENVIRONMENT: ***10cea
```

## 🚨 **Troubleshooting**

### Sorun: Build script çalışmıyor
**Çözüm:**
```bash
# Script'in executable olduğundan emin olun
chmod +x AudioAssist/xcode_build_script.sh

# Script yolunu kontrol edin
ls -la AudioAssist/xcode_build_script.sh
```

### Sorun: API key bulunamıyor
**Çözüm:**
1. Scheme → Environment Variables'ı tekrar kontrol edin
2. Xcode'u restart edin
3. Console'da `[APIKeyManager]` loglarını takip edin

### Sorun: Hala çoklu instance açılıyor
**Çözüm:**
1. Activity Monitor'da tüm AudioAssist process'lerini kapatın
2. `/Applications/AudioAssist.app` varsa silin
3. Cleanup script'ini çalıştırın
4. Xcode'da Clean Build yapın

### Sorun: İzin verilmiyor
**Çözüm:**
1. System Settings → Privacy & Security → Screen Recording
2. AudioAssist'i listede bulun
3. Yoksa "+" ile `/Applications/AudioAssist.app` ekleyin
4. Kutucuğu işaretleyin
5. Uygulamayı restart edin

## ✅ **Başarı Kriterleri**

Build ve run sonrası şunları görmelisiniz:
- ✅ Sadece **tek pencere** açılır
- ✅ Console'da **tek instance** mesajı
- ✅ **API key bulundu** mesajı
- ✅ **İzin verildi** mesajı
- ✅ **/Applications/ klasöründe** uygulama mevcut

## 📝 **Notlar**

- Bu ayarlar **development build** için optimize edilmiştir
- **Production/Archive** build'lerde farklı ayarlar gerekebilir
- **macOS Sequoia** kullanıyorsanız haftalık izin yenileme gerekebilir
- Build script her **Debug** build'de otomatik çalışacaktır

## 🆘 **Destek**

Sorun devam ederse:
1. Console.app'i açın
2. "AudioAssist" arayın
3. Hata mesajlarını kaydedin
4. Activity Monitor'da process'leri kontrol edin

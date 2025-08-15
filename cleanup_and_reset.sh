#!/bin/bash

echo "🧹 AudioAssist Complete Cleanup & Reset Script"
echo "=============================================="
echo "Bu script şunları yapacak:"
echo "1. Tüm AudioAssist instance'larını kapatır"
echo "2. DerivedData'yı temizler"
echo "3. TCC izinlerini sıfırlar"
echo "4. Cache'leri temizler"
echo "5. Sistem ayarlarını açar"
echo ""

# Confirmation
read -p "Devam etmek istiyor musunuz? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "İptal edildi."
    exit 1
fi

echo ""
echo "🚀 Cleanup başlıyor..."

# Bundle ID
BUNDLE_ID="com.dogan.audioassist"
APP_NAME="AudioAssist"

# 1. Tüm AudioAssist instance'larını kapat
echo "🔪 1. Tüm AudioAssist instance'larını kapatıyor..."
pkill -9 -f "${APP_NAME}" || echo "   Çalışan instance bulunamadı"
sleep 2

# Process kontrolü
REMAINING=$(pgrep -f "${APP_NAME}" | wc -l)
if [ "$REMAINING" -gt 0 ]; then
    echo "   ⚠️ Hala ${REMAINING} process çalışıyor, force kill yapıyor..."
    pkill -9 -f "${APP_NAME}"
    sleep 1
fi

echo "   ✅ Tüm instance'lar kapatıldı"

# 2. DerivedData'yı temizle
echo "🗑️ 2. DerivedData'yı temizliyor..."
DERIVED_DATA_PATH=~/Library/Developer/Xcode/DerivedData/AudioAssist-*
if ls ${DERIVED_DATA_PATH} 1> /dev/null 2>&1; then
    rm -rf ${DERIVED_DATA_PATH}
    echo "   ✅ DerivedData temizlendi"
else
    echo "   ℹ️ DerivedData bulunamadı"
fi

# ModuleCache'i de temizle
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex 2>/dev/null || true
echo "   ✅ ModuleCache temizlendi"

# 3. TCC izinlerini sıfırla
echo "🔒 3. TCC izinlerini sıfırlıyor (sudo gerekli)..."

# Screen Recording
echo "   - Screen Recording izni sıfırlanıyor..."
sudo tccutil reset ScreenCapture "${BUNDLE_ID}" 2>/dev/null || echo "   ⚠️ ScreenCapture reset başarısız"

# Microphone
echo "   - Microphone izni sıfırlanıyor..."
sudo tccutil reset Microphone "${BUNDLE_ID}" 2>/dev/null || echo "   ⚠️ Microphone reset başarısız"

# Camera
echo "   - Camera izni sıfırlanıyor..."
sudo tccutil reset Camera "${BUNDLE_ID}" 2>/dev/null || echo "   ⚠️ Camera reset başarısız"

# All permissions (if available)
echo "   - Tüm izinleri sıfırlıyor..."
sudo tccutil reset All "${BUNDLE_ID}" 2>/dev/null || echo "   ⚠️ All reset başarısız (normal)"

echo "   ✅ TCC izinleri sıfırlandı"

# 4. App cache'lerini temizle
echo "🧹 4. Uygulama cache'lerini temizliyor..."

# App caches
rm -rf ~/Library/Caches/"${BUNDLE_ID}" 2>/dev/null && echo "   ✅ App caches temizlendi" || echo "   ℹ️ App caches bulunamadı"

# Saved application state
rm -rf ~/Library/Saved\ Application\ State/"${BUNDLE_ID}".savedState/ 2>/dev/null && echo "   ✅ Saved state temizlendi" || echo "   ℹ️ Saved state bulunamadı"

# App preferences
rm -rf ~/Library/Preferences/"${BUNDLE_ID}".plist 2>/dev/null && echo "   ✅ Preferences temizlendi" || echo "   ℹ️ Preferences bulunamadı"

# Containers
rm -rf ~/Library/Containers/"${BUNDLE_ID}" 2>/dev/null && echo "   ✅ Containers temizlendi" || echo "   ℹ️ Containers bulunamadı"

# 5. Applications klasöründeki eski versiyonu kaldır
echo "📱 5. Applications klasöründeki eski versiyonu kontrol ediyor..."
if [ -d "/Applications/${APP_NAME}.app" ]; then
    rm -rf "/Applications/${APP_NAME}.app"
    echo "   ✅ Eski versiyon kaldırıldı"
else
    echo "   ℹ️ Applications'da eski versiyon bulunamadı"
fi

# 6. TCC daemon'unu yeniden başlat (mümkünse)
echo "🔄 6. TCC daemon'unu yenilemeye çalışıyor..."
sudo pkill -f tccd 2>/dev/null && echo "   ✅ TCC daemon yenilendi" || echo "   ℹ️ TCC daemon restart edilemedi"
sleep 2

# 7. macOS version detection
MACOS_VERSION=$(sw_vers -productVersion | cut -d '.' -f 1)
echo "🍎 7. macOS Version: $(sw_vers -productVersion)"

# 8. Sistem ayarlarını aç
echo "⚙️ 8. Sistem ayarlarını açıyor..."

if [ "$MACOS_VERSION" -ge 15 ]; then
    # macOS Sequoia (15.0+)
    echo "   macOS Sequoia için System Settings açılıyor..."
    open "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture" 2>/dev/null || \
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null
elif [ "$MACOS_VERSION" -ge 13 ]; then
    # macOS 13+ (Ventura ve Sonoma)
    echo "   macOS 13+ için System Settings açılıyor..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null
else
    # Older macOS versions
    echo "   Eski macOS için System Preferences açılıyor..."
    open "/System/Library/PreferencePanes/Security.prefPane" 2>/dev/null
fi

echo ""
echo "🎉 Cleanup tamamlandı!"
echo "================================"
echo ""
echo "📋 ŞİMDİ YAPMANIZ GEREKENLER:"
echo ""
echo "1. 🔧 XCODE AYARLARI:"
echo "   • Xcode'da projeyi açın"
echo "   • Product → Scheme → Edit Scheme → Run → Environment Variables"
echo "   • Ekleyin: DEEPGRAM_API_KEY = b284403be6755d63a0c2dc440464773186b10cea"
echo ""
echo "2. 🛠️ BUILD SCRIPT EKLEYİN:"
echo "   • Xcode'da Target → Build Phases → '+' → New Run Script Phase"
echo "   • Script içeriği: \$(PROJECT_DIR)/AudioAssist/xcode_build_script.sh"
echo ""
echo "3. 🔒 İZİN VERİN:"
echo "   • Açılan System Settings/Preferences'ta"
echo "   • Privacy & Security → Screen Recording"
echo "   • AudioAssist'i bulun veya '+' ile ekleyin"
echo "   • Kutucuğu işaretleyin"
echo ""
echo "4. 🚀 TEST EDİN:"
echo "   • Xcode'da Clean Build: Cmd+Shift+K"
echo "   • Build: Cmd+B"
echo "   • Run: Cmd+R"
echo ""

if [ "$MACOS_VERSION" -ge 15 ]; then
    echo "🍎 macOS Sequoia Not:"
    echo "   • Haftalık izin yenileme gerekebilir"
    echo "   • Uygulamayı /Applications/ klasöründe tutun"
    echo ""
fi

echo "✅ Hazırsınız! Artık tek instance çalışacak ve API key sorunu çözülecek."
echo ""

#!/bin/bash

# AudioAssist Xcode Build Phase Script
# Bu script her build'de otomatik çalışır ve:
# 1. Eski instance'ları kapatır
# 2. Uygulamayı /Applications/ klasörüne kopyalar
# 3. İzinleri düzeltir
# 4. API key'i environment'a ekler

echo "🔧 AudioAssist Build Script Starting..."

# Build configuration kontrolü
echo "📋 Build Configuration: ${CONFIGURATION}"
echo "📁 Built Products Dir: ${BUILT_PRODUCTS_DIR}"
echo "🎯 Product Name: ${PRODUCT_NAME}"

# Sadece Debug build'lerde çalıştır (Release'de gereksiz)
if [ "${CONFIGURATION}" != "Debug" ]; then
    echo "✅ Skipping script for non-Debug build"
    exit 0
fi

# App paths
APP_NAME="AudioAssist"
SOURCE_APP="${BUILT_PRODUCTS_DIR}/${APP_NAME}.app"
DEST_APP="/Applications/${APP_NAME}.app"

echo "📦 Source App: ${SOURCE_APP}"
echo "📍 Destination: ${DEST_APP}"

# 1. Eski instance'ları kapat
echo "🔪 Terminating existing AudioAssist instances..."
pkill -f "${APP_NAME}" || echo "   No existing instances found"
sleep 1

# 2. Uygulamanın build edildiğini kontrol et
if [ ! -d "${SOURCE_APP}" ]; then
    echo "❌ Source app not found: ${SOURCE_APP}"
    exit 1
fi

echo "✅ Source app found: ${SOURCE_APP}"

# 3. Eski versiyonu kaldır
if [ -d "${DEST_APP}" ]; then
    echo "🗑️ Removing existing app in Applications..."
    rm -rf "${DEST_APP}"
fi

# 4. Yeni versiyonu kopyala
echo "📋 Copying app to Applications folder..."
cp -R "${SOURCE_APP}" "${DEST_APP}"

if [ $? -eq 0 ]; then
    echo "✅ Successfully copied to Applications"
else
    echo "❌ Failed to copy to Applications"
    exit 1
fi

# 5. İzinleri düzelt
echo "🔧 Fixing permissions..."
chmod -R 755 "${DEST_APP}"

# 6. Code signing (development için)
echo "🔐 Attempting to codesign..."
codesign --force --deep --sign - "${DEST_APP}" 2>/dev/null || echo "   ⚠️ Codesigning failed (normal for development builds)"

# 7. Bundle ID'yi kontrol et
BUNDLE_ID=$(defaults read "${DEST_APP}/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)
echo "🆔 Bundle ID: ${BUNDLE_ID}"

# 8. API key environment'ını kontrol et
if [ -n "${DEEPGRAM_API_KEY}" ]; then
    echo "🔑 API Key environment variable is set: ***${DEEPGRAM_API_KEY: -4}"
else
    echo "⚠️ DEEPGRAM_API_KEY environment variable is not set"
    echo "💡 Make sure to set it in Xcode Scheme: Product → Scheme → Edit Scheme → Run → Environment Variables"
fi

# 9. Başarı mesajı
echo "🎉 Build script completed successfully!"
echo "📍 App is now available at: ${DEST_APP}"
echo "💡 You can now run the app from Applications folder for consistent permissions"

# 10. İsteğe bağlı: Applications klasöründeki uygulamayı başlat
# Uncomment the line below if you want to auto-launch from Applications
# open "${DEST_APP}"

echo "✅ AudioAssist Build Script Finished"

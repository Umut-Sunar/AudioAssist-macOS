#!/bin/bash

# Test script for Deepgram API Key
# Usage: ./test_api_key.sh

echo "🔍 Testing Deepgram API Key..."
echo ""

# Check if DEEPGRAM_API_KEY is set
if [ -z "$DEEPGRAM_API_KEY" ]; then
    echo "❌ DEEPGRAM_API_KEY environment variable is not set!"
    echo ""
    echo "Please set it using one of these methods:"
    echo ""
    echo "1. Export in current session:"
    echo "   export DEEPGRAM_API_KEY=\"your_api_key_here\""
    echo ""
    echo "2. Add to ~/.zshrc or ~/.bash_profile:"
    echo "   echo 'export DEEPGRAM_API_KEY=\"your_api_key_here\"' >> ~/.zshrc"
    echo "   source ~/.zshrc"
    echo ""
    echo "3. Set in Xcode Scheme (recommended for development):"
    echo "   Product → Scheme → Edit Scheme → Run → Environment Variables"
    echo "   Name: DEEPGRAM_API_KEY"
    echo "   Value: your_api_key_here"
    echo ""
    exit 1
fi

# Mask the API key for display (show only last 4 characters)
MASKED_KEY="***${DEEPGRAM_API_KEY: -4}"
echo "✅ DEEPGRAM_API_KEY is set: $MASKED_KEY"
echo ""

# Test API key with a simple curl request
echo "🌐 Testing API key with Deepgram API..."
echo ""

# Create a simple test request to Deepgram
RESPONSE=$(curl -s -w "%{http_code}" -X GET \
  "https://api.deepgram.com/v1/projects" \
  -H "Authorization: Token $DEEPGRAM_API_KEY" \
  -H "Content-Type: application/json" \
  -o /tmp/deepgram_test_response.json)

HTTP_CODE="${RESPONSE: -3}"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ API Key is valid! Deepgram API responded successfully."
    echo ""
    echo "🚀 You can now run the AudioAssist app in Xcode."
    echo "   The app will automatically use this API key for WebSocket connections."
elif [ "$HTTP_CODE" = "401" ]; then
    echo "❌ API Key is invalid! Received 401 Unauthorized."
    echo ""
    echo "Please check your API key:"
    echo "1. Make sure you copied it correctly from Deepgram Console"
    echo "2. Verify the key hasn't expired"
    echo "3. Check that the key has the necessary permissions"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "❌ API Key is valid but lacks permissions! Received 403 Forbidden."
    echo ""
    echo "Please check your Deepgram account:"
    echo "1. Ensure you have credits available"
    echo "2. Verify the API key has Live API permissions"
else
    echo "⚠️  Received HTTP code: $HTTP_CODE"
    echo ""
    echo "Response details:"
    cat /tmp/deepgram_test_response.json 2>/dev/null || echo "No response body"
fi

echo ""
echo "📚 For more information, see ENVIRONMENT.md"

# Cleanup
rm -f /tmp/deepgram_test_response.json

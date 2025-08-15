#!/bin/bash

echo "🔑 DEEPGRAM API KEY SETUP"
echo "========================"
echo ""
echo "DEEPGRAM_API_KEY is required for speech-to-text functionality."
echo "The app can still work in mic-only mode without it, but no transcripts will appear."
echo ""

# Check if API key is already set
if [ ! -z "$DEEPGRAM_API_KEY" ]; then
    echo "✅ DEEPGRAM_API_KEY is already set: ***$(echo $DEEPGRAM_API_KEY | tail -c 5)"
    echo "You can skip this setup."
    exit 0
fi

echo "❌ DEEPGRAM_API_KEY is not set in your environment."
echo ""
echo "OPTIONS:"
echo "1. Set it temporarily for this session only"
echo "2. Set it permanently in your shell profile"
echo "3. Set it in Xcode scheme (recommended for development)"
echo "4. Skip setup (app will work in mic-only mode without transcripts)"
echo ""

read -p "Choose option (1-4): " -n 1 -r
echo
echo ""

case $REPLY in
    1)
        echo "📝 TEMPORARY SETUP (current session only):"
        echo "Enter your Deepgram API key (it will not be displayed):"
        read -s api_key
        if [ ! -z "$api_key" ]; then
            export DEEPGRAM_API_KEY="$api_key"
            echo "✅ DEEPGRAM_API_KEY set for this session"
            echo "   Masked key: ***$(echo $api_key | tail -c 5)"
            echo ""
            echo "⚠️  This will be lost when you close the terminal."
            echo "   To make it permanent, choose option 2 next time."
        else
            echo "❌ No API key entered"
        fi
        ;;
    2)
        echo "📝 PERMANENT SETUP (added to ~/.zshrc):"
        echo "Enter your Deepgram API key (it will not be displayed):"
        read -s api_key
        if [ ! -z "$api_key" ]; then
            echo "" >> ~/.zshrc
            echo "# Deepgram API Key for AudioAssist" >> ~/.zshrc
            echo "export DEEPGRAM_API_KEY=\"$api_key\"" >> ~/.zshrc
            echo "✅ DEEPGRAM_API_KEY added to ~/.zshrc"
            echo "   Masked key: ***$(echo $api_key | tail -c 5)"
            echo ""
            echo "🔄 To apply changes, run: source ~/.zshrc"
            echo "   Or restart your terminal"
        else
            echo "❌ No API key entered"
        fi
        ;;
    3)
        echo "📝 XCODE SCHEME SETUP (recommended for development):"
        echo ""
        echo "1. In Xcode, go to: Product → Scheme → Edit Scheme..."
        echo "2. Select 'Run' in the left sidebar"
        echo "3. Go to 'Arguments' tab"
        echo "4. In 'Environment Variables' section, click '+'"
        echo "5. Add:"
        echo "   Name: DEEPGRAM_API_KEY"
        echo "   Value: [your_deepgram_api_key]"
        echo "6. Check the checkbox to enable it"
        echo "7. Click 'Close'"
        echo ""
        echo "This method keeps the API key in Xcode only and doesn't affect your system."
        ;;
    4)
        echo "⏭️  SKIPPING API KEY SETUP"
        echo ""
        echo "The app will work in mic-only mode:"
        echo "✅ Microphone audio will be captured"
        echo "❌ No speech-to-text transcripts will appear"
        echo "❌ System audio capture requires Screen Recording permission"
        echo ""
        echo "You can set up the API key later using this script."
        ;;
    *)
        echo "❌ Invalid option selected"
        exit 1
        ;;
esac

echo ""
echo "🎉 Setup completed!"

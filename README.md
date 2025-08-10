# AudioAssist - macOS Meeting Audio Capture

AudioAssist is a macOS application that captures both microphone and system audio (speakers/headphones) and provides real-time transcription using Deepgram's speech-to-text API.

## Features

- 🎤 **Microphone Capture**: Records audio from your microphone
- 🔊 **System Audio Capture**: Records audio from speakers/headphones using ScreenCaptureKit
- 🗣️ **Real-time Transcription**: Live speech-to-text using Deepgram API
- 🔒 **Permission Management**: Automatic handling of macOS audio and screen recording permissions
- 📝 **Live Transcript Display**: Real-time display of transcribed text with confidence scores

## Requirements

- macOS 13.0+ (for ScreenCaptureKit system audio capture)
- Xcode 15.0+
- Deepgram API Key

## Setup

### 1. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/AudioAssist-macOS.git
cd AudioAssist-macOS
```

### 2. Get Deepgram API Key
1. Sign up at [Deepgram](https://deepgram.com)
2. Get your API key from the dashboard

### 3. Configure API Key
In Xcode:
1. Go to **Product → Scheme → Edit Scheme**
2. Select **Run** in the left sidebar
3. Go to **Environment Variables** tab
4. Add: `DEEPGRAM_API_KEY` = `your_api_key_here`

### 4. Configure Signing
1. Open the project in Xcode
2. Select the **AudioAssist** target
3. Go to **Signing & Capabilities**
4. Select your **Development Team**
5. Ensure **Automatically manage signing** is checked

## Permissions

The app requires the following macOS permissions:

- **Microphone Access**: For recording microphone audio
- **Screen Recording**: For capturing system audio via ScreenCaptureKit

The app will automatically request these permissions and guide you through the setup process.

## Usage

1. Launch the application
2. Grant required permissions when prompted
3. Click **Start** to begin audio capture and transcription
4. Speak or play audio - you'll see real-time transcription
5. Click **Stop** to end the session

## Architecture

- **AudioEngine.swift**: Main audio processing coordinator
- **MicCapture.swift**: Microphone audio capture using AVAudioEngine
- **SystemAudioCaptureSC.swift**: System audio capture using ScreenCaptureKit
- **DeepgramClient.swift**: WebSocket client for Deepgram API integration
- **ContentView.swift**: SwiftUI interface with permission management

## Technical Details

- **Audio Format**: 48kHz mono Int16 PCM for optimal Deepgram compatibility
- **Real-time Processing**: Low-latency audio capture and streaming
- **Permission Handling**: Robust macOS permission management with user guidance
- **Error Handling**: Comprehensive error logging and user feedback

## Known Issues

- Video frame drop warnings from ScreenCaptureKit are normal and don't affect audio capture
- In meetings, simultaneous microphone and system audio capture may cause echo - use headphones to prevent this

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions, please open an issue on GitHub.

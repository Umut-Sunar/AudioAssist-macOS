import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

@available(macOS 13.0, *)
final class SystemAudioCaptureSC: NSObject, SCStreamOutput, SCStreamDelegate {

    // Dışarı: 16 kHz, mono, Int16 PCM
    var onPCM16k: ((Data) -> Void)?

    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "sc.audio.queue")
    private var converter: AVAudioConverter?

    // Hedef format: 48kHz, mono, Int16 interleaved (Deepgram ile uyumlu)
    private let outFmt = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48_000,
        channels: 1,
        interleaved: true
    )!

    // MARK: - Public
    
    /// Check screen recording permission and optionally request it
    func checkPermissions() async -> Bool {
        print("[SC] 🔒 Checking screen recording permission...")
        
        // Check current permission status
        let hasScreenPermission = CGPreflightScreenCaptureAccess()
        
        if hasScreenPermission {
            print("[SC] ✅ Screen recording permission granted")
            return true
        } else {
            print("[SC] ❌ Screen recording permission denied")
            print("[SC] 🔒 Attempting to request permission...")
            
            // Try to request permission - this should make app appear in System Preferences
            let granted = CGRequestScreenCaptureAccess()
            print("[SC] 🔒 Permission request result: \(granted ? "✅ Granted" : "❌ Still denied")")
            
            if !granted {
                print("[SC] 💡 Please enable manually in System Preferences:")
                print("[SC] 💡 Security & Privacy → Privacy → Screen Recording")
                print("[SC] 💡 Find 'AudioAssist' in the list and check the box")
                print("[SC] 💡 You may need to restart the app after granting permission")
            }
            
            return granted
        }
    }

    func start() async throws {
        print("[SC] 🚀 Starting SystemAudioCaptureSC...")
        
        // Check permissions first
        let hasPermission = await checkPermissions()
        guard hasPermission else {
            let error = NSError(domain: "SC", code: -2, 
                              userInfo: [NSLocalizedDescriptionKey: "Screen recording permission denied"])
            print("[SC] ❌ Permission denied: \(error.localizedDescription)")
            throw error
        }
        
        print("[SC] 🚀 requesting shareable content…")
        let content = try await SCShareableContent.current
        
        // 🔍 Debug: Mevcut içeriği logla
        print("[SC] 📺 Available displays: \(content.displays.count)")
        for (index, display) in content.displays.enumerated() {
            print("[SC] 📺 Display \(index): ID=\(display.displayID), Frame=\(display.frame)")
        }
        
        print("[SC] 📱 Available applications: \(content.applications.count)")
        print("[SC] 🪟 Available windows: \(content.windows.count)")

        guard let display = content.displays.first else {
            print("[SC] ❌ No displays found!")
            throw NSError(domain: "SC", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No displays found"])
        }

        print("[SC] 🎯 Using display: ID=\(display.displayID)")

        // 👇 Etiket sırasına dikkat: excludingApplications, exceptingWindows
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true        // ✅ var
        // cfg.capturesVideo = false     // ❌ böyle bir alan yok, ekleme
        cfg.sampleRate = 48_000
        cfg.channelCount = 2            // sistem miks genelde stereo
        
        // 🔍 Debug: Konfigürasyonu detaylı logla
        print("[SC] ⚙️ Stream Configuration:")
        print("[SC] ⚙️   - capturesAudio: \(cfg.capturesAudio)")
        print("[SC] ⚙️   - sampleRate: \(cfg.sampleRate) Hz")
        print("[SC] ⚙️   - channelCount: \(cfg.channelCount) channels")
        print("[SC] ⚙️   - Output format: \(outFmt.sampleRate) Hz, \(outFmt.channelCount) ch, \(outFmt.commonFormat.rawValue)")

        print("[SC] 🔧 Creating SCStream...")
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        
        print("[SC] 🔧 Adding stream output...")
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        
        print("[SC] 🔧 Starting capture...")
        try await s.startCapture()
        self.stream = s

        print("[SC] ✅ SystemAudioCaptureSC started successfully!")
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        converter = nil
        print("[SC] ⏹️ stopped")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {

        guard type == .audio else { 
            print("[SC] ⚠️ Received non-audio type: \(type)")
            return 
        }
        
        guard CMSampleBufferDataIsReady(sampleBuffer) else { 
            print("[SC] ⚠️ Sample buffer data not ready")
            return 
        }

        // 🔍 Debug: Ses verisi detayları
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let durationSeconds = CMTimeGetSeconds(duration)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampSeconds = CMTimeGetSeconds(timestamp)
        
        print("[SC] 🎵 Audio received: \(sampleCount) samples, duration: \(String(format: "%.3f", durationSeconds))s, timestamp: \(String(format: "%.3f", timestampSeconds))s")

        // Giriş formatını çıkar
        guard let fd = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fd) else { 
            print("[SC] ❌ Failed to get format description")
            return 
        }

        var asbd = asbdPtr.pointee
        guard let inFmt = AVAudioFormat(streamDescription: &asbd) else { 
            print("[SC] ❌ Failed to create input format")
            return 
        }

        // Converter yoksa/format değiştiyse oluştur
        if converter == nil || converter?.inputFormat != inFmt {
            print("[SC] 🔄 Creating new converter...")
            print("[SC] 🔄 Input format: \(inFmt)")
            print("[SC] 🔄 Output format: \(outFmt)")
            
            converter = AVAudioConverter(from: inFmt, to: outFmt)
            if converter != nil {
                print("[SC] ✅ Converter created successfully")
            } else {
                print("[SC] ❌ Failed to create converter")
                return
            }
        }
        guard let converter = converter else { return }

        // CMSampleBuffer -> AVAudioPCMBuffer
        guard let inBuf = sampleBuffer.makePCMBuffer(format: inFmt) else { return }

        // Çıkış buffer'ı
        let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * outFmt.sampleRate / inFmt.sampleRate)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCap) else { return }

        var err: NSError?
        _ = converter.convert(to: outBuf, error: &err) { _, outStatus in
            outStatus.pointee = .haveData
            return inBuf
        }
        if let err { print("[SC] ❌ convert error: \(err.localizedDescription)"); return }

        // Int16 veriyi Data'ya çevir
        guard let ch = outBuf.int16ChannelData?.pointee else { return }
        let byteCount = Int(outBuf.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: ch, count: byteCount)

        // 🔊 dışarı yayınla
        onPCM16k?(data)
        print("[SC] 📤 Sent \(data.count) bytes to callback (48kHz mono Int16: \(data.count/2) samples)")
    }

    // MARK: - SCStreamDelegate

    // Optional @objc method — uyarı olmaması için @objc şart
    @objc func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[SC] ❌ Stream stopped with error: \(error.localizedDescription)")
        print("[SC] 🔍 Error details: \(error)")
    }
}

// MARK: - Helpers

@available(macOS 13.0, *)
private extension CMSampleBuffer {
    /// CMSampleBuffer içindeki ses verisini AVAudioPCMBuffer'a kopyalar
    func makePCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames

        var block: CMBlockBuffer?
        var abl = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: format.channelCount,
                                  mDataByteSize: 0,
                                  mData: nil)
        )

        let st = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &block
        )
        if st != noErr { return nil }

        let src = abl.mBuffers

        // 🔧 AVAudioPCMBuffer'ın MUTABLE ABL'sini al
        let dstABLPtr = buf.mutableAudioBufferList
        
        // AudioBufferList'in mNumberBuffers kontrolü
        if dstABLPtr.pointee.mNumberBuffers > 0 {
            // İlk buffer'a erişim
            dstABLPtr.pointee.mBuffers.mNumberChannels = src.mNumberChannels
            dstABLPtr.pointee.mBuffers.mDataByteSize = src.mDataByteSize

            if dstABLPtr.pointee.mBuffers.mData == nil {
                dstABLPtr.pointee.mBuffers.mData = malloc(Int(src.mDataByteSize))
            }
            if let dst = dstABLPtr.pointee.mBuffers.mData, let s = src.mData {
                memcpy(dst, s, Int(src.mDataByteSize))
            }
        }
        return buf
    }
}
@preconcurrency import AVFoundation

/// Captures microphone audio using AVAudioEngine.
/// NOT @MainActor - installTap callback runs on the audio thread.
final class AudioCaptureManager: Sendable {
    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16000

    // Use nonisolated(unsafe) for callbacks set from main actor
    nonisolated(unsafe) var onAudioData: (@Sendable (Data) -> Void)?
    nonisolated(unsafe) var onAudioLevel: (@Sendable (Float) -> Void)?
    /// Raw PCM buffer before format conversion — used by Apple STT
    nonisolated(unsafe) var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func startCapture() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }

        let levelCb = onAudioLevel
        let dataCb = onAudioData
        let bufferCb = onAudioBuffer
        let tgtRate = targetSampleRate

        // installTap callback runs on a real-time audio thread - must be nonisolated
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            // Raw buffer for Apple STT
            bufferCb?(buffer)

            // Audio level for waveform
            let rms = Self.calculateRMS(buffer: buffer)
            levelCb?(rms)

            // Convert to Linear16 PCM 16kHz mono
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * tgtRate / buffer.format.sampleRate
            )
            guard frameCapacity > 0 else { return }
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

            var error: NSError?
            let src = buffer
            var consumed = false
            converter.convert(to: converted, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return src
            }
            guard error == nil else { return }
            guard let int16 = converted.int16ChannelData else { return }
            let data = Data(bytes: int16[0], count: Int(converted.frameLength) * 2)
            dataCb?(data)
        }

        engine.prepare()
        try engine.start()
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { let s = data[0][i]; sum += s * s }
        return min(1.0, sqrt(sum / Float(count)) * 5.0)
    }
}

enum AudioError: Error, LocalizedError {
    case formatCreationFailed
    case converterCreationFailed
    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Failed to create audio format"
        case .converterCreationFailed: return "Failed to create audio converter"
        }
    }
}

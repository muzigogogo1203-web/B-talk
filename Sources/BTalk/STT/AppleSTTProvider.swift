import Foundation
import Speech
import AVFoundation

/// STT provider using Apple's built-in SFSpeechRecognizer.
/// No API key required. Supports Chinese (zh-CN) and other locales.
final class AppleSTTProvider: STTProvider {
    private let language: String

    nonisolated(unsafe) private var recognizer: SFSpeechRecognizer?
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?
    nonisolated(unsafe) private var task: SFSpeechRecognitionTask?
    nonisolated(unsafe) private var latestTranscript: String = ""
    nonisolated(unsafe) private var isFinalReceived: Bool = false
    nonisolated(unsafe) private var streamContinuation: AsyncStream<STTResult>.Continuation?

    init(language: String = "zh-CN") {
        self.language = language
    }

    func startStreaming(language: String) async throws -> AsyncStream<STTResult> {
        let lang = language.isEmpty ? self.language : language

        // Request Speech Recognition permission
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { s in cont.resume(returning: s) }
        }
        guard status == .authorized else {
            throw AppleSTTError.notAuthorized
        }

        let locale = Locale(identifier: lang)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AppleSTTError.recognizerNotAvailable
        }
        self.recognizer = recognizer

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req
        latestTranscript = ""
        isFinalReceived = false

        return AsyncStream { [weak self] continuation in
            guard let self = self else { continuation.finish(); return }
            self.streamContinuation = continuation

            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.latestTranscript = text
                    let confidence = result.bestTranscription.segments.first?.confidence ?? 1.0
                    continuation.yield(STTResult(text: text, isFinal: result.isFinal, confidence: confidence))
                    if result.isFinal {
                        self.isFinalReceived = true
                        continuation.finish()
                    }
                }
                if let error = error {
                    let code = (error as NSError).code
                    // 216 = recognition canceled, 301 = no speech detected — ignore
                    if code != 216 && code != 301 { continuation.finish() }
                }
            }
        }
    }

    func sendAudioData(_ data: Data) async throws {
        // Apple STT receives raw AVAudioPCMBuffer via sendAudioBuffer, not Data
    }

    /// Called by AppDelegate with the raw AVAudioPCMBuffer from AudioCaptureManager.
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stopStreaming() async throws -> String {
        request?.endAudio()
        // Poll every 100ms until isFinal arrives, with a 4-second timeout
        for _ in 0..<40 {
            if isFinalReceived { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // Extra 300ms if we got interim but no final (in case final is still in-flight)
        if !latestTranscript.isEmpty && !isFinalReceived {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        let result = latestTranscript
        cleanup()
        return result
    }

    private func cleanup() {
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        streamContinuation?.finish()
        streamContinuation = nil
        latestTranscript = ""
        isFinalReceived = false
    }
}

enum AppleSTTError: Error, LocalizedError {
    case notAuthorized
    case recognizerNotAvailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech Recognition not authorized. Please grant permission in System Settings → Privacy & Security → Speech Recognition."
        case .recognizerNotAvailable:
            return "Speech recognizer not available for the selected language."
        }
    }
}

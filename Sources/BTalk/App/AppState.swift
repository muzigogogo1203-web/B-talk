import SwiftUI
import Combine

enum AppMode: String, Equatable {
    case idle
    case recording
    case finalizing
    case transcribing
    case structuring
    case showingResult
    case showingError
}

@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .idle
    @Published var interimTranscript: String = ""
    @Published var finalTranscript: String = ""
    @Published var structuredResult: String = ""
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0.0
    @Published var transcriptQualityLow: Bool = false

    var isRecording: Bool { mode == .recording }
    var isProcessing: Bool { mode == .transcribing || mode == .structuring || mode == .finalizing }

    func toggleRecording() {
        switch mode {
        case .idle:
            mode = .recording
            interimTranscript = ""
            finalTranscript = ""
            structuredResult = ""
            errorMessage = nil
        case .recording:
            mode = .finalizing
        default:
            break
        }
    }

    func setTranscribing() {
        mode = .transcribing
    }

    func setStructuring(transcript: String) {
        finalTranscript = transcript
        mode = .structuring
    }

    func setResult(_ result: String) {
        structuredResult = result
        mode = .showingResult
        // Auto-copy to clipboard so it's always available
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func setError(_ message: String) {
        // Only surface error if we're in an active workflow (not already showing a result)
        guard mode != .showingResult else { return }
        errorMessage = message
        mode = .showingError
    }

    func reset() {
        mode = .idle
        interimTranscript = ""
        finalTranscript = ""
        structuredResult = ""
        errorMessage = nil
        audioLevel = 0.0
        transcriptQualityLow = false
    }
}

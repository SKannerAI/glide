import Foundation
import GlideCore

/// Bridges live speech to a script position: feeds transcripts into the
/// `VoiceAligner` and publishes a 0...1 progress fraction the teleprompter
/// turns into a scroll target.
@MainActor
final class VoiceEngine: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var progress: Double = 0
    @Published var permissionDenied = false

    private let transcriber: Transcriber
    private let aligner: VoiceAligner

    init(scriptText: String) {
        transcriber = SFSpeechTranscriber()
        aligner = VoiceAligner(text: scriptText)
        transcriber.onTranscript = { [weak self] text in
            Task { @MainActor in self?.ingest(text) }
        }
    }

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func start() async {
        let ok = await transcriber.requestAuthorization()
        guard ok else { permissionDenied = true; return }
        permissionDenied = false
        do {
            try transcriber.start()
            isListening = true
        } catch {
            isListening = false
        }
    }

    func stop() {
        transcriber.stop()
        isListening = false
    }

    /// Restart from the top: reset the aligner and clear the recognizer's
    /// accumulated transcript so tracking begins fresh.
    func reset() {
        aligner.reset()
        progress = 0
        if isListening { transcriber.restartRecognition() }
    }

    private func ingest(_ text: String) {
        aligner.advance(transcript: ScriptTokenizer.tokenize(text))
        progress = aligner.progress
    }
}

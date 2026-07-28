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
        GlideLog.reset()
        let ok = await transcriber.requestAuthorization()
        GlideLog.log("voice.start authorized=\(ok)")
        guard ok else { permissionDenied = true; return }
        permissionDenied = false
        do {
            try transcriber.start()
            isListening = true
            GlideLog.log("voice listening; script tokens=\(aligner.count)")
        } catch {
            isListening = false
            GlideLog.log("transcriber.start threw: \(error)")
        }
    }

    func stop() {
        transcriber.stop()
        isListening = false
    }

    private func ingest(_ text: String) {
        aligner.advance(transcript: ScriptTokenizer.tokenize(text))
        progress = aligner.progress
        GlideLog.log("ingest '…\(text.suffix(40))' idx=\(aligner.index)/\(aligner.count) prog=\(String(format: "%.2f", progress))")
    }
}

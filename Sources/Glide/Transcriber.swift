import Foundation
import Speech
import AVFoundation

protocol Transcriber: AnyObject {
    var onTranscript: ((String) -> Void)? { get set }
    func requestAuthorization() async -> Bool
    func start() throws
    func stop()
}

enum TranscriberError: Error { case unavailable }

/// `SFSpeechRecognizer`-backed transcriber. On-device when supported, and it
/// auto-restarts the recognition task to work around the framework's ~1-minute
/// per-task limit. The `Transcriber` protocol lets a `SpeechAnalyzer` (macOS 26)
/// or WhisperKit backend drop in later without touching the rest of the app.
final class SFSpeechTranscriber: NSObject, Transcriber {
    var onTranscript: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var running = false

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return speech && mic
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else { throw TranscriberError.unavailable }
        running = true
        try startTask()
    }

    private func startTask() throws {
        guard let recognizer else { throw TranscriberError.unavailable }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onTranscript?(result.bestTranscription.formattedString)
            }
            // The framework stops tasks after ~1 minute; restart to keep going.
            if error != nil || (result?.isFinal ?? false) {
                self.restart()
            }
        }
    }

    private func restart() {
        guard running else { return }
        teardownAudio()
        try? startTask()
    }

    func stop() {
        running = false
        teardownAudio()
        task?.cancel()
        task = nil
    }

    private func teardownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        request = nil
    }
}

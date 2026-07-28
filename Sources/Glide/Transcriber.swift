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
    private var bufferCount = 0

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return speech && mic
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            GlideLog.log("transcriber: recognizer unavailable (nil=\(recognizer == nil))")
            throw TranscriberError.unavailable
        }
        GlideLog.log("transcriber.start onDevice=\(recognizer.supportsOnDeviceRecognition)")
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
        bufferCount = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.bufferCount += 1
            if self.bufferCount % 40 == 0 {
                GlideLog.log("tap buffers=\(self.bufferCount) rms=\(String(format: "%.4f", Self.rms(buffer)))")
            }
        }
        engine.prepare()
        try engine.start()
        GlideLog.log("audio engine started; out=\(Int(format.sampleRate))Hz/\(format.channelCount)ch in=\(Int(input.inputFormat(forBus: 0).sampleRate))Hz")

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onTranscript?(result.bestTranscription.formattedString)
            }
            if let error { GlideLog.log("recog error: \(error.localizedDescription)") }
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

    /// Rough signal level of a capture buffer (handles float or int16).
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        if let ch = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            return (sum / Float(n)).squareRoot()
        }
        if let ch = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<n { let s = Float(ch[i]) / 32768; sum += s * s }
            return (sum / Float(n)).squareRoot()
        }
        return -1  // unknown format
    }

    private func teardownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        request = nil
    }
}

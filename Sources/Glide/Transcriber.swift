import Foundation
import Speech
import AVFoundation

protocol Transcriber: AnyObject {
    var onTranscript: ((String) -> Void)? { get set }
    func requestAuthorization() async -> Bool
    func start() throws
    func restartRecognition()
    func stop()
}

enum TranscriberError: Error { case unavailable }

/// `SFSpeechRecognizer`-backed transcriber. On-device when supported. The audio
/// engine + tap run continuously; recognition requests are swapped in as needed
/// (for the ~1-minute task cap and for restart-from-top), which avoids engine
/// churn. Each task carries an `epoch` so stale callbacks can't tear down a
/// newer task. The `Transcriber` protocol lets a `SpeechAnalyzer`/WhisperKit
/// backend drop in later.
final class SFSpeechTranscriber: NSObject, Transcriber {
    var onTranscript: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var running = false
    private var epoch = 0
    private var bufferCount = 0

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return speech && mic
    }

    func start() throws {
        guard recognizer?.isAvailable == true else {
            throw TranscriberError.unavailable
        }
        running = true
        bufferCount = 0
        try startEngine()
        startRecognition()
        scheduleColdStartKick()
    }

    /// Install the tap, then start the engine. The tap is always in place before
    /// the engine starts — starting a tapless engine throws in `prepare()`.
    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.bufferCount += 1
        }
        engine.prepare()
        try engine.start()
    }

    /// On a cold launch the first engine start sometimes delivers no audio. If
    /// nothing arrives shortly, restart the engine once (tap re-installed first)
    /// — the same recovery a manual mic re-toggle performs, done automatically.
    private func scheduleColdStartKick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.running, self.bufferCount == 0 else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            if self.engine.isRunning { self.engine.stop() }
            try? self.startEngine()
        }
    }

    /// Begin a fresh recognition request/task, keeping the engine + tap alive.
    /// Also clears the accumulated transcript.
    private func startRecognition() {
        guard running, let recognizer else { return }
        epoch += 1
        let myEpoch = epoch
        task?.cancel()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.epoch == myEpoch else { return }  // ignore stale callbacks
                if let result { self.onTranscript?(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true {
                    self.startRecognition()  // ~1-min cap or end-of-utterance
                }
            }
        }
    }

    /// Restart from the top: swap in a fresh request (clears transcript) without
    /// disturbing the running audio engine.
    func restartRecognition() {
        guard running else { return }
        request?.endAudio()
        startRecognition()
    }

    func stop() {
        running = false
        epoch += 1  // invalidate any in-flight callbacks
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}

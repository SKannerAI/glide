import Foundation
import AVFoundation
import Speech

/// Picks the best available speech backend for the running OS: Apple's newer
/// on-device `SpeechAnalyzer` (macOS 26+, continuous, no 1-minute cap) when
/// available, otherwise the `SFSpeechRecognizer` path.
func makeTranscriber() -> Transcriber {
    if #available(macOS 26, *) {
        return SpeechAnalyzerTranscriber()
    } else {
        return SFSpeechTranscriber()
    }
}

/// `SpeechAnalyzer` + `SpeechTranscriber` backend (macOS 26+). Reuses the same
/// AVAudioEngine mic-capture shape as the SF path, converting buffers to the
/// analyzer's format and streaming them in; emits a running transcript string.
@available(macOS 26, *)
final class SpeechAnalyzerTranscriber: Transcriber {
    var onTranscript: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private var running = false

    private var finalizedText = ""
    private var volatileText = ""

    func requestAuthorization() async -> Bool {
        // On-device transcription; request Speech + mic defensively.
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return speech && mic
    }

    func start() throws {
        running = true
        finalizedText = ""
        volatileText = ""

        // Tap installed before the engine starts (never a tapless engine).
        let input = engine.inputNode
        let tapFormat = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            self?.feed(buffer)
        }
        engine.prepare()
        try engine.start()

        // Build the analyzer pipeline asynchronously (model install, format, etc.).
        setupTask = Task { [weak self] in await self?.setupPipeline() }
    }

    private func setupPipeline() async {
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        // Install the language model on first use for this locale.
        do {
            let installed = await SpeechTranscriber.installedLocales
            let want = resolved.identifier(.bcp47)
            if !installed.contains(where: { $0.identifier(.bcp47) == want }),
               let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            // Proceed anyway — may already be usable.
        }

        guard running else { return }

        let analyzer = SpeechAnalyzer(modules: [transcriber], options: nil)
        self.analyzer = analyzer
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        resultsTask = Task { [weak self] in
            guard let self, let transcriber = self.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    self.handle(result)
                }
            } catch {
                // stream ended / cancelled
            }
        }

        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = builder
        do { try await analyzer.start(inputSequence: stream) } catch { }
    }

    /// Called from the audio tap. Converts to the analyzer format and streams in.
    private func feed(_ buffer: AVAudioPCMBuffer) {
        guard running, let inputBuilder, let analyzerFormat else { return }
        let out: AVAudioPCMBuffer
        if buffer.format == analyzerFormat {
            out = buffer
        } else {
            if converter == nil { converter = AVAudioConverter(from: buffer.format, to: analyzerFormat) }
            guard let converter, let converted = Self.convert(buffer, converter, analyzerFormat) else { return }
            out = converted
        }
        inputBuilder.yield(AnalyzerInput(buffer: out))
    }

    private func handle(_ result: SpeechTranscriber.Result) {
        let piece = String(result.text.characters)
        if result.isFinal {
            finalizedText += finalizedText.isEmpty ? piece : " " + piece
            volatileText = ""
        } else {
            volatileText = piece
        }
        let text = volatileText.isEmpty ? finalizedText
            : (finalizedText.isEmpty ? volatileText : finalizedText + " " + volatileText)
        onTranscript?(text)
    }

    /// Restart from the top: tear down the analyzer pipeline and rebuild it
    /// (clears the transcript). The engine + tap keep running.
    func restartRecognition() {
        guard running else { return }
        inputBuilder?.finish(); inputBuilder = nil
        resultsTask?.cancel(); resultsTask = nil
        setupTask?.cancel(); setupTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        transcriber = nil
        finalizedText = ""
        volatileText = ""
        setupTask = Task { [weak self] in await self?.setupPipeline() }
    }

    func stop() {
        running = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        inputBuilder?.finish(); inputBuilder = nil
        resultsTask?.cancel(); resultsTask = nil
        setupTask?.cancel(); setupTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        transcriber = nil
        converter = nil
        analyzerFormat = nil
    }

    /// Convert a capture buffer to the analyzer's format (handles sample-rate change).
    private static func convert(_ input: AVAudioPCMBuffer,
                                _ converter: AVAudioConverter,
                                _ format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else { return nil }
        return output
    }
}

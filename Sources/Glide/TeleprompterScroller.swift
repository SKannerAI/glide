import SwiftUI
import GlideCore

@MainActor
final class TeleprompterScroller: ObservableObject {
    @Published var offset: Double = 0
    @Published var isPlaying = false
    /// When true, `target` is driven by voice progress instead of constant pace.
    var voiceMode = false

    var contentHeight: Double = 0
    var viewportHeight: Double = 0
    var pointsPerSecond: Double = 60

    private var target: Double = 0
    private var velocity: Double = 0
    private var timer: Timer?
    private var lastTick = Date()
    private var manualHoldUntil = Date.distantPast

    private var maxOffset: Double { max(0, contentHeight - viewportHeight) }

    func start() {
        guard timer == nil else { return }
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func togglePlay() { isPlaying.toggle() }

    func restart() {
        offset = 0
        target = 0
        velocity = 0
        isPlaying = true
    }

    /// User grabbed the scroll — jump there and suspend auto-advance briefly.
    func manualScrub(to newOffset: Double) {
        let clamped = clamp(newOffset)
        offset = clamped
        target = clamped
        velocity = 0
        manualHoldUntil = Date().addingTimeInterval(2.0)
        GlideLog.log("manualScrub -> \(Int(clamped)) (req \(Int(newOffset)), maxOff \(Int(maxOffset)))")
    }

    func nudge(_ dy: Double) { manualScrub(to: offset + dy) }

    /// Voice-follow: set the scroll target from a 0...1 script-progress fraction.
    /// Ignored briefly after a manual scrub so the user's grab wins.
    func setVoiceTarget(_ fraction: Double) {
        guard voiceMode, Date() >= manualHoldUntil else { return }
        target = clamp(fraction * maxOffset)
        GlideLog.log("setVoiceTarget frac=\(String(format: "%.2f", fraction)) maxOff=\(Int(maxOffset)) target=\(Int(target)) contentH=\(Int(contentHeight)) vp=\(Int(viewportHeight))")
    }

    private func tick() {
        let now = Date()
        let dt = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now

        if isPlaying && !voiceMode && now >= manualHoldUntil {
            target = min(maxOffset, target + pointsPerSecond * dt)
        }
        offset = clamp(smoothDamp(current: offset, target: target,
                                  velocity: &velocity, smoothTime: 0.25, dt: dt))

        if isPlaying && offset >= maxOffset - 0.5 && target >= maxOffset {
            isPlaying = false
        }
    }

    private func clamp(_ v: Double) -> Double { min(max(0, v), maxOffset) }
}

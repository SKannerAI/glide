import SwiftUI

/// Unity-style critically-damped spring. Phase 2 drives `target` at a constant
/// pace; Phase 3 (voice) will set `target` to the matched script position — the
/// same smoothing serves both.
func smoothDamp(current: Double, target: Double, velocity: inout Double,
                smoothTime: Double, dt: Double) -> Double {
    let smoothTime = max(0.0001, smoothTime)
    let omega = 2 / smoothTime
    let x = omega * dt
    let expo = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    let change = current - target
    let temp = (velocity + omega * change) * dt
    velocity = (velocity - omega * temp) * expo
    var output = target + (change + temp) * expo
    // Prevent overshoot past the target.
    if (target - current > 0) == (output > target) {
        output = target
        velocity = (output - target) / dt
    }
    return output
}

@MainActor
final class TeleprompterScroller: ObservableObject {
    @Published var offset: Double = 0
    @Published var isPlaying = false

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
    }

    func nudge(_ dy: Double) { manualScrub(to: offset + dy) }

    private func tick() {
        let now = Date()
        let dt = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now

        if isPlaying && now >= manualHoldUntil {
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

import Foundation

/// Unity-style critically-damped spring. Moves `current` toward `target`
/// without overshoot; `velocity` is carried across calls. Phase 2 advances
/// `target` at a constant pace; Phase 3 sets `target` to the voice-matched
/// script position — the same smoothing serves both.
public func smoothDamp(current: Double, target: Double, velocity: inout Double,
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

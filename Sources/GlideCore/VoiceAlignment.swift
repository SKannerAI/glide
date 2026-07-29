import Foundation

/// Splits text into normalized word tokens (lowercased, punctuation-stripped).
public enum ScriptTokenizer {
    public static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

/// Tracks a speaker's position in a script by matching the tail of the live
/// transcript against a window of script tokens using multiset ("bag of
/// words") overlap. Tolerant of ad-libs, filler, re-reads, and STT errors.
public final class VoiceAligner {
    private let script: [String]
    public private(set) var index: Int = 0

    /// How far back/forward from the current index to search each step.
    public var searchBack: Int = 5
    public var searchForward: Int = 10
    /// Number of trailing spoken words compared against the script.
    public var window: Int = 6
    /// Minimum overlap (as a fraction of the window) required to move.
    public var minScoreRatio: Double = 0.34
    /// Penalty per token of distance from the current position. Makes the
    /// tracker prefer nearby matches, so a repeated word far away must match
    /// distinctly better to win (prevents jumping between duplicate words).
    public var distancePenalty: Double = 0.35

    public init(script: [String]) { self.script = script }
    public convenience init(text: String) { self.init(script: ScriptTokenizer.tokenize(text)) }

    public var count: Int { script.count }
    public var progress: Double {
        script.isEmpty ? 0 : min(1, Double(index) / Double(script.count))
    }

    public func reset() { index = 0 }

    /// Advances the position from the latest transcript. Returns the new index.
    @discardableResult
    public func advance(transcript spoken: [String]) -> Int {
        guard !script.isEmpty, !spoken.isEmpty else { return index }

        let recent = Array(spoken.suffix(window))
        let w = recent.count
        let recentSet = Self.multiset(recent)

        let lo = max(0, index - searchBack)
        let hi = min(script.count - 1, index + searchForward)

        var bestScore = -Double.greatestFiniteMagnitude
        var bestStart = index
        var bestOverlap = 0
        var start = lo
        while start <= hi {
            let end = min(script.count, start + w)
            let overlap = Self.overlap(recentSet, Self.multiset(Array(script[start..<end])))
            // Overlap, discounted by distance from the current position.
            let score = Double(overlap) - distancePenalty * Double(abs(start - index))
            if score > bestScore {
                bestScore = score
                bestStart = start
                bestOverlap = overlap
            }
            start += 1
        }

        let threshold = max(1, Int((Double(w) * minScoreRatio).rounded()))
        if bestOverlap >= threshold {
            index = min(script.count, bestStart + w)
        }
        return index
    }

    static func multiset(_ words: [String]) -> [String: Int] {
        var d: [String: Int] = [:]
        for x in words { d[x, default: 0] += 1 }
        return d
    }

    static func overlap(_ a: [String: Int], _ b: [String: Int]) -> Int {
        var s = 0
        for (k, v) in a { s += min(v, b[k] ?? 0) }
        return s
    }
}

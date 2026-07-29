import Foundation
import GlideCore

// Minimal assertion harness (XCTest is unavailable under Command Line Tools).
var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") } else { print("  ✗ FAIL: \(msg)"); failures += 1 }
}
func checkEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    check(a == b, "\(msg) — got \(a), want \(b)")
}
func checkClose(_ a: Double, _ b: Double, _ eps: Double, _ msg: String) {
    check(abs(a - b) <= eps, "\(msg) — got \(a), want ~\(b)")
}

let scriptText = """
The quick brown fox jumps over the lazy dog near the river bank at dawn \
while birds sing softly.
"""
let tokens = ScriptTokenizer.tokenize(scriptText)

print("VoiceAligner:")
checkEqual(tokens.first, "the", "tokenizer lowercases")
checkEqual(tokens.count, 19, "tokenizer count")
checkEqual(tokens.last, "softly", "tokenizer strips trailing punctuation")

do {
    let a = VoiceAligner(text: scriptText)
    a.advance(transcript: Array(tokens.prefix(8)))
    checkEqual(a.index, 8, "on-script reading advances to spoken position")
}
do {
    let a = VoiceAligner(text: scriptText)
    a.advance(transcript: ["the", "quick", "brown", "um", "you", "know", "fox", "jumps"])
    check((6...8).contains(a.index), "ad-libs/filler don't derail tracking (index \(a.index))")
}
do {
    let a = VoiceAligner(text: scriptText)
    a.advance(transcript: ["near", "the", "river", "bank", "at", "dawn"])
    checkEqual(a.index, 15, "skip-ahead jumps forward")
}
do {
    let a = VoiceAligner(text: scriptText)
    a.advance(transcript: ["xyzzy", "foobar", "plugh"])
    checkEqual(a.index, 0, "garbage speech doesn't move")
}
do {
    // "manager" repeats at indices 1 and 8.
    let rep = "the manager approved the plan then later the manager rejected the appeal after review"
    let a = VoiceAligner(text: rep)
    a.advance(transcript: ["the", "manager", "approved"])
    check(a.index <= 5, "repeated word: stays at first occurrence (idx \(a.index))")
    a.advance(transcript: ["the", "manager", "approved", "the", "plan", "then",
                           "later", "the", "manager", "rejected"])
    check(a.index >= 8, "repeated word: advances to 2nd occurrence when read through (idx \(a.index))")
}
do {
    let a = VoiceAligner(text: scriptText)
    a.advance(transcript: Array(tokens.prefix(4)))
    let first = a.index
    a.advance(transcript: Array(tokens.prefix(10)))
    check(a.index >= first, "progress is monotonic")
    checkEqual(a.index, 10, "continued reading tracks position")
}
do {
    let a = VoiceAligner(text: scriptText)
    a.advance(transcript: Array(tokens.prefix(8)))
    checkClose(a.progress, 8.0 / 19.0, 0.001, "progress fraction")
}
do {
    let a = VoiceAligner(text: scriptText)
    a.advance(transcript: [])
    checkEqual(a.index, 0, "empty transcript is safe")
    let empty = VoiceAligner(text: "")
    empty.advance(transcript: ["anything"])
    checkEqual(empty.index, 0, "empty script is safe")
}

print("SmoothDamp:")
do {
    var current = 0.0, velocity = 0.0, maxSeen = 0.0
    for _ in 0..<600 {
        current = smoothDamp(current: current, target: 100, velocity: &velocity,
                             smoothTime: 0.25, dt: 1.0 / 60.0)
        maxSeen = max(maxSeen, current)
    }
    checkClose(current, 100, 0.5, "converges to target")
    check(maxSeen <= 100.001, "no overshoot (max \(maxSeen))")
}
do {
    var current = 50.0, velocity = 0.0
    for _ in 0..<120 {
        current = smoothDamp(current: current, target: 50, velocity: &velocity,
                             smoothTime: 0.25, dt: 1.0 / 60.0)
    }
    checkClose(current, 50, 0.0001, "stays at target")
}
do {
    var current = 0.0, velocity = 0.0
    let next = smoothDamp(current: current, target: 100, velocity: &velocity,
                          smoothTime: 0.25, dt: 1.0 / 60.0)
    check(next > current && next < 100, "moves toward target")
}

print(failures == 0 ? "\n✅ All checks passed." : "\n❌ \(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)

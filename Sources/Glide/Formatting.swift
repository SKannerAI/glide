import SwiftUI

enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable {
    case leading, center
    var id: String { rawValue }
    var textAlignment: TextAlignment { self == .center ? .center : .leading }
    var frameAlignment: Alignment { self == .center ? .center : .leading }
    var label: String { self == .center ? "Center" : "Left" }
}

/// Global teleprompter formatting + scroll preferences. Persisted separately
/// from the script library so the Phase 1 schema stays untouched.
struct PromptSettings: Codable, Equatable {
    var fontSize: Double = 44
    var lineSpacing: Double = 14
    var horizontalPadding: Double = 80
    var mirror: Bool = false
    var wordsPerMinute: Double = 130
    var textColorHex: String = "#FFFFFF"
    var backgroundHex: String = "#0A0A0A"
    var alignment: TextAlignmentOption = .leading
    var overlayOpacity: Double = 0.9
    var overlayAlwaysOnTop: Bool = true
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

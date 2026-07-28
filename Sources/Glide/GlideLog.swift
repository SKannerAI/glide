import Foundation

/// Tiny append-only debug log at ~/Library/Application Support/Glide/debug.log.
/// Temporary diagnostics for the voice pipeline.
enum GlideLog {
    static let url: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glide", isDirectory: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func reset() {
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    static func log(_ msg: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

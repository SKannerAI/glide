import Foundation

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

struct Script: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var body: String = ""
    var folderID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// On-disk container. JSON persistence stands in for SwiftData until a full
/// Xcode toolchain is available (the @Model macro ships only with Xcode).
struct Library: Codable {
    var scripts: [Script] = []
    var folders: [Folder] = []
}

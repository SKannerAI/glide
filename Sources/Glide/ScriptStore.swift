import Foundation
import SwiftUI

@MainActor
final class ScriptStore: ObservableObject {
    @Published var scripts: [Script] = []
    @Published var folders: [Folder] = []
    @Published var selectedScriptID: UUID?
    @Published var searchText: String = ""

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glide", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            load()
        } else {
            seedWelcome()
        }
        if selectedScriptID == nil {
            selectedScriptID = filteredScripts.first?.id
        }
    }

    // MARK: - Derived

    var filteredScripts: [Script] {
        let base = searchText.isEmpty
            ? scripts
            : scripts.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.body.localizedCaseInsensitiveContains(searchText)
            }
        return base.sorted { $0.updatedAt > $1.updatedAt }
    }

    func scripts(in folder: Folder?) -> [Script] {
        filteredScripts.filter { $0.folderID == folder?.id }
    }

    /// A binding into a script by id; edits bump `updatedAt` and autosave.
    func scriptBinding(_ id: UUID) -> Binding<Script> {
        Binding(
            get: { self.scripts.first(where: { $0.id == id }) ?? Script() },
            set: { newValue in
                guard let i = self.scripts.firstIndex(where: { $0.id == id }) else { return }
                var v = newValue
                v.updatedAt = Date()
                self.scripts[i] = v
                self.scheduleSave()
            }
        )
    }

    // MARK: - Mutations

    func newScript(in folderID: UUID? = nil) {
        var s = Script()
        s.folderID = folderID
        scripts.append(s)
        selectedScriptID = s.id
        scheduleSave()
    }

    func deleteScript(_ id: UUID) {
        scripts.removeAll { $0.id == id }
        if selectedScriptID == id { selectedScriptID = filteredScripts.first?.id }
        scheduleSave()
    }

    func move(_ scriptID: UUID, to folderID: UUID?) {
        guard let i = scripts.firstIndex(where: { $0.id == scriptID }) else { return }
        scripts[i].folderID = folderID
        scripts[i].updatedAt = Date()
        scheduleSave()
    }

    func newFolder() {
        folders.append(Folder(name: "New Folder"))
        scheduleSave()
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name.isEmpty ? "Untitled Folder" : name
        scheduleSave()
    }

    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for i in scripts.indices where scripts[i].folderID == id {
            scripts[i].folderID = nil
        }
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let lib = try? Self.decoder.decode(Library.self, from: data) else { return }
        scripts = lib.scripts
        folders = lib.folders
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let lib = Library(scripts: scripts, folders: folders)
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            guard let data = try? Self.encoder.encode(lib) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func seedWelcome() {
        let s = Script(
            title: "Welcome to Glide",
            body: """
            This is your first script.

            Edit it right here. Create more with the + button in the sidebar, \
            and drop them into folders to stay organized.

            Voice-activated scrolling and the floating overlay come in later phases.
            """
        )
        scripts = [s]
        selectedScriptID = s.id
        scheduleSave()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

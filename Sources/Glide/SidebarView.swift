import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: ScriptStore
    @State private var renamingFolder: Folder?
    @State private var renameText: String = ""

    var body: some View {
        List(selection: $store.selectedScriptID) {
            Section("Scripts") {
                let unfiled = store.scripts(in: nil)
                if unfiled.isEmpty {
                    Text("No scripts")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                }
                ForEach(unfiled) { scriptRow($0) }
            }

            ForEach(store.folders) { folder in
                Section {
                    ForEach(store.scripts(in: folder)) { scriptRow($0) }
                } header: {
                    folderHeader(folder)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search scripts")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        store.newScript()
                    } label: {
                        Label("New Script", systemImage: "doc.badge.plus")
                    }
                    Button {
                        store.newFolder()
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Rename Folder", isPresented: renamingBinding) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Rename") {
                if let f = renamingFolder { store.renameFolder(f.id, to: renameText) }
                renamingFolder = nil
            }
        }
    }

    private func scriptRow(_ s: Script) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.title.isEmpty ? "Untitled" : s.title)
                .lineLimit(1)
            Text(s.body.replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .tag(s.id)
        .contextMenu {
            Menu("Move to") {
                Button("None") { store.move(s.id, to: nil) }
                Divider()
                ForEach(store.folders) { f in
                    Button(f.name) { store.move(s.id, to: f.id) }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { store.deleteScript(s.id) }
        }
    }

    private func folderHeader(_ folder: Folder) -> some View {
        HStack {
            Label(folder.name, systemImage: "folder")
            Spacer()
        }
        .contextMenu {
            Button("Rename…") {
                renameText = folder.name
                renamingFolder = folder
            }
            Button("Delete Folder", role: .destructive) {
                store.deleteFolder(folder.id)
            }
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ScriptStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if let id = store.selectedScriptID,
               store.scripts.contains(where: { $0.id == id }) {
                EditorView(script: store.scriptBinding(id))
                    .id(id)
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "doc.text",
                    description: Text("Select a script in the sidebar, or press ⌘N to create one.")
                )
            }
        }
    }
}

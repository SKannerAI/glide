import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ScriptStore
    @StateObject private var overlay = OverlayController()
    @State private var presenting: Script?
    @State private var clickThrough = false

    private var selectedScript: Script? {
        guard let id = store.selectedScriptID else { return nil }
        return store.scripts.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if let id = store.selectedScriptID,
               store.scripts.contains(where: { $0.id == id }) {
                EditorView(script: store.scriptBinding(id)) { presenting = $0 }
                    .id(id)
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "doc.text",
                    description: Text("Select a script in the sidebar, or press ⌘N to create one.")
                )
            }
        }
        .overlay {
            if let script = presenting {
                TeleprompterView(script: script) { presenting = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: presenting)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(overlay.isOpen ? "Close Overlay" : "Open Overlay") {
                        if overlay.isOpen {
                            overlay.close()
                        } else if let script = selectedScript {
                            presenting = nil                    // avoid two teleprompters at once
                            overlay.open(script: script, store: store)
                            overlay.setClickThrough(clickThrough)
                        }
                    }
                    Divider()
                    Toggle("Always on Top", isOn: alwaysOnTopBinding)
                    Toggle("Click-through", isOn: clickThroughBinding)
                } label: {
                    Image(systemName: overlay.isOpen ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
                }
                .help("Floating overlay (opacity slider is inside the overlay)")
                .disabled(selectedScript == nil && !overlay.isOpen)
            }
        }
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(get: { store.settings.overlayAlwaysOnTop },
                set: { store.settings.overlayAlwaysOnTop = $0; overlay.setAlwaysOnTop($0) })
    }

    private var clickThroughBinding: Binding<Bool> {
        Binding(get: { clickThrough },
                set: { clickThrough = $0; overlay.setClickThrough($0) })
    }
}

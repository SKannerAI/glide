import SwiftUI
import AppKit

/// A floating, non-activating panel that stays above other apps and follows
/// across Spaces / over full-screen apps. Transparent so window opacity
/// (`alphaValue`) shows the desktop through the teleprompter.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Allow the panel to become key when clicked so its SwiftUI controls
        // (mic, formatting, opacity) receive events — without activating the app.
        becomesKeyOnlyIfNeeded = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        // Hide the traffic-light buttons — the teleprompter's own Exit closes it.
        [.closeButton, .miniaturizeButton, .zoomButton].forEach {
            standardWindowButton($0)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }   // so its controls + keys work when clicked
    override var canBecomeMain: Bool { false } // but it never becomes the app's main window
}

/// Owns the floating overlay panel and exposes window-level controls that the
/// main window drives (kept out of the panel so they stay reachable even when
/// click-through is enabled).
@MainActor
final class OverlayController: ObservableObject {
    @Published private(set) var isOpen = false
    private var panel: FloatingPanel?

    func open(script: Script, store: ScriptStore) {
        close()
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 460))
        let root = OverlayRootView(script: script) { [weak self] in self?.close() }
            .environmentObject(store)
        panel.contentView = NSHostingView(rootView: root)
        panel.level = store.settings.overlayAlwaysOnTop ? .floating : .normal
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        isOpen = true
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        isOpen = false
    }

    func setAlwaysOnTop(_ on: Bool) { panel?.level = on ? .floating : .normal }
    func setClickThrough(_ on: Bool) { panel?.ignoresMouseEvents = on }
}

/// Overlay content: the teleprompter with adjustable *content* opacity, plus a
/// small always-opaque strip to control that opacity from within the panel
/// (window `alphaValue` would fade the controls too).
struct OverlayRootView: View {
    let script: Script
    var onClose: () -> Void
    @EnvironmentObject var store: ScriptStore

    var body: some View {
        ZStack(alignment: .top) {
            TeleprompterView(script: script, onExit: onClose)
                .opacity(store.settings.overlayOpacity)
            opacityStrip
        }
    }

    private var opacityStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled").font(.caption2)
            Slider(value: $store.settings.overlayOpacity, in: 0.3...1.0).frame(width: 120)
            Text("\(Int(store.settings.overlayOpacity * 100))%")
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }
}

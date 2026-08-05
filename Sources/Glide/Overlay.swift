import SwiftUI
import AppKit

/// A floating, non-activating panel that stays above other apps and follows
/// across Spaces / over full-screen apps. Transparent so the content opacity
/// shows the desktop through the teleprompter.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Become key when clicked so its SwiftUI controls receive events —
        // without activating the app.
        becomesKeyOnlyIfNeeded = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        [.closeButton, .miniaturizeButton, .zoomButton].forEach {
            standardWindowButton($0)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating overlay panel (the single way to open the prompter) and
/// its window-level behaviors: always-on-top and "smart strip" click-through.
@MainActor
final class OverlayController: ObservableObject {
    @Published private(set) var isOpen = false
    private var panel: FloatingPanel?
    private var mouseMonitors: [Any] = []
    private var clickThrough = false

    // Control zones (points from the top / bottom of the panel) that stay
    // clickable even when click-through is on.
    private let topZone: CGFloat = 84
    private let bottomZone: CGFloat = 108

    func open(script: Script, store: ScriptStore) {
        close()
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 460))
        let root = OverlayRootView(
            script: script,
            onClose: { [weak self] in self?.close() },
            onAlwaysOnTop: { [weak self] on in self?.setAlwaysOnTop(on) },
            onClickThrough: { [weak self] on in self?.setClickThrough(on) }
        ).environmentObject(store)
        panel.contentView = NSHostingView(rootView: root)
        panel.level = store.settings.overlayAlwaysOnTop ? .floating : .normal
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        isOpen = true
    }

    func close() {
        setClickThrough(false)
        panel?.orderOut(nil)
        panel = nil
        isOpen = false
    }

    func setAlwaysOnTop(_ on: Bool) { panel?.level = on ? .floating : .normal }

    /// "Smart strip" click-through: the reading area passes clicks to apps
    /// beneath, while the top (opacity + settings) and bottom (playback) zones
    /// stay interactive — so you can always adjust and toggle this back off.
    func setClickThrough(_ on: Bool) {
        clickThrough = on
        removeMouseMonitors()
        guard on else { panel?.ignoresMouseEvents = false; return }
        evaluatePointer()
        let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.evaluatePointer()
        }
        if let g { mouseMonitors.append(g) }
        let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.evaluatePointer()
            return event
        }
        if let l { mouseMonitors.append(l) }
    }

    private func evaluatePointer() {
        guard clickThrough, let panel else { return }
        let f = panel.frame
        let m = NSEvent.mouseLocation
        let inX = m.x >= f.minX && m.x <= f.maxX
        let inTop = inX && m.y >= f.maxY - topZone && m.y <= f.maxY
        let inBottom = inX && m.y >= f.minY && m.y <= f.minY + bottomZone
        panel.ignoresMouseEvents = !(inTop || inBottom)
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
    }
}

/// Overlay content: the teleprompter with adjustable *content* opacity, and a
/// top strip carrying the opacity slider plus a settings (cog) popover for the
/// overlay behaviors. Kept as content opacity so this strip stays fully visible.
struct OverlayRootView: View {
    let script: Script
    var onClose: () -> Void
    var onAlwaysOnTop: (Bool) -> Void
    var onClickThrough: (Bool) -> Void

    @EnvironmentObject var store: ScriptStore
    @State private var showSettings = false
    @State private var clickThrough = false

    var body: some View {
        ZStack(alignment: .top) {
            TeleprompterView(script: script, onExit: onClose)
                .opacity(store.settings.overlayOpacity)
            controlStrip
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled").font(.caption2)
            Slider(value: $store.settings.overlayOpacity, in: 0.3...1.0).frame(width: 120)
            Text("\(Int(store.settings.overlayOpacity * 100))%")
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            Divider().frame(height: 16)

            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape.fill").font(.callout)
            }
            .buttonStyle(.plain)
            .help("Overlay settings")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { settingsPopover }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlay").font(.headline)
            Toggle("Always on Top", isOn: alwaysOnTopBinding)
            Toggle("Click-through", isOn: clickThroughBinding)
            Text("Clicks pass through the script to apps beneath; this strip and the playback controls stay active.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 250)
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(get: { store.settings.overlayAlwaysOnTop },
                set: { store.settings.overlayAlwaysOnTop = $0; onAlwaysOnTop($0) })
    }

    private var clickThroughBinding: Binding<Bool> {
        Binding(get: { clickThrough },
                set: { clickThrough = $0; onClickThrough($0) })
    }
}

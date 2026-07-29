import SwiftUI
import AppKit

struct TeleprompterView: View {
    let script: Script
    var onExit: () -> Void

    @EnvironmentObject var store: ScriptStore
    @StateObject private var scroller = TeleprompterScroller()
    @StateObject private var voice: VoiceEngine
    @State private var dragStartOffset: Double?
    @State private var eventMonitor: Any?

    // Reading guide sits this far down the viewport; top padding matches it so a
    // word at progress p lands on the guide. Bottom padding lets the last line
    // scroll up to the guide.
    private static let guideFraction = 0.42
    private static let bottomPadFraction = 0.6

    // Control tints: orange when active (playing / listening), soft white otherwise.
    private static let activeTint = Color(hex: "#FF5A00")
    private static let inactiveTint = Color.white.opacity(0.85)

    init(script: Script, onExit: @escaping () -> Void) {
        self.script = script
        self.onExit = onExit
        _voice = StateObject(wrappedValue: VoiceEngine(scriptText: script.body))
    }

    private var wordCount: Int {
        max(1, script.body.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count)
    }

    var body: some View {
        let s = store.settings
        ZStack(alignment: .bottom) {
            Color(hex: s.backgroundHex).ignoresSafeArea()

            GeometryReader { geo in
                textContent(s, viewport: geo.size.height)
                    .offset(y: -scroller.offset)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .scaleEffect(x: s.mirror ? -1 : 1, y: 1)
                    .onAppear {
                        scroller.viewportHeight = geo.size.height
                        scroller.start()
                    }
                    .onChange(of: geo.size.height) { _, h in
                        scroller.viewportHeight = h
                        recomputeSpeed(store.settings)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStartOffset == nil { dragStartOffset = scroller.offset }
                                scroller.manualScrub(to: (dragStartOffset ?? 0) - value.translation.height)
                            }
                            .onEnded { _ in dragStartOffset = nil }
                    )
            }
            .clipped()

            controlsBar(s)
        }
        .overlay(alignment: .top) { readingGuide }
        .overlay(alignment: .top) { permissionBanner }
        .onChange(of: store.settings) { _, s in recomputeSpeed(s) }
        .onChange(of: voice.progress) { _, p in
            // Map progress onto the true text height (excludes top/bottom padding)
            // so the spoken word lands on the reading guide instead of overshooting.
            let vp = scroller.viewportHeight
            let textHeight = max(1, scroller.contentHeight - vp * (Self.guideFraction + Self.bottomPadFraction))
            scroller.setVoiceTargetOffset(p * textHeight)
        }
        .onAppear { installEventMonitor() }
        .onDisappear {
            removeEventMonitor()
            voice.stop()
            scroller.stop()
        }
    }

    // Scroll wheel / trackpad + keys, via an AppKit monitor (reliable regardless
    // of SwiftUI focus). Space = play/pause, ↑/↓ = nudge, Esc = exit.
    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { event in
            switch event.type {
            case .scrollWheel:
                scroller.nudge(-event.scrollingDeltaY)
                return nil
            case .keyDown:
                switch event.keyCode {
                case 126: scroller.nudge(-80); return nil   // up arrow
                case 125: scroller.nudge(80); return nil    // down arrow
                case 49:  scroller.togglePlay(); return nil // space
                case 53:  exit(); return nil                // esc
                default:  return event
                }
            default:
                return event
            }
        }
    }

    private func removeEventMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Pieces

    private func textContent(_ s: PromptSettings, viewport: Double) -> some View {
        Text(script.body.isEmpty ? "…" : script.body)
            .font(.system(size: s.fontSize, weight: .medium))
            .foregroundStyle(Color(hex: s.textColorHex))
            .lineSpacing(s.lineSpacing)
            .multilineTextAlignment(s.alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: s.alignment.frameAlignment)
            .padding(.horizontal, s.horizontalPadding)
            .padding(.top, viewport * Self.guideFraction)
            .padding(.bottom, viewport * Self.bottomPadFraction)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { p in
                    Color.clear
                        .onAppear { setContentHeight(p.size.height) }
                        .onChange(of: p.size.height) { _, h in setContentHeight(h) }
                }
            )
    }

    private func setContentHeight(_ h: Double) {
        scroller.contentHeight = h
        recomputeSpeed(store.settings)
    }

    private var readingGuide: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color(hex: "#FF5A00").opacity(0.55))
                .frame(height: 2)
                .position(x: geo.size.width / 2, y: geo.size.height * Self.guideFraction)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var permissionBanner: some View {
        if voice.permissionDenied {
            Text("Enable Microphone & Speech Recognition in System Settings → Privacy")
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 16)
        }
    }

    private func controlsBar(_ s: PromptSettings) -> some View {
        HStack(spacing: 16) {
            Button { scroller.togglePlay() } label: {
                Image(systemName: scroller.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(scroller.isPlaying ? Self.activeTint : Self.inactiveTint)
            }
            .buttonStyle(.plain)
            .help("Play / pause (Space)")

            Button {
                scroller.restart()
                voice.reset()
            } label: {
                Image(systemName: "backward.end.fill")
                    .foregroundStyle(Self.inactiveTint)
            }
            .buttonStyle(.plain)
            .help("Restart from top")

            Divider().frame(height: 20)

            Button {
                Task {
                    await voice.toggle()
                    scroller.voiceMode = voice.isListening
                    if voice.isListening { scroller.isPlaying = true }
                }
            } label: {
                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .foregroundStyle(voice.isListening ? Self.activeTint : Self.inactiveTint)
            }
            .buttonStyle(.plain)
            .help("Voice-activated scrolling")

            Divider().frame(height: 20)

            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Slider(value: $store.settings.wordsPerMinute, in: 60...300).frame(width: 120)
                Text("\(Int(s.wordsPerMinute)) wpm")
                    .monospacedDigit().frame(width: 66, alignment: .leading)
            }

            Stepper("Aa \(Int(s.fontSize))", value: $store.settings.fontSize, in: 18...120, step: 2)
                .fixedSize()
            Stepper("↕ \(Int(s.lineSpacing))", value: $store.settings.lineSpacing, in: 0...48, step: 2)
                .fixedSize()

            Picker("", selection: $store.settings.alignment) {
                ForEach(TextAlignmentOption.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize().labelsHidden()

            Toggle(isOn: $store.settings.mirror) {
                Image(systemName: "flip.horizontal")
            }
            .toggleStyle(.button)
            .help("Mirror horizontally")

            Spacer()

            Button { exit() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Exit teleprompter")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(20)
        .frame(maxWidth: 940)
    }

    // MARK: - Logic

    private func exit() {
        scroller.stop()
        onExit()
    }

    /// Sets scroll velocity so traversing the whole script takes wordCount/WPM minutes.
    private func recomputeSpeed(_ s: PromptSettings) {
        let seconds = Double(wordCount) / max(1, s.wordsPerMinute) * 60
        let distance = max(1, scroller.contentHeight - scroller.viewportHeight)
        scroller.pointsPerSecond = distance / max(1, seconds)
    }
}

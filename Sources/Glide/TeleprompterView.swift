import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}

struct TeleprompterView: View {
    let script: Script
    var onExit: () -> Void

    @EnvironmentObject var store: ScriptStore
    @StateObject private var scroller = TeleprompterScroller()
    @FocusState private var focused: Bool
    @State private var dragStartOffset: Double?

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
        .onPreferenceChange(ContentHeightKey.self) { h in
            scroller.contentHeight = h
            recomputeSpeed(store.settings)
        }
        .onChange(of: store.settings) { _, s in recomputeSpeed(s) }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.space) { scroller.togglePlay(); return .handled }
        .onKeyPress(.upArrow) { scroller.nudge(-80); return .handled }
        .onKeyPress(.downArrow) { scroller.nudge(80); return .handled }
        .onExitCommand { exit() }
        .onDisappear { scroller.stop() }
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
            .padding(.top, viewport * 0.42)
            .padding(.bottom, viewport * 0.6)
            .background(
                GeometryReader { p in
                    Color.clear.preference(key: ContentHeightKey.self, value: p.size.height)
                }
            )
    }

    private var readingGuide: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color(hex: "#FF5A00").opacity(0.55))
                .frame(height: 2)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
        .allowsHitTesting(false)
    }

    private func controlsBar(_ s: PromptSettings) -> some View {
        HStack(spacing: 16) {
            Button { scroller.togglePlay() } label: {
                Image(systemName: scroller.isPlaying ? "pause.fill" : "play.fill")
            }
            .help("Play / pause (Space)")

            Button { scroller.restart() } label: {
                Image(systemName: "backward.end.fill")
            }
            .help("Restart")

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

            Button("Exit") { exit() }
                .keyboardShortcut(.cancelAction)
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

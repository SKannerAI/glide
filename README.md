# Glide

A native macOS teleprompter with **voice-activated scrolling** — the script follows your voice, holds when you pause, and glides smoothly as you read.

## Decisions (locked)

| | |
|---|---|
| **Name** | Glide |
| **Icon** | Playhead — marker locked to the active reading line (orange & black) |
| **Platform** | macOS, min deployment **14.0 (Sonoma)** |
| **Stack** | SwiftUI + AppKit (`NSPanel` overlay); JSON persistence (SwiftData deferred — its macro needs full Xcode) |
| **Speech** | `Transcriber` protocol: **SpeechAnalyzer** (macOS 26+) with **SFSpeechRecognizer** fallback (macOS 14–15), selected at runtime |
| **Distribution** | Developer ID / notarized (not App Store to start) |

Screen-share hiding is intentionally **out of scope** — it's unreliable and unsupported on modern macOS (ScreenCaptureKit ignores `NSWindow.sharingType` on 15.4+).

## Phased build plan

- **Phase 0** — Scaffold: SwiftUI app, split-view shell, Info.plist mic/speech usage strings.
- **Phase 1** — Script management: SwiftData `Script`/`Folder`, sidebar CRUD + search, autosaving editor.
- **Phase 2** — Teleprompter view + formatting: font/size/spacing/color/mirror, SmoothDamp spring scroll (constant-WPM + manual override).
- **Phase 3** — Voice-activated scrolling: `Transcriber` protocol (SpeechAnalyzer / WhisperKit), fuzzy sliding-window alignment, pause-hold/resume. *(needs signed bundle for mic/speech prompts)*
- **Phase 4** — Overlay: floating `NSPanel`, opacity slider (`alphaValue`), always-on-top toggle, all-Spaces/fullscreen.
- **Phase 5** — Polish & distribution: shortcuts, preferences, codesign + notarize.

## Layout

```
glide/
├─ Package.swift          # SPM executable target (macOS 14+, Swift 5 mode)
├─ Sources/Glide/         # app source
│  ├─ GlideApp.swift      # @main App + AppDelegate (activation)
│  ├─ Models.swift        # Script / Folder / Library (Codable)
│  ├─ ScriptStore.swift   # ObservableObject store + JSON autosave
│  ├─ ContentView.swift   # NavigationSplitView shell
│  ├─ SidebarView.swift   # folders, scripts, search, CRUD
│  └─ EditorView.swift    # title + body editor
├─ Resources/Info.plist   # bundle metadata + mic/speech usage strings
├─ scripts/build.sh       # swift build → signed Glide.app
├─ scripts/run.sh         # build + launch
├─ design/                # icon concepts + final asset catalog
│  ├─ icon.svg            # Playhead master (source of truth)
│  └─ AppIcon.appiconset/
└─ README.md
```

## Build & run

No Xcode required — Glide builds with the Swift toolchain into a signed `.app`.

**First time on a machine:**

```
git clone <repo> && cd glide
./scripts/setup-signing.sh   # one-time: create the local "Glide Dev" signing identity
./scripts/run.sh             # build + launch
```

**Everyday:**

```
./scripts/run.sh             # build + launch
./scripts/build.sh           # build only → build/Glide.app
swift run GlideCoreCheck     # run the core unit checks
```

### Signing

`setup-signing.sh` creates a self-signed **"Glide Dev"** code-signing identity in a
dedicated keychain (`~/Library/Keychains/glide-signing.keychain-db`, with a fixed
internal password baked into the script — nothing for you to remember or type).
This is **required for voice features**: macOS won't show the microphone /
speech-recognition permission prompts for an ad-hoc-signed app.

- It's **per machine** — run it once on each Mac you build on. Each gets its own
  local cert; the keychain/cert are never committed to git.
- Skip it and `build.sh` **falls back to ad-hoc signing** automatically — the app
  still builds and runs, just without reliable voice permissions.
- `build.sh` unlocks the signing keychain before signing, so `codesign` never
  blocks on a keychain prompt (even in a fresh login session).

Data persists to `~/Library/Application Support/Glide/` (`library.json`,
`settings.json`). When full Xcode is available, migrate JSON → SwiftData and add a
proper `.xcodeproj` for notarized distribution.

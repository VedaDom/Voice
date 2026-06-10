import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var bridge: WorkerBridge!
    var status: StatusController!
    var overlay: OverlayController!
    var onboarding: OnboardingController!
    var library: LibraryController!
    var settingsWindow: SettingsController!
    let updates = UpdateChecker()
    let hotkeys = HotkeyMonitor()
    private var focusAnchor: FocusAnchor?

    static let onboardedKey = "VoiceOnboarded"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Theme.registerFonts()

        state.notes = HistoryStore.load()
        state.notes = HistoryStore.sweepOldAudio(state.notes)   // 14-day audio retention
        state.accessibilityTrusted = Paster.accessibilityTrusted

        status = StatusController(state: state, updates: updates)
        overlay = OverlayController(state: state)
        onboarding = OnboardingController(state: state)
        library = LibraryController(state: state)
        settingsWindow = SettingsController(state: state)
        status.onOpenLibrary = { [weak self] in self?.library.show() }
        status.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        settingsWindow.onCleanupDownload = { [weak self] in
            self?.state.cleanupState = .downloading(0)
            self?.bridge.send(["cmd": "cleanup_setup"])
        }
        library.onRetranscribe = { [weak self] note in self?.retranscribe(note) }
        updates.checkDaily()

        bridge = WorkerBridge { [weak self] event in
            self?.handle(event)
        }

        status.onPaste = { [weak self] note in
            Paster.paste(note.text)
            self?.bumpToTop(note)
        }
        status.onPause = { [weak self] in self?.bridge.send(["cmd": "pause"]) }
        status.onResume = { [weak self] in self?.bridge.send(["cmd": "resume"]) }
        status.onComplete = { [weak self] in self?.stopDictation() }
        status.onCancel = { [weak self] in self?.cancelDictation() }
        onboarding.onRetry = { [weak self] in
            self?.state.engine = .launching
            self?.bridge.setup()
        }

        hotkeys.onStart = { [weak self] in self?.startDictation() }
        hotkeys.onStop = { [weak self] in self?.stopDictation() }
        hotkeys.onCancel = { [weak self] in self?.cancelDictation() }
        hotkeys.isSessionActive = { [weak self] in self?.state.sessionActive ?? false }
        hotkeys.fnEnabled = { SettingsStore.shared.hotkeyFn }
        hotkeys.rightCmdEnabled = { SettingsStore.shared.hotkeyRightCmd }
        hotkeys.onTogglePause = { [weak self] in
            guard let self, self.state.sessionActive else { return }
            self.bridge.send(["cmd": self.state.engine == .paused ? "resume" : "pause"])
        }
        hotkeys.onOpenApp = { [weak self] in self?.library.show() }
        hotkeys.startMonitoring()

        if !UserDefaults.standard.bool(forKey: Self.onboardedKey) {
            onboarding.show()
        }

        bridge.launch()
        bridge.setup()
        if SettingsStore.shared.cleanupModelInstalled {
            // already on disk from a previous run — just load it
            bridge.send(["cmd": "cleanup_setup"])
        }

        // keep accessibility status fresh (user may grant it in System Settings)
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.state.accessibilityTrusted = Paster.accessibilityTrusted
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.shutdown()
        hotkeys.stopMonitoring()
    }

    // ------------------------------------------------------------- events
    private func handle(_ e: [String: Any]) {
        switch e["event"] as? String {
        case "state":
            let s = e["state"] as? String ?? ""
            switch s {
            case "checking": state.engine = .downloading(0)
            case "downloading": state.engine = .downloading(e["pct"] as? Double ?? 0)
            case "loading": state.engine = .loading
            case "warming": state.engine = .warming
            case "ready":
                let wasReady = UserDefaults.standard.bool(forKey: Self.onboardedKey)
                state.engine = .ready
                if !wasReady {
                    UserDefaults.standard.set(true, forKey: Self.onboardedKey)
                }
            case "recording": state.engine = .recording
            case "paused": state.engine = .paused
            case "transcribing": state.engine = .transcribing
            case "error": state.engine = .error(e["message"] as? String ?? "Unknown error")
            default: break
            }
            status.refresh()
        case "cleanup_state":
            switch e["state"] as? String ?? "" {
            case "downloading":
                state.cleanupState = .downloading(e["pct"] as? Double ?? 0)
            case "ready":
                state.cleanupState = .ready
                SettingsStore.shared.cleanupModelInstalled = true
                SettingsStore.shared.cleanupEnabled = true
            case "error":
                state.cleanupState = .failed(e["message"] as? String ?? "Download failed")
            default: break
            }
        case "retranscribed":
            let idStr = e["id"] as? String ?? ""
            let text = (e["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            state.retranscribing = nil
            if let uuid = UUID(uuidString: idStr), !text.isEmpty,
               let idx = state.notes.firstIndex(where: { $0.id == uuid }) {
                state.notes[idx].text = SettingsStore.shared.postProcess(text)
                HistoryStore.save(state.notes)
            }
        case "level":
            state.level = e["norm"] as? Double ?? 0
        case "partial":
            state.partial = e["text"] as? String ?? ""
        case "final":
            let raw = (e["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let wav = e["wav"] as? String ?? ""
            let dur = e["duration"] as? Double ?? 0
            let settings = SettingsStore.shared
            state.sessionActive = false
            overlay.hide()
            state.partial = ""
            state.level = 0
            let text = settings.postProcess(raw)
            if !text.isEmpty {
                if settings.insertIntoApp {
                    Paster.paste(text, anchor: focusAnchor,
                                 keepOnClipboard: settings.alsoCopyToClipboard)
                } else {
                    Paster.copy(text)
                }
                if settings.saveHistory {
                    let note = Note(text: text, wav: wav, date: Date(), duration: dur)
                    state.notes.insert(note, at: 0)
                    HistoryStore.save(state.notes)
                }
                settings.collectSuggestions(from: text)
                if settings.playSounds { NSSound(named: "Glass")?.play() }
            }
            focusAnchor = nil
        default:
            break
        }
    }

    // ------------------------------------------------------------- dictation
    private func startDictation() {
        guard state.engine == .ready, !state.sessionActive else { return }
        let settings = SettingsStore.shared
        state.sessionActive = true
        state.partial = ""
        focusAnchor = FocusAnchor.capture()   // remember where the user was typing
        bridge.send([
            "cmd": "start",
            "language": settings.language,
            "mode": settings.transcriptionMode,
            "lookahead": settings.lowPowerMode ? 13 : 6,
            "save_audio": settings.storeAudio,
            "smart_detect": settings.smartDetect,
            "cleanup": cleanupOptions(),
        ])
        overlay.show()
        if settings.playSounds { NSSound(named: "Pop")?.play() }
    }

    private func cleanupOptions() -> [String: Any] {
        let s = SettingsStore.shared
        return [
            "enabled": s.cleanupEnabled && s.cleanupModelInstalled,
            "typos": s.cleanupFixTypos,
            "grammar": s.cleanupGrammar,
            "style": s.cleanupPreserveStyle,
            "words": Array(s.vocabulary.words.prefix(40)),
        ]
    }

    private func retranscribe(_ note: Note) {
        guard !note.wav.isEmpty else { return }
        state.retranscribing = note.id
        bridge.send([
            "cmd": "retranscribe",
            "wav": note.wav,
            "id": note.id.uuidString,
            "language": SettingsStore.shared.language,
            "cleanup": cleanupOptions(),
        ])
    }

    private func stopDictation() {
        guard state.sessionActive else { return }
        // worker processes commands in order, so stop lands after start even
        // when the key is released before the "recording" state echo arrives
        bridge.stop()
    }

    private func cancelDictation() {
        guard state.sessionActive else { return }
        state.sessionActive = false
        bridge.cancel()
        overlay.hide()
        state.partial = ""
        state.level = 0
    }

    private func bumpToTop(_ note: Note) {
        if let idx = state.notes.firstIndex(of: note) {
            state.notes.remove(at: idx)
            state.notes.insert(note, at: 0)
            HistoryStore.save(state.notes)
        }
    }
}

@main
struct VoiceMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

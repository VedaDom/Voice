import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class SettingsController {
    private var window: NSWindow?
    private let state: AppState
    var onCleanupDownload: () -> Void = {}

    init(state: AppState) {
        self.state = state
    }

    func show(page: SettingsPage = .dictation) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(Theme.pane)
            w.contentView = NSHostingView(
                rootView: SettingsView(state: state, initialPage: page,
                                       onCleanupDownload: { [weak self] in
                                           self?.onCleanupDownload()
                                       })
            )
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsPage: String, CaseIterable {
    case general = "General"
    case dictation = "Dictation"
    case shortcuts = "Shortcuts"
    case models = "Models"
    case vocabulary = "Vocabulary"
    case privacy = "Privacy"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .dictation: return "mic"
        case .shortcuts: return "command"
        case .models: return "cpu"
        case .vocabulary: return "book"
        case .privacy: return "shield"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings = SettingsStore.shared
    @State var page: SettingsPage
    var onCleanupDownload: () -> Void

    init(state: AppState, initialPage: SettingsPage, onCleanupDownload: @escaping () -> Void) {
        self.state = state
        self.onCleanupDownload = onCleanupDownload
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 700)
        .background(Theme.bg)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(Theme.fraunces(21))
                .kerning(-0.3)
                .foregroundStyle(Theme.ink)
                .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))

            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases, id: \.self) { p in
                    navRow(p)
                }
            }
            .padding(.horizontal, 12)
            Spacer()
        }
        .padding(.top, 26)
        .background(Theme.pane)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private func navRow(_ p: SettingsPage) -> some View {
        let active = page == p
        return HStack(spacing: 11) {
            Image(systemName: p.icon)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Theme.ink2)
                .frame(width: 16)
            Text(p.rawValue)
                .font(Theme.inter(13.5, active ? .semibold : .medium))
                .foregroundStyle(active ? Theme.ink : Theme.ink2)
            Spacer()
        }
        .padding(EdgeInsets(top: 9, leading: active ? 10 : 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 8).fill(active ? Theme.sel : .clear))
        .overlay(alignment: .leading) {
            if active {
                RoundedRectangle(cornerRadius: 1).fill(Theme.accent).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { page = p }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    pageBody
                }
                .padding(EdgeInsets(top: 8, leading: 32, bottom: 28, trailing: 32))
            }
        }
        .background(Theme.doc)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.rawValue)
                .font(Theme.fraunces(27))
                .kerning(-0.5)
                .foregroundStyle(Theme.ink)
            Text(headerSub)
                .font(Theme.inter(13))
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 32, leading: 32, bottom: 22, trailing: 32))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var headerSub: String {
        switch page {
        case .general: return "How Voice lives on your Mac."
        case .dictation: return "How Voice listens and turns your speech into text."
        case .shortcuts: return "Keys and gestures that control dictation anywhere on your Mac."
        case .models: return "The on-device models that turn your speech into clean, finished text."
        case .vocabulary: return "Teach Voice the words and phrases it should always get right."
        case .privacy: return "Voice is built to keep everything on your Mac."
        case .about: return "On-device voice dictation for macOS."
        }
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .general: GeneralPage()
        case .dictation: DictationPage(settings: settings, goVocabulary: { page = .vocabulary })
        case .shortcuts: ShortcutsPage(settings: settings)
        case .models: ModelsPage(state: state, settings: settings,
                                 onCleanupDownload: onCleanupDownload)
        case .vocabulary: VocabularyPage(settings: settings)
        case .privacy: PrivacyPage(state: state, settings: settings)
        case .about: AboutPage()
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        SettingsSection(title: "STARTUP", topPadding: 14)
        SettingsRow(title: "Launch at login",
                    description: "Start Voice automatically so dictation is always one key away.") {
            EmberToggle(isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; LoginItem.set(enabled: $0) }
            ))
        }
        SettingsRow(title: "Menu bar icon",
                    description: "Voice lives in your menu bar — there is no Dock icon.") {
            Text("Always shown")
                .font(Theme.inter(12.5))
                .foregroundStyle(Theme.ink3)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppServiceShim.isEnabled
        }
        return false
    }
    static func set(enabled: Bool) {
        SMAppServiceShim.set(enabled: enabled)
    }
}

import ServiceManagement
enum SMAppServiceShim {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Voice: launch-at-login change failed: \(error)")
        }
    }
}

// MARK: - Dictation

private struct DictationPage: View {
    @ObservedObject var settings: SettingsStore
    var goVocabulary: () -> Void

    /// The model's 19 transcription-ready locales (per the NVIDIA model card),
    /// plus full auto-detect.
    static let languages: [(String, String)] = [
        ("en-US", "English (US)"), ("en-GB", "English (UK)"),
        ("es-US", "Español (US)"), ("es-ES", "Español (España)"),
        ("fr-FR", "Français"), ("fr-CA", "Français (Canada)"),
        ("it-IT", "Italiano"), ("pt-BR", "Português (Brasil)"),
        ("pt-PT", "Português (Portugal)"), ("nl-NL", "Nederlands"),
        ("de-DE", "Deutsch"), ("tr-TR", "Türkçe"),
        ("ru-RU", "Русский"), ("ar-AR", "العربية"),
        ("hi-IN", "हिन्दी"), ("ja-JP", "日本語"),
        ("ko-KR", "한국어"), ("vi-VN", "Tiếng Việt"),
        ("uk-UA", "Українська"), ("auto", "Auto-detect"),
    ]

    var body: some View {
        SettingsSection(title: "ACTIVATION", topPadding: 14)
        SettingsRow(title: "Push-to-talk key",
                    description: "Hold to dictate anywhere, release to insert.") {
            HStack(spacing: 8) {
                if settings.hotkeyRightCmd { Keycap(label: "right ⌘") }
                if settings.hotkeyFn { Keycap(label: "fn") }
            }
        }
        SettingsRow(title: "Activation mode",
                    description: "Hold the key down, or double-tap to keep it recording hands-free.") {
            Text("Hold · 2×tap locks")
                .font(Theme.inter(12.5))
                .foregroundStyle(Theme.ink3)
        }

        SettingsSection(title: "TRANSCRIPTION")
        SettingsRow(title: "Language", description: "Primary language for transcription.") {
            SelectPill(selection: $settings.language, options: Self.languages)
        }
        SettingsRow(title: "Detect other languages",
                    description: "If you start speaking another language, Voice notices after ~2 s and switches automatically.") {
            EmberToggle(isOn: $settings.smartDetect)
        }
        SettingsRow(title: "Model",
                    description: "Runs entirely on your Mac — nothing leaves the device.") {
            Text("Nemotron 3.5")
                .font(Theme.inter(12.5, .medium))
                .foregroundStyle(Theme.ink2)
        }
        SettingsRow(title: "Transcription mode",
                    description: "Transcribe live as you speak, or once after you finish for the highest accuracy.") {
            SelectPill(selection: $settings.transcriptionMode, options: [
                ("live", "Real-time"), ("deferred", "After I finish"),
            ])
        }
        SettingsRow(title: "Custom words",
                    description: "Teach Voice names, jargon and acronyms so they’re always spelled right.") {
            SettingsButton(label: "Manage · \(SettingsStore.shared.vocabulary.words.count)") {
                goVocabulary()
            }
        }
        SettingsRow(title: "Smart punctuation",
                    description: "Add commas, periods, and capitalization automatically.") {
            EmberToggle(isOn: $settings.smartPunctuation)
        }
        SettingsRow(title: "Remove filler words",
                    description: "Strip “um”, “uh”, and false starts from the final text.") {
            EmberToggle(isOn: $settings.removeFillers)
        }

        SettingsSection(title: "OUTPUT")
        SettingsRow(title: "Insert into focused app",
                    description: "Paste the text right where your cursor is.") {
            EmberToggle(isOn: $settings.insertIntoApp)
        }
        SettingsRow(title: "Also copy to clipboard",
                    description: "Keep a copy so you can paste it again later.") {
            EmberToggle(isOn: $settings.alsoCopyToClipboard)
        }
        SettingsRow(title: "Play sound on start & stop",
                    description: "A soft cue when recording begins and ends.") {
            EmberToggle(isOn: $settings.playSounds)
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPage: View {
    @ObservedObject var settings: SettingsStore

    private var keySelection: Binding<String> {
        Binding(
            get: {
                if settings.hotkeyRightCmd && settings.hotkeyFn { return "both" }
                if settings.hotkeyFn { return "fn" }
                return "rightCmd"
            },
            set: { v in
                settings.hotkeyRightCmd = (v == "both" || v == "rightCmd")
                settings.hotkeyFn = (v == "both" || v == "fn")
            }
        )
    }

    var body: some View {
        SettingsSection(title: "ACTIVATION", topPadding: 14)
        SettingsRow(title: "Activation key",
                    description: "Hold this key anywhere to start dictating.") {
            SelectPill(selection: keySelection, options: [
                ("both", "Right ⌘ or fn"), ("rightCmd", "Right ⌘"), ("fn", "fn"),
            ])
        }
        if settings.hotkeyFn {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xB0832A))
                Text("macOS may open the emoji picker on fn. Set “Press 🌐 key to” → “Do Nothing” in System Settings ▸ Keyboard, or use Right ⌘ only.")
                    .font(Theme.inter(12))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(3)
                Spacer()
                SettingsButton(label: "Open Keyboard") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xF7EFDC)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xE0C98F), lineWidth: 1))
            .padding(.vertical, 8)
        }
        SettingsRow(title: "Hands-free toggle",
                    description: "Double-tap the activation key to start; tap once to stop.") {
            HStack(spacing: 5) { Keycap(label: "2×"); Keycap(label: "tap") }
        }

        SettingsSection(title: "GLOBAL SHORTCUTS")
        SettingsRow(title: "Pause / resume", description: "While dictating.") {
            HStack(spacing: 5) { Keycap(label: "⌥"); Keycap(label: "P") }
        }
        SettingsRow(title: "Cancel dictation", description: "") {
            Keycap(label: "esc")
        }
        SettingsRow(title: "Re-transcribe note", description: "In the Library window.") {
            HStack(spacing: 5) { Keycap(label: "⌘"); Keycap(label: "R") }
        }
        SettingsRow(title: "Complete dictation", description: "While recording hands-free.") {
            Keycap(label: "tap key")
        }
    }
}

// MARK: - Models

private struct ModelsPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: SettingsStore
    var onCleanupDownload: () -> Void

    var body: some View {
        SettingsSection(title: "INSTALLED MODEL", topPadding: 14)
        VStack(spacing: 10) {
            ModelCard(icon: "cpu", iconEmber: true, title: "Nemotron ASR 3.5",
                      subtitle: "On-device · 1.2 GB · 40 languages") {
                StatusBadge(label: "Active")
            }
            ModelCard(icon: "shippingbox", title: "Parakeet TDT 0.6B",
                      subtitle: "Faster, lighter · 0.6 GB") {
                Text("Coming soon")
                    .font(Theme.inter(12.5, .medium))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.vertical, 4)

        SettingsSection(title: "TEXT CLEANUP")
        Text("A small, fast on-device language model rewrites the raw transcript — fixing typos, grammar and punctuation — without anything leaving your Mac.")
            .font(Theme.inter(12.5))
            .foregroundStyle(Theme.ink2)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)

        ModelCard(icon: "sparkles", title: "Liquid LFM2-350M",
                  tag: "Optional",
                  subtitle: "350 MB · cleans up text after dictation, fully on-device") {
            cleanupTrailing
        }
        .padding(.bottom, 4)

        SettingsRow(title: "Fix spelling & typos",
                    description: "Correct misheard or mistyped words.") {
            EmberToggle(isOn: $settings.cleanupFixTypos,
                        disabled: !settings.cleanupModelInstalled)
        }
        SettingsRow(title: "Grammar & punctuation",
                    description: "Tidy sentence structure, casing and commas.") {
            EmberToggle(isOn: $settings.cleanupGrammar,
                        disabled: !settings.cleanupModelInstalled)
        }
        SettingsRow(title: "Preserve my style",
                    description: "Keep contractions, slang and tone intact.") {
            EmberToggle(isOn: $settings.cleanupPreserveStyle,
                        disabled: !settings.cleanupModelInstalled)
        }
        SettingsRow(title: "Run cleanup", description: "") {
            Text("After I finish")
                .font(Theme.inter(12.5, .medium))
                .foregroundStyle(Theme.ink2)
        }

        SettingsSection(title: "COMPUTE")
        SettingsRow(title: "Processing unit",
                    description: "Inference runs on the Apple GPU via Metal (MLX).") {
            Text("GPU · Metal")
                .font(Theme.inter(12.5, .medium))
                .foregroundStyle(Theme.ink2)
        }
        SettingsRow(title: "Low-power mode",
                    description: "Larger chunks use less energy at slightly higher latency.") {
            EmberToggle(isOn: $settings.lowPowerMode)
        }

        SettingsSection(title: "STORAGE")
        SettingsRow(title: "Model storage",
                    description: "Models live in the Hugging Face cache on this Mac.") {
            SettingsButton(label: "Reveal") {
                let dir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".cache/huggingface/hub")
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            }
        }
    }

    @ViewBuilder
    private var cleanupTrailing: some View {
        switch state.cleanupState {
        case .none:
            SettingsButton(label: "Download") {
                onCleanupDownload()
            }
        case .downloading(let pct):
            HStack(spacing: 8) {
                ProgressView(value: pct).frame(width: 70)
                Text("\(Int(pct * 100))%")
                    .font(Theme.inter(12, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .monospacedDigit()
            }
        case .ready:
            HStack(spacing: 10) {
                StatusBadge(label: "Installed")
                EmberToggle(isOn: $settings.cleanupEnabled)
            }
        case .failed(let msg):
            HStack(spacing: 8) {
                Text(msg).font(Theme.inter(11.5)).foregroundStyle(Theme.accent).lineLimit(1)
                SettingsButton(label: "Retry") { onCleanupDownload() }
            }
        }
    }
}

// MARK: - Vocabulary

private struct VocabularyPage: View {
    @ObservedObject var settings: SettingsStore
    @State private var tab: Tab = .dictionary
    @State private var newWord = ""
    @State private var newSpoken = ""
    @State private var newWritten = ""

    enum Tab: String, CaseIterable {
        case dictionary = "Dictionary"
        case replacements = "Replacements"
        case suggestions = "Suggestions"
    }

    private func count(_ t: Tab) -> Int {
        switch t {
        case .dictionary: return settings.vocabulary.words.count
        case .replacements: return settings.vocabulary.replacements.count
        case .suggestions: return settings.vocabulary.suggestions.count
        }
    }

    var body: some View {
        // segmented tabs keep each list manageable as it grows
        HStack(spacing: 3) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = tab == t
                HStack(spacing: 6) {
                    Text(t.rawValue)
                        .font(Theme.inter(12.5, active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.ink : Theme.ink2)
                    if count(t) > 0 {
                        Text("\(count(t))")
                            .font(Theme.inter(10.5, .semibold))
                            .foregroundStyle(active ? Theme.accent : Theme.ink3)
                    }
                }
                .padding(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(active ? Theme.doc : .clear)
                        .shadow(color: .black.opacity(active ? 0.06 : 0), radius: 2, y: 1)
                )
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(active ? Theme.line : .clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { tab = t }
            }
            Spacer()
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.pane))
        .padding(.top, 16)

        switch tab {
        case .dictionary: dictionary
        case .replacements: replacements
        case .suggestions: suggestions
        }
    }

    // ------------------------------------------------------------ dictionary
    @ViewBuilder private var dictionary: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
            TextField("Add a word or phrase…", text: $newWord)
                .textFieldStyle(.plain)
                .font(Theme.inter(13))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .onSubmit(addWord)
            Text("⏎ Enter")
                .font(Theme.inter(11.5, .medium))
                .foregroundStyle(Theme.ink3)
                .padding(EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7))
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.pane))
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
        .padding(.top, 16)

        if settings.vocabulary.words.isEmpty {
            emptyHint("Names, jargon and acronyms you add here are used to keep special words spelled right.")
        } else {
            FlowLayout(spacing: 8) {
                ForEach(settings.vocabulary.words, id: \.self) { w in
                    WordChip(word: w) {
                        settings.vocabulary.words.removeAll { $0 == w }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
    }

    // ---------------------------------------------------------- replacements
    @ViewBuilder private var replacements: some View {
        HStack(spacing: 8) {
            TextField("When I say…", text: $newSpoken)
                .textFieldStyle(.plain).font(Theme.inter(13))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
            TextField("Write…", text: $newWritten)
                .textFieldStyle(.plain).font(Theme.inter(13))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                .onSubmit(addReplacement)
            SettingsButton(label: "Add") { addReplacement() }
        }
        .padding(.top, 16)

        if settings.vocabulary.replacements.isEmpty {
            emptyHint("Spoken phrases that should always become specific text — “voice dot app” → “voice.app”.")
        } else {
            VStack(spacing: 0) {
                ForEach(settings.vocabulary.replacements) { r in
                    HStack(spacing: 10) {
                        Text(r.spoken).font(Theme.inter(13, .medium)).foregroundStyle(Theme.ink)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10)).foregroundStyle(Theme.ink3)
                        Text(r.written).font(Theme.inter(13, .medium)).foregroundStyle(Theme.accent2)
                        Spacer()
                        Button {
                            settings.vocabulary.replacements.removeAll { $0.id == r.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10)).foregroundStyle(Theme.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
                }
            }
            .padding(.top, 8)
        }
    }

    // ----------------------------------------------------------- suggestions
    @ViewBuilder private var suggestions: some View {
        if settings.vocabulary.suggestions.isEmpty {
            emptyHint("New words Voice notices in your dictations show up here — add the ones worth keeping.")
        } else {
            FlowLayout(spacing: 8) {
                ForEach(settings.vocabulary.suggestions, id: \.self) { w in
                    HStack(spacing: 7) {
                        Button {
                            settings.vocabulary.words.append(w)
                            settings.vocabulary.suggestions.removeAll { $0 == w }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(w).font(Theme.inter(12.5, .medium))
                            }
                            .foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(.plain)
                        Button {
                            settings.vocabulary.suggestions.removeAll { $0 == w }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 9))
                    .background(Capsule().fill(Theme.sel))
                    .overlay(Capsule().stroke(Color(hex: 0xE5483A, alpha: 0x30), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(Theme.inter(12.5))
            .foregroundStyle(Theme.ink3)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
    }

    private func addWord() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !settings.vocabulary.words.contains(w) else { newWord = ""; return }
        settings.vocabulary.words.append(w)
        newWord = ""
    }

    private func addReplacement() {
        let s = newSpoken.trimmingCharacters(in: .whitespaces)
        let w = newWritten.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !w.isEmpty else { return }
        settings.vocabulary.replacements.append(.init(spoken: s, written: w))
        newSpoken = ""; newWritten = ""
    }
}

// MARK: - Privacy

private struct PrivacyPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: SettingsStore
    @State private var confirmingClear = false

    var body: some View {
        // hero
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.ember)
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Everything stays on this Mac")
                    .font(Theme.inter(14.5, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Voice has no account and makes no network calls to transcribe. Your audio and text never leave your device.")
                    .font(Theme.inter(12.5))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xF0A05A, alpha: 0x14)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(hex: 0xE5904D, alpha: 0x30), lineWidth: 1))
        .padding(.top, 14)

        SettingsSection(title: "DATA & HISTORY")
        SettingsRow(title: "Store audio with notes",
                    description: "Keep the original recording so you can re-transcribe it later.") {
            EmberToggle(isOn: $settings.storeAudio)
        }
        SettingsRow(title: "Save transcription history",
                    description: "Keep a searchable history of everything you dictate.") {
            EmberToggle(isOn: $settings.saveHistory)
        }
        SettingsRow(title: "Auto-delete recordings",
                    description: "Recordings older than this are removed automatically. Transcripts are kept.") {
            SelectPill(selection: $settings.retentionDays, options: [
                (7, "After 7 days"), (14, "After 14 days"),
                (30, "After 30 days"), (90, "After 90 days"),
            ])
        }
        SettingsRow(title: "Clear all recordings",
                    description: "Permanently delete every saved recording and transcript.") {
            SettingsButton(label: "Clear…", destructive: true) { confirmingClear = true }
        }
        .alert("Delete all notes and recordings?", isPresented: $confirmingClear) {
            Button("Delete Everything", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every transcript and audio recording. It cannot be undone.")
        }

        SettingsSection(title: "PERMISSIONS")
        SettingsRow(title: "Microphone", description: "Required to hear your voice.") {
            permissionBadge(micAllowed,
                            url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
        SettingsRow(title: "Accessibility",
                    description: "Lets Voice insert text into the app you’re using.") {
            permissionBadge(state.accessibilityTrusted,
                            url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }

        SettingsSection(title: "DIAGNOSTICS")
        SettingsRow(title: "Share anonymous diagnostics",
                    description: "Nothing is collected in this build — Voice is fully offline.") {
            EmberToggle(isOn: .constant(false), disabled: true)
        }
    }

    private var micAllowed: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    @ViewBuilder
    private func permissionBadge(_ ok: Bool, url: String) -> some View {
        if ok {
            StatusBadge(label: "Allowed")
        } else {
            SettingsButton(label: "Allow…") {
                NSWorkspace.shared.open(URL(string: url)!)
            }
        }
    }

    private func clearAll() {
        for n in state.notes where !n.wav.isEmpty {
            try? FileManager.default.removeItem(atPath: n.wav)
        }
        state.notes = []
        HistoryStore.save([])
    }
}

// MARK: - About

private struct AboutPage: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Version \(v) · build \(b)"
    }

    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .shadow(color: Theme.accent.opacity(0.2), radius: 14, y: 8)
            }
            VStack(spacing: 5) {
                Text("Voice")
                    .font(Theme.fraunces(30))
                    .kerning(-0.6)
                    .foregroundStyle(Theme.ink)
                Text(version)
                    .font(Theme.inter(12.5))
                    .foregroundStyle(Theme.ink2)
            }
            HStack(spacing: 7) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("Open source · github.com/VedaDom/Voice")
                    .font(Theme.inter(12, .semibold))
            }
            .foregroundStyle(Color(hex: 0x1F7A45))
            .padding(EdgeInsets(top: 6, leading: 13, bottom: 6, trailing: 13))
            .background(Capsule().fill(Color(hex: 0xE7F2EA)))
            .onTapGesture { open("https://github.com/VedaDom/Voice") }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)

        SettingsSection(title: "UPDATES", topPadding: 28)
        SettingsRow(title: "Software update",
                    description: "Releases are published on GitHub.") {
            SettingsButton(label: "Check now") {
                open("https://github.com/VedaDom/Voice/releases")
            }
        }

        SettingsSection(title: "RESOURCES", topPadding: 28)
        linkRow("What’s new", "https://github.com/VedaDom/Voice/releases")
        linkRow("Help & support", "https://github.com/VedaDom/Voice/issues")
        linkRow("Acknowledgements", "https://github.com/VedaDom/Voice#acknowledgements")
        linkRow("Star Voice on GitHub", "https://github.com/VedaDom/Voice")

        Text("Made on-device · © 2026 Wistfare")
            .font(Theme.inter(12))
            .foregroundStyle(Theme.ink3)
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
    }

    private func linkRow(_ title: String, _ url: String) -> some View {
        SettingsRow(title: title) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(url) }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

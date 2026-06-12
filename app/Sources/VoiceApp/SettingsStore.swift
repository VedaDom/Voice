import AppKit
import Foundation
import SwiftUI

/// User preferences. Scalars live in UserDefaults; the vocabulary (which can
/// grow large) lives in vocab.json under Application Support.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // MARK: dictation
    /// fn is opt-in (macOS maps it to the 🌐/emoji key); Right ⌘ is the default.
    @AppStorage("HotkeyFn") var hotkeyFn = false
    @AppStorage("HotkeyRightCmd") var hotkeyRightCmd = true
    /// "live" = words appear as you speak; "deferred" = transcribe after you finish
    /// (slightly higher accuracy on long takes, nothing shown while speaking).
    @AppStorage("TranscriptionMode") var transcriptionMode = "live"
    @AppStorage("VoiceLanguage") var language = "en-US"
    /// Probe ~2 s in and switch language automatically when the speaker is
    /// clearly not using the primary language.
    @AppStorage("SmartDetect") var smartDetect = false
    @AppStorage("SmartPunctuation") var smartPunctuation = true
    @AppStorage("RemoveFillerWords") var removeFillers = false

    // MARK: output
    @AppStorage("InsertIntoApp") var insertIntoApp = true
    @AppStorage("AlsoCopyClipboard") var alsoCopyToClipboard = false
    @AppStorage("PlaySounds") var playSounds = false

    // MARK: cleanup (optional local LLM pass)
    @AppStorage("CleanupEnabled") var cleanupEnabled = false
    @AppStorage("CleanupFixTypos") var cleanupFixTypos = true
    @AppStorage("CleanupGrammar") var cleanupGrammar = false
    @AppStorage("CleanupPreserveStyle") var cleanupPreserveStyle = true
    @AppStorage("CleanupModelInstalled") var cleanupModelInstalled = false
    /// "balanced" = LFM2.5-350M (fast) · "best" = bake-off winner (context fixes)
    @AppStorage("CleanupTier") var cleanupTier = "balanced"

    // MARK: models / compute
    @AppStorage("LowPowerMode") var lowPowerMode = false

    // MARK: privacy
    @AppStorage("StoreAudio") var storeAudio = true
    @AppStorage("SaveHistory") var saveHistory = true
    @AppStorage("AudioRetentionDays") var retentionDays = 14
    @AppStorage("AutoCollectWords") var autoCollect = true

    // MARK: vocabulary
    struct Replacement: Codable, Identifiable, Equatable {
        var id = UUID()
        var spoken: String
        var written: String
    }
    struct Vocabulary: Codable {
        var words: [String] = []
        var replacements: [Replacement] = []
        var suggestions: [String] = []
    }
    @Published var vocabulary = Vocabulary() {
        didSet { saveVocabulary() }
    }

    private var vocabFile: URL {
        HistoryStore.dataDir.appendingPathComponent("vocab.json")
    }

    private init() {
        if let data = try? Data(contentsOf: vocabFile),
           let v = try? JSONDecoder().decode(Vocabulary.self, from: data) {
            vocabulary = v
        }
    }

    private func saveVocabulary() {
        try? FileManager.default.createDirectory(at: HistoryStore.dataDir,
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(vocabulary) {
            try? data.write(to: vocabFile, options: .atomic)
        }
    }

    /// Deterministic spoken→written substitutions applied to final transcripts.
    func applyReplacements(_ text: String) -> String {
        var out = text
        for r in vocabulary.replacements where !r.spoken.isEmpty {
            out = out.replacingOccurrences(of: r.spoken, with: r.written,
                                           options: [.caseInsensitive])
        }
        return out
    }

    /// Full deterministic post-processing for a final transcript:
    /// replacements → optional filler removal → optional punctuation strip.
    func postProcess(_ text: String) -> String {
        var out = applyReplacements(text)
        if removeFillers {
            out = out.replacingOccurrences(
                of: #"(?i)\b(um+|uh+|erm*|hmm+)\b[,.]?\s*"#,
                with: "", options: .regularExpression)
            out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ",
                                           options: .regularExpression)
        }
        if !smartPunctuation {
            out = out.replacingOccurrences(of: #"[.,!?;:…]"#, with: "",
                                           options: .regularExpression)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Heuristic "new word" collection: unusual words worth suggesting for the
    /// user's dictionary (proper-noun-ish or long rare tokens).
    func collectSuggestions(from text: String) {
        guard autoCollect else { return }
        let known = Set(vocabulary.words.map { $0.lowercased() })
            .union(vocabulary.suggestions.map { $0.lowercased() })
        let checker = NSSpellChecker.shared
        var added = vocabulary.suggestions
        for raw in text.split(separator: " ") {
            let w = raw.trimmingCharacters(in: .punctuationCharacters)
            guard w.count >= 4, !known.contains(w.lowercased()) else { continue }
            let miss = checker.checkSpelling(of: w, startingAt: 0)
            if miss.location != NSNotFound, added.count < 30, !added.contains(w) {
                added.append(w)
            }
        }
        if added != vocabulary.suggestions {
            vocabulary.suggestions = added
        }
    }
}

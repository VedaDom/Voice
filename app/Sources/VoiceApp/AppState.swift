import Foundation
import SwiftUI

enum EngineState: Equatable {
    case launching
    case downloading(Double)   // 0...1
    case loading
    case warming
    case ready
    case recording
    case paused
    case transcribing
    case error(String)

    var statusLine: String {
        switch self {
        case .launching: return "Starting…"
        case .downloading(let p): return "Downloading model · \(Int(p * 100))%"
        case .loading: return "Loading model…"
        case .warming: return "Warming up…"
        case .ready: return "Ready"
        case .recording: return "Listening…"
        case .paused: return "Paused"
        case .transcribing: return "Transcribing…"
        case .error: return "Setup needed"
        }
    }
}

struct Note: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var wav: String
    var date: Date
    var duration: Double
    var starred: Bool? = nil   // optional: stays decodable for pre-star history files
}

@MainActor
final class AppState: ObservableObject {
    @Published var engine: EngineState = .launching
    @Published var partial: String = ""
    @Published var level: Double = 0          // raw 0...1 from worker (~20 Hz)
    @Published var notes: [Note] = []
    @Published var accessibilityTrusted: Bool = false
    /// True from the moment WE request a session until final/cancel — independent
    /// of the worker's state echo, so a fast key release can never get lost.
    @Published var sessionActive: Bool = false

    enum CleanupModelState: Equatable {
        case none, downloading(Double), ready, failed(String)
    }
    @Published var cleanupState: CleanupModelState = .none
    /// Note id currently being re-transcribed (Library shows a spinner).
    @Published var retranscribing: UUID?

    var isRecording: Bool { engine == .recording }

    var language: String { SettingsStore.shared.language }

    /// e.g. "right ⌘ or fn" depending on which triggers are enabled.
    var hotkeyHint: String {
        let s = SettingsStore.shared
        var keys: [String] = []
        if s.hotkeyRightCmd { keys.append("right ⌘") }
        if s.hotkeyFn { keys.append("fn") }
        if keys.isEmpty { keys.append("right ⌘ (enable in Settings)") }
        return keys.joined(separator: " or ")
    }

    var statusLine: String {
        engine == .ready ? "Ready · hold \(hotkeyHint)" : engine.statusLine
    }
}

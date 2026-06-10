import Foundation

/// Notes persisted as JSON under ~/Library/Application Support/Voice.
enum HistoryStore {
    static var dataDir: URL {
        if let env = ProcessInfo.processInfo.environment["VOICE_DATA_DIR"] {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voice")
    }

    private static var file: URL { dataDir.appendingPathComponent("history.json") }

    static func load() -> [Note] {
        guard let data = try? Data(contentsOf: file),
              let notes = try? JSONDecoder().decode([Note].self, from: data)
        else { return [] }
        return notes
    }

    static func save(_ notes: [Note]) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let capped = Array(notes.prefix(2000))
        if let data = try? JSONEncoder().encode(capped) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Audio retention: recordings older than 14 days are deleted to keep disk
    /// usage flat; the transcript stays forever. Also removes orphan WAVs.
    static let audioRetentionDays = 14

    static func sweepOldAudio(_ notes: [Note]) -> [Note] {
        let cutoff = Date().addingTimeInterval(-Double(audioRetentionDays) * 86400)
        let fm = FileManager.default
        var swept = notes
        var referenced = Set<String>()
        for i in swept.indices {
            if !swept[i].wav.isEmpty {
                if swept[i].date < cutoff {
                    try? fm.removeItem(atPath: swept[i].wav)
                    swept[i].wav = ""
                } else {
                    referenced.insert((swept[i].wav as NSString).lastPathComponent)
                }
            }
        }
        let audioDir = dataDir.appendingPathComponent("audio")
        if let files = try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: [.creationDateKey]) {
            for f in files where !referenced.contains(f.lastPathComponent) {
                let created = (try? f.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                if created < cutoff {
                    try? fm.removeItem(at: f)
                }
            }
        }
        save(swept)
        return swept
    }
}

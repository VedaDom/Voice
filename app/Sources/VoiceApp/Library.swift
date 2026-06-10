import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class LibraryController {
    private var window: NSWindow?
    private let state: AppState
    var onRetranscribe: (Note) -> Void = { _ in }

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                     .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.minSize = NSSize(width: 860, height: 540)
        w.backgroundColor = NSColor(Theme.pane)
        w.contentView = NSHostingView(
            rootView: LibraryView(state: state,
                                  onRetranscribe: { [weak self] in
                                      self?.onRetranscribe($0)
                                  })
        )
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct LibraryView: View {
    @ObservedObject var state: AppState
    var onRetranscribe: (Note) -> Void = { _ in }
    @State private var query = ""
    @State private var selectedID: UUID?

    private var filtered: [Note] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return state.notes }
        return state.notes.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var selected: Note? {
        filtered.first { $0.id == selectedID } ?? filtered.first
    }

    var body: some View {
        // plain HStack — HSplitView draws a dark system divider that fights
        // the design's soft hairline
        HStack(spacing: 0) {
            sidebar
                .frame(width: 322)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
    }

    // ------------------------------------------------------------- sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("All Notes")
                    .font(Theme.fraunces(21))
                    .kerning(-0.3)
                    .foregroundStyle(Theme.ink)
                Text("\(filtered.count)")
                    .font(Theme.inter(13, .medium))
                    .foregroundStyle(Theme.ink3)
                Spacer()
            }
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 12, trailing: 18))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.inter(13))
                    .foregroundStyle(Theme.ink)
            }
            .padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11))
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.doc))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            .padding(EdgeInsets(top: 0, leading: 14, bottom: 12, trailing: 14))

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(grouped, id: \.0) { section, notes in
                        Text(section)
                            .font(Theme.inter(10.5, .bold))
                            .kerning(1.3)
                            .foregroundStyle(Theme.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 16, leading: 18, bottom: 8, trailing: 18))
                        ForEach(notes) { note in
                            SidebarRow(note: note, isActive: note.id == selected?.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedID = note.id }
                        }
                    }
                    if filtered.isEmpty {
                        Text(query.isEmpty ? "No notes yet — hold \(state.hotkeyHint) and speak."
                                           : "No matches for “\(query)”.")
                            .font(Theme.inter(12.5))
                            .foregroundStyle(Theme.ink3)
                            .padding(.top, 40)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 26) // room for traffic lights
        .background(Theme.pane)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private var grouped: [(String, [Note])] {
        let cal = Calendar.current
        var out: [(String, [Note])] = []
        for note in filtered {
            let label: String
            if cal.isDateInToday(note.date) { label = "TODAY" }
            else if cal.isDateInYesterday(note.date) { label = "YESTERDAY" }
            else {
                let f = DateFormatter()
                f.dateFormat = note.date.timeIntervalSinceNow > -6 * 86400 ? "EEEE" : "MMM d"
                label = f.string(from: note.date).uppercased()
            }
            if out.last?.0 == label {
                out[out.count - 1].1.append(note)
            } else {
                out.append((label, [note]))
            }
        }
        return out
    }

    // ------------------------------------------------------------- detail
    @ViewBuilder
    private var detail: some View {
        if let note = selected {
            NoteDetail(state: state, note: note, onRetranscribe: onRetranscribe)
                .id(note.id)
        } else {
            VStack {
                Text("Select a note")
                    .font(Theme.fraunces(16, .regular))
                    .foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.doc)
        }
    }
}

private struct SidebarRow: View {
    let note: Note
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                Text(note.title)
                    .font(Theme.fraunces(15.5))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                Text(note.shortTime)
                    .font(Theme.inter(11.5))
                    .foregroundStyle(Theme.ink3)
            }
            Text(note.text)
                .font(Theme.inter(12.5))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("VOICE NOTE")
                .font(Theme.inter(10, .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.ink3)
        }
        .padding(EdgeInsets(top: 13, leading: isActive ? 14 : 16, bottom: 13, trailing: 16))
        .background(isActive ? Theme.sel : .clear)
        .overlay(alignment: .leading) {
            if isActive { Rectangle().fill(Theme.accent).frame(width: 2) }
        }
        .overlay(alignment: .bottom) {
            if !isActive { Rectangle().fill(Theme.line2).frame(height: 1).padding(.horizontal, 16) }
        }
    }
}

private struct NoteDetail: View {
    @ObservedObject var state: AppState
    let note: Note
    var onRetranscribe: (Note) -> Void = { _ in }
    @ObservedObject private var settings = SettingsStore.shared
    @State private var copied = false

    private var isStarred: Bool {
        state.notes.first { $0.id == note.id }?.starred ?? false
    }

    private var liveNote: Note {
        state.notes.first { $0.id == note.id } ?? note
    }

    private var hasAudio: Bool {
        !note.wav.isEmpty && FileManager.default.fileExists(atPath: note.wav)
    }

    var body: some View {
        VStack(spacing: 0) {
            // live text (re-transcription may update it while this view is open)
            let display = liveNote
            HStack(spacing: 3) {
                Spacer()
                toolbarButton(isStarred ? "star.fill" : "star",
                              tint: isStarred ? Theme.accent : Theme.ink3,
                              help: "Star") { toggleStar() }
                toolbarButton(copied ? "checkmark" : "square.on.square",
                              tint: copied ? Theme.accent : Theme.ink3,
                              help: "Copy transcript") {
                    Paster.copy(liveNote.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                ShareLink(item: liveNote.text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Share")
                if state.retranscribing == note.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 32, height: 32)
                        .help("Re-transcribing…")
                } else {
                    Menu {
                        if hasAudio {
                            Button("Re-transcribe") { onRetranscribe(liveNote) }
                                .keyboardShortcut("r", modifiers: .command)
                            Button("Export Audio…") { exportAudio() }
                            Button("Reveal Audio in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: note.wav)])
                            }
                            Divider()
                        }
                        Toggle("Auto-collect new words", isOn: $settings.autoCollect)
                        Divider()
                        Button("Delete Note", role: .destructive) { deleteNote() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.ink3)
                            .frame(width: 32, height: 32)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 32, height: 32)
                }
            }
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 4, trailing: 20))

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 9) {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            Text(metaLine)
                                .font(Theme.inter(11, .semibold))
                                .kerning(0.8)
                                .foregroundStyle(Theme.ink3)
                        }
                        Text(display.title)
                            .font(Theme.fraunces(33))
                            .kerning(-0.6)
                            .lineSpacing(4)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 19) {
                        ForEach(Array(display.paragraphs.enumerated()), id: \.offset) { _, p in
                            Text(p)
                                .font(Theme.fraunces(19, .regular))
                                .kerning(-0.1)
                                .lineSpacing(13)
                                .foregroundStyle(Color(hex: 0x34332E))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: 632)
                .padding(EdgeInsets(top: 8, leading: 40, bottom: 28, trailing: 40))
                .frame(maxWidth: .infinity)
            }

            AudioBar(note: note)
        }
        .background(Theme.doc)
    }

    private var metaLine: String {
        let words = liveNote.text.split(separator: " ").count
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(note.date) { f.dateFormat = "'TODAY' H:mm" }
        else if cal.isDateInYesterday(note.date) { f.dateFormat = "'YESTERDAY' H:mm" }
        else { f.dateFormat = "MMM d · H:mm" }
        return "VOICE NOTE · \(f.string(from: note.date).uppercased()) · \(note.durationLabel) · \(words) WORDS"
    }

    private func toggleStar() {
        if let i = state.notes.firstIndex(where: { $0.id == note.id }) {
            state.notes[i].starred = !(state.notes[i].starred ?? false)
            HistoryStore.save(state.notes)
        }
    }

    private func deleteNote() {
        if let i = state.notes.firstIndex(where: { $0.id == note.id }) {
            let wav = state.notes[i].wav
            if !wav.isEmpty { try? FileManager.default.removeItem(atPath: wav) }
            state.notes.remove(at: i)
            HistoryStore.save(state.notes)
        }
    }

    private func exportAudio() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(note.title).wav"
        panel.allowedContentTypes = [.wav]
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: note.wav), to: dest)
        }
    }

    private func toolbarButton(_ symbol: String, tint: Color, help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13.5))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// ------------------------------------------------------------- audio player
private struct AudioBar: View {
    let note: Note
    @StateObject private var player = AudioPlayerModel()

    var body: some View {
        Group {
            if !note.wav.isEmpty, FileManager.default.fileExists(atPath: note.wav) {
                HStack(spacing: 16) {
                    Button {
                        player.toggle(path: note.wav)
                    } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.accent))
                    }
                    .buttonStyle(.plain)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line).frame(height: 4)
                            Capsule().fill(Theme.accent)
                                .frame(width: max(6, geo.size.width * player.progress), height: 4)
                            Circle().fill(Theme.accent)
                                .frame(width: 12, height: 12)
                                .offset(x: max(0, geo.size.width * player.progress - 6))
                        }
                        .frame(height: 12)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            player.seek(fraction: v.location.x / geo.size.width, path: note.wav)
                        })
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 32)

                    Text("\(format(player.current)) / \(format(player.durationOr(note.duration)))")
                        .font(Theme.inter(12.5, .medium))
                        .foregroundStyle(Theme.ink2)
                        .monospacedDigit()

                    Button {
                        player.cycleRate()
                    } label: {
                        Text(String(format: "%.2g×", player.rate))
                            .font(Theme.inter(11.5, .semibold))
                            .foregroundStyle(Theme.ink2)
                            .padding(EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9))
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.pane))
                    }
                    .buttonStyle(.plain)
                    .help("Playback speed")
                }
                .padding(EdgeInsets(top: 15, leading: 40, bottom: 15, trailing: 40))
            } else {
                HStack {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink3)
                    Text("Audio cleared after \(HistoryStore.audioRetentionDays) days — transcript kept.")
                        .font(Theme.inter(12))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                }
                .padding(EdgeInsets(top: 15, leading: 40, bottom: 15, trailing: 40))
            }
        }
        .background(Theme.doc)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .onDisappear { player.stop() }
    }

    private func format(_ t: Double) -> String {
        "\(Int(t) / 60):\(String(format: "%02d", Int(t) % 60))"
    }
}

@MainActor
final class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var progress: Double = 0
    @Published var current: Double = 0
    @Published var rate: Float = 1.0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func durationOr(_ fallback: Double) -> Double {
        player?.duration ?? fallback
    }

    func cycleRate() {
        let steps: [Float] = [1.0, 1.25, 1.5, 2.0]
        rate = steps[((steps.firstIndex(of: rate) ?? 0) + 1) % steps.count]
        player?.rate = rate
    }

    func toggle(path: String) {
        if playing {
            player?.pause()
            playing = false
            timer?.invalidate()
            return
        }
        if player == nil || player?.url?.path != path {
            player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player?.enableRate = true
            player?.delegate = self
        }
        player?.rate = rate
        player?.play()
        playing = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
    }

    func seek(fraction: Double, path: String) {
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player?.delegate = self
        }
        guard let p = player else { return }
        p.currentTime = max(0, min(1, fraction)) * p.duration
        tick()
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
        playing = false
    }

    private func tick() {
        guard let p = player else { return }
        current = p.currentTime
        progress = p.duration > 0 ? p.currentTime / p.duration : 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.playing = false
            self.timer?.invalidate()
            self.progress = 1
        }
    }
}

// ------------------------------------------------------------- note helpers
extension Note {
    var title: String {
        let words = text.split(separator: " ").prefix(6)
        var t = words.joined(separator: " ")
        if let r = t.range(of: #"[.,!?;:]+$"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        return t.isEmpty ? "Voice note" : t
    }

    var paragraphs: [String] {
        // group sentences into ~2-sentence reading paragraphs
        var sentences: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if ".!?".contains(ch) {
                sentences.append(cur.trimmingCharacters(in: .whitespaces))
                cur = ""
            }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append(cur.trimmingCharacters(in: .whitespaces))
        }
        if sentences.isEmpty { return [text] }
        return stride(from: 0, to: sentences.count, by: 2).map {
            sentences[$0..<min($0 + 2, sentences.count)].joined(separator: "  ")
        }
    }

    var shortTime: String {
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(date) { f.dateFormat = "H:mm" }
        else if cal.isDateInYesterday(date) { f.dateFormat = "EEE" }
        else { f.dateFormat = "MMM d" }
        return f.string(from: date)
    }

    var longDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · H:mm"
        return f.string(from: date)
    }

    var durationLabel: String {
        "\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))"
    }
}

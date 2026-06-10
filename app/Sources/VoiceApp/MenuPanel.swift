import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusController: NSObject {
    private var item: NSStatusItem!
    private var panel: NSPanel?
    private var dismissMonitors: [Any] = []
    private let state: AppState
    private var levelSub: AnyCancellable?
    private var animTimer: Timer?
    private var phase: Double = 0
    private var smoothLevel: Double = 0

    var onPaste: (Note) -> Void = { _ in }
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    var onComplete: () -> Void = {}
    var onCancel: () -> Void = {}
    var onOpenLibrary: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    private let updates: UpdateChecker

    init(state: AppState, updates: UpdateChecker) {
        self.state = state
        self.updates = updates
        super.init()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.idleImage()
            button.action = #selector(clicked)
            button.target = self
        }

        levelSub = state.$level.sink { [weak self] lv in
            guard let self else { return }
            self.smoothLevel = max(lv, self.smoothLevel * 0.82)
        }
    }

    // ---------------------------------------------------------------- icon
    func refresh() {
        switch state.engine {
        case .recording:
            startAnimating()
        case .paused:
            stopAnimating()
            item.button?.image = Self.barsImage(level: 0.25, phase: 0,
                                                color: NSColor(Theme.accent).withAlphaComponent(0.55))
        default:
            stopAnimating()
            item.button?.image = Self.idleImage()
        }
    }

    private func startAnimating() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.phase += 0.55
                self.item.button?.image = Self.barsImage(level: self.smoothLevel,
                                                         phase: self.phase,
                                                         color: NSColor(Theme.accent))
            }
        }
    }

    private func stopAnimating() {
        animTimer?.invalidate()
        animTimer = nil
    }

    private static func idleImage() -> NSImage? {
        let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice")?
            .withSymbolConfiguration(.init(pointSize: 14.5, weight: .medium))
        img?.isTemplate = true
        return img
    }

    /// Five accent bars dancing with the live voice level.
    private static func barsImage(level: Double, phase: Double, color: NSColor) -> NSImage {
        let size = NSSize(width: 20, height: 17)
        let base: [Double] = [0.42, 0.7, 1.0, 0.7, 0.42]
        let img = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            let barW: CGFloat = 2.4
            let gap: CGFloat = 1.5
            let total = barW * 5 + gap * 4
            var x = (rect.width - total) / 2
            for (i, b) in base.enumerated() {
                let wobble = 0.72 + 0.28 * sin(phase + Double(i) * 1.15)
                let energy = 0.30 + 0.70 * min(1.0, level * 1.6)
                let h = max(3.0, rect.height * CGFloat(b * wobble * energy))
                let y = (rect.height - h) / 2
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: h),
                             xRadius: 1.2, yRadius: 1.2).fill()
                x += barW + gap
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    // ---------------------------------------------------------------- click
    @objc private func clicked() {
        if state.sessionActive {
            showRecordingMenu()
        } else {
            togglePanel()
        }
    }

    private func showRecordingMenu() {
        let menu = NSMenu()
        let paused = state.engine == .paused

        let toggle = NSMenuItem(title: paused ? "Resume" : "Pause",
                                action: #selector(menuPauseResume), keyEquivalent: "")
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill",
                               accessibilityDescription: nil)
        menu.addItem(toggle)

        let complete = NSMenuItem(title: "Complete & Paste",
                                  action: #selector(menuComplete), keyEquivalent: "")
        complete.target = self
        complete.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                 accessibilityDescription: nil)
        menu.addItem(complete)

        menu.addItem(.separator())

        let cancel = NSMenuItem(title: "Discard", action: #selector(menuCancel), keyEquivalent: "")
        cancel.target = self
        cancel.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(cancel)

        item.popUpMenu(menu)
    }

    @objc private func menuPauseResume() {
        state.engine == .paused ? onResume() : onPause()
    }
    @objc private func menuComplete() { onComplete() }
    @objc private func menuCancel() { onCancel() }

    // ---------------------------------------------------------------- panel
    private func togglePanel() {
        if panel != nil { closePanel(); return }
        guard let button = item.button, let btnWindow = button.window,
              let screen = btnWindow.screen ?? NSScreen.main else { return }

        updates.checkDaily()
        let host = NSHostingController(
            rootView: PanelView(state: state,
                                updates: updates,
                                onPaste: { [weak self] note in
                                    self?.closePanel()
                                    self?.onPaste(note)
                                },
                                onOpenLibrary: { [weak self] in
                                    self?.closePanel()
                                    self?.onOpenLibrary()
                                },
                                onOpenSettings: { [weak self] in
                                    self?.closePanel()
                                    self?.onOpenSettings()
                                })
        )
        // deterministic size + no auto-resizing: SwiftUI must never move the
        // window after we place it (auto-resize keeps the BOTTOM edge fixed,
        // which dropped the panel toward mid-screen)
        host.sizingOptions = []
        let bannerH: CGFloat = updates.available != nil ? 54 : 0
        let size = NSSize(width: 352, height: (state.notes.isEmpty ? 196 : 448) + bannerH)

        // hug the menu bar like native status popovers: top edge 8 pt below it
        let btnFrame = btnWindow.frame
        var x = btnFrame.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8),
                screen.frame.maxX - size.width - 8)

        let p = NSPanel(contentRect: NSRect(x: x, y: 0, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.contentViewController = host
        p.setContentSize(size)
        p.setFrameTopLeftPoint(NSPoint(x: x, y: btnFrame.minY - 8))
        p.isReleasedWhenClosed = false
        p.orderFrontRegardless()
        panel = p

        // dismiss on any click outside the panel
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            if let self, let p = self.panel, e.window !== p, e.window !== self.item.button?.window {
                self.closePanel()
            }
            return e
        }
        dismissMonitors = [global, local].compactMap { $0 }
    }

    private func closePanel() {
        for m in dismissMonitors { NSEvent.removeMonitor(m) }
        dismissMonitors = []
        panel?.orderOut(nil)
        panel = nil
    }
}

struct PanelView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updates: UpdateChecker
    var onPaste: (Note) -> Void
    var onOpenLibrary: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            label
            rows
            Spacer(minLength: 0)
            updateBanner
        }
        .frame(width: 352)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.doc)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(1)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Voice")
                    .font(Theme.fraunces(18))
                    .kerning(-0.3)
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(state.statusLine)
                        .font(Theme.inter(11.5))
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
    }

    @ViewBuilder
    private var updateBanner: some View {
        if let release = updates.available {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.ember)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Voice \(release.version) is ready")
                        .font(Theme.inter(12.5, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Installs and relaunches — notes are kept.")
                        .font(Theme.inter(10.5))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                Button {
                    updates.install()
                } label: {
                    Group {
                        if updates.installing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Install")
                                .font(Theme.inter(11, .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(updates.installing)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .background(Theme.sel)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
        }
    }

    private var statusColor: Color {
        switch state.engine {
        case .ready, .recording: return Theme.accent
        case .paused: return Theme.ink3
        case .error: return Color(hex: 0xC9A227)
        default: return Theme.ink3
        }
    }

    private var label: some View {
        HStack {
            Text("RECENT")
                .font(Theme.inter(10, .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.ink3)
            Spacer()
            Button(action: onOpenLibrary) {
                Text("Open Library")
                    .font(Theme.inter(11.5, .semibold))
                    .foregroundStyle(Theme.ink2)
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 8, trailing: 18))
    }

    @ViewBuilder
    private var rows: some View {
        if state.notes.isEmpty {
            VStack(spacing: 4) {
                Text("Nothing here yet")
                    .font(Theme.fraunces(14, .regular))
                    .foregroundStyle(Theme.ink2)
                Text("Hold \(state.hotkeyHint) and speak · double-tap to lock.")
                    .font(Theme.inter(11.5))
                    .foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.notes.prefix(30).enumerated()), id: \.element.id) { i, note in
                        NoteRow(note: note, isActive: i == 0, onPaste: onPaste)
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let isActive: Bool
    var onPaste: (Note) -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(note.text)
                .font(Theme.fraunces(14, .regular))
                .foregroundStyle(isActive ? Theme.ink : Theme.ink2)
                .lineSpacing(3)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(meta)
                    .font(Theme.inter(10.5, .medium))
                    .kerning(0.3)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                if isActive {
                    Button { onPaste(note) } label: {
                        HStack(spacing: 6) {
                            Text("Paste").font(Theme.inter(10.5, .semibold))
                            Text("↵").font(Theme.inter(10.5)).opacity(0.7)
                        }
                        .foregroundStyle(.white)
                        .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                        .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Paster.copy(note.text)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "square.on.square")
                            .font(.system(size: 11))
                            .foregroundStyle(copied ? Theme.accent : Theme.ink3)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering || copied ? 1 : 0.45)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: isActive ? 16 : 18, bottom: 12, trailing: 18))
        .background(isActive ? Theme.sel : .clear)
        .overlay(alignment: .leading) {
            if isActive { Rectangle().fill(Theme.accent).frame(width: 2) }
        }
        .overlay(alignment: .bottom) {
            if !isActive { Rectangle().fill(Theme.line2).frame(height: 1) }
        }
        .onHover { hovering = $0 }
    }

    private var meta: String {
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(note.date) { f.dateFormat = "H:mm" }
        else if cal.isDateInYesterday(note.date) { f.dateFormat = "'Yesterday'" }
        else { f.dateFormat = "EEE" }
        let m = Int(note.duration) / 60
        let s = Int(note.duration) % 60
        return "\(f.string(from: note.date)) · \(m):\(String(format: "%02d", s))"
    }
}

import AppKit
import SwiftUI

@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private let state: AppState
    var onRetry: () -> Void = {}

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(Theme.bg)
        w.contentView = NSHostingView(
            rootView: OnboardingView(state: state, onRetry: { [weak self] in self?.onRetry() })
        )
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    @ObservedObject var state: AppState
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            Theme.bg
            aura
            content
                .padding(EdgeInsets(top: 14, leading: 44, bottom: 30, trailing: 44))
        }
        .frame(width: 460, height: 580)
        .clipped()
    }

    @ViewBuilder private var aura: some View {
        switch state.engine {
        case .error:
            radial(Color(hex: 0x9A9387, alpha: 0x33))
        case .ready, .recording:
            RadialGradient(stops: [.init(color: Color(hex: 0xEC6B4A, alpha: 0x38), location: 0),
                                   .init(color: Color(hex: 0xEC6B4A, alpha: 0), location: 1)],
                           center: .center, startRadius: 0, endRadius: 240)
                .frame(width: 600, height: 420)
                .offset(y: -40)
        default:
            radial(Color(hex: 0xEC6B4A, alpha: 0x33))
        }
    }

    private func radial(_ c: Color) -> some View {
        RadialGradient(stops: [.init(color: c, location: 0),
                               .init(color: c.opacity(0), location: 1)],
                       center: .bottom, startRadius: 0, endRadius: 200)
            .frame(width: 520, height: 320)
            .offset(y: 130)
    }

    @ViewBuilder private var content: some View {
        switch state.engine {
        case .ready, .recording: ready
        case .error(let msg): failed(msg)
        default: preparing
        }
    }

    // ---------------------------------------------------------------- states
    private var preparing: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Orb(size: 78) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 7) {
                    Text("Voice")
                        .font(Theme.fraunces(30))
                        .kerning(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text("Real-time dictation, fully on your Mac.")
                        .font(Theme.inter(13.5))
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer()
            VStack(spacing: 13) {
                Text("Getting things ready")
                    .font(Theme.fraunces(19))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.ink)
                Text("Setting up the on-device speech model so everything stays private and works offline.")
                    .font(Theme.inter(13))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                progress
                    .padding(.top, 8)
            }
            Spacer()
            Text("This only happens once — no setup needed.")
                .font(Theme.inter(12))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.top, 28)
    }

    private var progressPct: Double {
        switch state.engine {
        case .downloading(let p): return p
        case .loading: return 1.0
        case .warming: return 1.0
        default: return 0
        }
    }

    private var progressLabel: String {
        switch state.engine {
        case .downloading: return "Downloading speech model · 1.2 GB"
        case .loading: return "Loading model"
        case .warming: return "Warming up"
        default: return "Checking…"
        }
    }

    private var progress: some View {
        VStack(spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0xF4A861), Color(hex: 0xE5483A)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * progressPct))
                        .animation(.easeOut(duration: 0.4), value: progressPct)
                }
            }
            .frame(height: 6)
            HStack {
                Text(progressLabel)
                    .font(Theme.inter(12, .medium))
                    .foregroundStyle(Theme.ink3)
                Spacer()
                Text("\(Int(progressPct * 100))%")
                    .font(Theme.inter(12, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .monospacedDigit()
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color(hex: 0xEFEBE1))
                        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 78, height: 78)
                VStack(spacing: 7) {
                    Text("Setup couldn’t finish")
                        .font(Theme.fraunces(27))
                        .kerning(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text("The speech model didn’t finish downloading. Check your connection and try again — nothing else is needed.")
                        .font(Theme.inter(13.5))
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
            }
            Spacer()
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink3)
                    Text(message.isEmpty ? "Setup error" : message)
                        .font(Theme.inter(12.5, .medium))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
                .padding(EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.pane))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))

                Button(action: onRetry) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                        Text("Retry").font(Theme.inter(13.5, .semibold))
                    }
                    .foregroundStyle(Theme.bg)
                    .padding(EdgeInsets(top: 11, leading: 18, bottom: 11, trailing: 18))
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.ink))
                    .shadow(color: Color(hex: 0x1A1A1A, alpha: 0x33), radius: 6, y: 4)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Voice can’t start until setup completes.")
                .font(Theme.inter(12))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.top, 28)
    }

    private var ready: some View {
        VStack(spacing: 0) {
            Text("Voice")
                .font(Theme.fraunces(16))
                .kerning(0.2)
                .foregroundStyle(Theme.ink3)
            Spacer()
            VStack(spacing: 20) {
                Orb(size: 104, glow: 0.35) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    Text("You’re all set")
                        .font(Theme.fraunces(28))
                        .kerning(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text("Everything’s ready and running entirely on your Mac.")
                        .font(Theme.inter(13.5))
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
            }
            Spacer()
            VStack(spacing: 11) {
                keycap("right ⌘")
                Text("Hold right ⌘ anywhere to dictate — or double-tap to keep recording hands-free.")
                    .font(Theme.inter(13))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                if !state.accessibilityTrusted {
                    Button {
                        Paster.promptForAccessibility()
                    } label: {
                        Text("Allow Accessibility so Voice can type for you →")
                            .font(Theme.inter(11.5, .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.top, 24)
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(Theme.inter(13.5, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13))
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.doc))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Color(hex: 0x1A1A1A, alpha: 0x1F), radius: 1.5, y: 2)
    }
}

/// Ember-gradient circle with the soft red glow shadow.
struct Orb<Content: View>: View {
    var size: CGFloat
    var glow: Double = 0.3
    @ViewBuilder var content: Content

    var body: some View {
        ZStack { content }
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.ember))
            .shadow(color: Theme.accent.opacity(glow), radius: size * 0.36, y: size * 0.13)
    }
}

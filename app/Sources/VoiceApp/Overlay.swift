import AppKit
import SwiftUI

/// Full-width, click-through window hugging the bottom of the screen:
/// three stacked radial glows (amber → coral → red) that breathe with the
/// voice level, with the live transcript in Fraunces above them.
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func show() {
        guard panel == nil else { fadeIn(); return }
        guard let screen = NSScreen.main else { return }

        let height = min(420, screen.frame.height * 0.45)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                           width: screen.frame.width, height: height)

        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: OverlayView(state: state))
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p
        fadeIn()
    }

    func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        })
    }

    private func fadeIn() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 1
        }
    }
}

struct OverlayView: View {
    @ObservedObject var state: AppState
    @State private var smooth: Double = 0
    @State private var caretOn = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let k = w / 1440.0  // design scale
            let boost = 0.82 + 0.5 * smooth

            ZStack(alignment: .bottom) {
                glow(color: Color(hex: 0xF0A05A, alpha: 0x40),
                     size: CGSize(width: 1200 * k, height: 600 * k),
                     wRatio: 0.66, boost: boost, w: w, h: h)
                glow(color: Color(hex: 0xEC6B4A, alpha: 0x4D),
                     size: CGSize(width: 800 * k, height: 430 * k),
                     wRatio: 0.55, boost: boost, w: w, h: h)
                glow(color: Color(hex: 0xE5483A, alpha: 0x45),
                     size: CGSize(width: 480 * k, height: 260 * k),
                     wRatio: 0.62, boost: 0.78 + 0.62 * smooth, w: w, h: h)

                caption
                    .padding(.bottom, 64 * k)
            }
            .frame(width: w, height: h, alignment: .bottom)
        }
        .allowsHitTesting(false)
        .onChange(of: state.level) { _, new in
            // fast attack, slow decay — feels like breath
            let target = max(0.05, new)
            withAnimation(.easeOut(duration: target > smooth ? 0.09 : 0.45)) {
                smooth = target
            }
        }
        .onReceive(Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()) { _ in
            caretOn.toggle()
        }
    }

    private var caption: some View {
        HStack(spacing: 13) {
            HStack(spacing: 12) {
                ForEach(tailWords, id: \.id) { w in
                    Text(w.text)
                        .font(Theme.fraunces(34))
                        .kerning(-0.5)
                        .foregroundStyle(Theme.accent)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: tailWords.map(\.id))
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: 2.5, height: 32)
                .opacity(caretOn ? 1 : 0.15)
                .animation(.easeInOut(duration: 0.18), value: caretOn)
        }
    }

    /// The newest two words; ids are transcript positions, so as speech grows
    /// the oldest word fades out and the newest fades in.
    private var tailWords: [(id: Int, text: String)] {
        let all = state.partial
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
        return all.enumerated().suffix(2).map { (id: $0.offset, text: String($0.element)) }
    }

    private func glow(color: Color, size: CGSize, wRatio: Double,
                      boost: Double, w: CGFloat, h: CGFloat) -> some View {
        // Bottom-anchored bloom (.pen: radial gradient, center.y = 1). The
        // voice level animates the gradient RADIUS — never the geometry — and
        // the radius is capped just under the window height so the fade always
        // completes inside the window: no hard clip line, however loud.
        let radius = min(size.width * wRatio / 2 * boost, h - 12)
        return Rectangle()
            .fill(
                RadialGradient(
                    stops: [.init(color: color, location: 0),
                            .init(color: color.opacity(0), location: 1)],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: w, height: h)
            .allowsHitTesting(false)
    }
}

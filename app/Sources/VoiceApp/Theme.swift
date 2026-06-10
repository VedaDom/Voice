import SwiftUI
import CoreText

// Design tokens from voice.pen
enum Theme {
    static let bg = Color(hex: 0xFAFAF9)
    static let doc = Color(hex: 0xFFFFFF)
    static let pane = Color(hex: 0xF3F3F1)
    static let ink = Color(hex: 0x1E1E1C)
    static let ink2 = Color(hex: 0x6C6C66)
    static let ink3 = Color(hex: 0xA4A49C)
    static let line = Color(hex: 0xE9E8E3)
    static let line2 = Color(hex: 0xF0EFEB)
    static let accent = Color(hex: 0xE5483A)
    static let accent2 = Color(hex: 0xC73A2E)
    static let sel = Color(hex: 0xE5483A, alpha: 0x12)

    // Ember brand gradient (orb / check / progress)
    static let ember = AngularGradient(
        stops: [
            .init(color: Color(hex: 0xF4A861), location: 0),
            .init(color: Color(hex: 0xEC6B4A), location: 0.42),
            .init(color: Color(hex: 0xE5483A), location: 0.72),
            .init(color: Color(hex: 0xF4A861), location: 1),
        ],
        center: .center,
        angle: .degrees(-120)
    )

    static func fraunces(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("Fraunces", size: size).weight(weight)
    }

    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    static func registerFonts() {
        guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil) else {
            NSLog("Voice: bundled Fonts directory not found; falling back to system fonts")
            return
        }
        for name in ["Fraunces.ttf", "Inter.ttf"] {
            let url = dir.appendingPathComponent(name)
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                NSLog("Voice: failed to register \(name): \(String(describing: error))")
            }
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: UInt32 = 0xFF) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

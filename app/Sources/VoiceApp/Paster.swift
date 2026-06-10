import AppKit
import ApplicationServices

/// Where the user was typing when dictation started: the frontmost app and,
/// when Accessibility allows, the exact focused UI element. Restoring brings
/// that app back to front and re-focuses the field before pasting, so the text
/// lands where dictation began even if the user clicked elsewhere meanwhile.
struct FocusAnchor {
    let pid: pid_t
    let element: AXUIElement?

    static func capture() -> FocusAnchor? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var element: AXUIElement?
        if AXIsProcessTrusted() {
            var focused: CFTypeRef?
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString,
                                             &focused) == .success,
               let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() {
                element = (f as! AXUIElement)
            }
        }
        return FocusAnchor(pid: app.processIdentifier, element: element)
    }

    /// Best effort; returns true if the anchored app could be activated.
    @discardableResult
    func restore() -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if !app.isActive {
            app.activate()
        }
        if let element {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString,
                                         kCFBooleanTrue)
        }
        return true
    }
}

enum Paster {
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    /// Put text on the pasteboard, synthesize ⌘V into the frontmost app, then
    /// restore the previous pasteboard contents (unless `keepOnClipboard`).
    /// Falls back to leaving the text on the pasteboard when we can't
    /// synthesize keystrokes. When `anchor` is given, the original app/field
    /// is re-focused first.
    static func paste(_ text: String, anchor: FocusAnchor? = nil,
                      keepOnClipboard: Bool = false) {
        let pb = NSPasteboard.general
        let savedString = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        guard accessibilityTrusted else { return } // text stays on clipboard

        let needsRefocus = anchor.map {
            NSWorkspace.shared.frontmostApplication?.processIdentifier != $0.pid
        } ?? false
        anchor?.restore()

        // give the app switch a beat before ⌘V; restore the clipboard after
        DispatchQueue.main.asyncAfter(deadline: .now() + (needsRefocus ? 0.30 : 0.02)) {
            postCmdV()
            guard !keepOnClipboard else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let savedString {
                    pb.clearContents()
                    pb.setString(savedString, forType: .string)
                }
            }
        }
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @discardableResult
    private static func postCmdV() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

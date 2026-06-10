import AppKit

/// Hold a trigger key (right ⌘ or fn, alone) anywhere = push-to-talk; release
/// completes. Double-tap a trigger = locked hands-free recording; a single tap
/// completes it. A short arm delay plus "no other key during the hold" keeps
/// shortcuts (⌘C, fn+arrows) from starting dictation. Esc cancels.
///
/// Right ⌘ is the default-safe trigger: unlike fn it never collides with the
/// system 🌐/emoji key, including on double-press.
final class HotkeyMonitor {
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}
    var onTogglePause: () -> Void = {}   // ⌥P while dictating
    var onOpenApp: () -> Void = {}       // ⌥V anywhere
    /// Lets a bare trigger tap COMPLETE a session that is running but not
    /// key-held (locked mode, started from the menu, or out-of-band end).
    var isSessionActive: () -> Bool = { false }

    // live-read so Settings changes apply instantly
    var fnEnabled: () -> Bool = { true }
    var rightCmdEnabled: () -> Bool = { true }
    var shiftEnabled: () -> Bool = { false }

    private var monitors: [Any] = []
    private var armTimer: Timer?
    private var activeKey: Key?      // key currently held & dictating
    private var pendingKey: Key?     // key held, waiting for arm delay
    private var lastTap: (key: Key, at: Date)?

    enum Key { case shift, fn, rightCmd }

    private let armDelay: TimeInterval = 0.30
    private let doubleTapWindow: TimeInterval = 0.45
    private let rightCommandKeyCode: UInt16 = 54

    func startMonitoring() {
        stopMonitoring()
        let flagsGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        let keysGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleKeyDown(e)
        }
        let flagsLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e); return e
        }
        let keysLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleKeyDown(e); return e
        }
        monitors = [flagsGlobal, keysGlobal, flagsLocal, keysLocal].compactMap { $0 }
    }

    func stopMonitoring() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        disarm()
    }

    private func handleFlags(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pressed = pressedTrigger(e, flags: flags)
        let none = flags.isEmpty

        if let key = activeKey {
            // dictating: stop when the triggering key is released
            if !stillHeld(key, flags: flags) {
                activeKey = nil
                onStop()
            }
            return
        }

        if pressed != nil && isSessionActive() {
            // session running without a held key: this press completes it
            disarm()
            lastTap = nil
            onStop()
            return
        }

        if let key = pressed { arm(key) }
        else if none { keyWentUp() }
        else { disarm() }   // other/extra modifiers — a normal shortcut, not us
    }

    private func pressedTrigger(_ e: NSEvent, flags: NSEvent.ModifierFlags) -> Key? {
        if flags == .function, fnEnabled() { return .fn }
        if flags == .command, e.keyCode == rightCommandKeyCode, rightCmdEnabled() { return .rightCmd }
        if flags == .shift, shiftEnabled() { return .shift }
        return nil
    }

    private func stillHeld(_ key: Key, flags: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case .fn: return flags.contains(.function)
        case .rightCmd: return flags.contains(.command)
        case .shift: return flags.contains(.shift)
        }
    }

    private func handleKeyDown(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .option, e.keyCode == 9 { // ⌥V opens the Voice window
            onOpenApp()
            return
        }
        if activeKey != nil || isSessionActive() {
            if e.keyCode == 53 { // esc cancels dictation (held or locked)
                activeKey = nil
                onCancel()
            } else if mods == .option, e.keyCode == 35 { // ⌥P pause/resume
                onTogglePause()
            }
            return
        }
        disarm() // typing while a modifier is held — not a dictation hold
        lastTap = nil
    }

    private func arm(_ key: Key) {
        guard pendingKey != key else { return }
        disarm()
        pendingKey = key
        armTimer = Timer.scheduledTimer(withTimeInterval: armDelay, repeats: false) { [weak self] _ in
            guard let self, let key = self.pendingKey else { return }
            self.pendingKey = nil
            self.activeKey = key
            self.onStart()
        }
    }

    /// All keys released. A release while still pending (= a quick tap) counts
    /// toward double-tap-to-lock; the second tap starts a locked session.
    private func keyWentUp() {
        let tapped = pendingKey
        disarm()
        guard let key = tapped else { lastTap = nil; return }
        if let prev = lastTap, prev.key == key,
           Date().timeIntervalSince(prev.at) < doubleTapWindow {
            lastTap = nil
            onStart()   // locked: no held key, so only a tap/Esc/menu ends it
        } else {
            lastTap = (key, Date())
        }
    }

    private func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        pendingKey = nil
    }
}

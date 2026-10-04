import AppKit
import Carbon

final class KeyProbe: NSView {
    var received: [UInt16] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}

@main
struct ReadingKeyTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            runChecks()
            app.terminate(nil)
        }
        app.run()
    }

    static func runChecks() {
        var wheel = WheelPagingState()
        check(wheel.consume(delta: -20, precise: true, momentum: false, time: 1, eligible: true) == nil, "Accumulate trackpad motion")
        check(wheel.consume(delta: -20, precise: true, momentum: false, time: 1.1, eligible: true) == 1, "Down turns next")
        wheel.clearMotion()
        check(wheel.consume(delta: -80, precise: true, momentum: false, time: 1.2, eligible: true) == nil, "Throttle rapid motion")
        check(wheel.consume(delta: 80, precise: true, momentum: true, time: 2, eligible: true) == nil, "Ignore inertia")
        check(wheel.consume(delta: 1, precise: false, momentum: false, time: 3, eligible: true) == -1, "Up turns previous")
        check(wheel.consume(delta: -1, precise: false, momentum: false, time: 4, eligible: false) == nil, "Reject unfocused motion")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let previous = NSWorkspace.shared.frontmostApplication
        defer { previous?.activate(options: []) }
        let panel = ReadingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 200),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let probe = KeyProbe(frame: panel.contentView!.bounds)
        panel.contentView = probe
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(probe)
        app.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(2)
        while !app.isActive && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(app.isActive, "Test app activates for focused input")
        check(panel.isKeyWindow, "Isolated panel becomes key without activating the app")
        var returns = 0
        panel.onReturnToBooks = { returns += 1 }
        func event(_ code: Int, _ modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: UInt16(code))!
        }
        panel.sendEvent(event(kVK_DownArrow, [.function, .numericPad]))
        check(returns == 1 && probe.received.isEmpty, "Down returns before the page receives it")
        panel.sendEvent(event(kVK_DownArrow, repeatKey: true))
        check(returns == 1, "Held Down does not repeat navigation")
        for key in [kVK_LeftArrow, kVK_RightArrow] { panel.sendEvent(event(key)) }
        check(probe.received == [UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow)], "Left and Right pass to page responder")
        panel.sendEvent(event(kVK_DownArrow, .shift))
        check(returns == 1 && probe.received.last == UInt16(kVK_DownArrow), "Modified Down is not intercepted")
        panel.wheelContentView = probe
        panel.sendPageKey(next: true, timestamp: 5)
        check(probe.received.last == UInt16(kVK_RightArrow), "Wheel delivers native page key")
        panel.resignKey()
        check(!panel.performKeyEquivalent(with: event(kVK_DownArrow)) && returns == 1, "Inactive window does not return")
        panel.makeKey()
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        panel.beginSheet(sheet)
        panel.sendEvent(event(kVK_DownArrow))
        check(returns == 1, "Native sheet keeps keyboard handling")
        panel.endSheet(sheet)
        panel.orderOut(nil)
        print("PASS: Down navigation, no repeats, Left/Right forwarding, modifiers, focus and sheet handling")
    }

    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}

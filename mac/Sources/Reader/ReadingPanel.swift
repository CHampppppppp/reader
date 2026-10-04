import AppKit
import WebKit

struct WheelPagingState {
    private var accumulated = 0.0
    private var lastEvent = -Double.infinity
    private var lastTurn = -Double.infinity

    mutating func reset() { self = WheelPagingState() }
    mutating func clearMotion() { accumulated = 0; lastEvent = -Double.infinity }

    // Returns +1 for next page, -1 for previous. No timers or queued page turns.
    mutating func consume(delta: Double, precise: Bool, momentum: Bool, time: Double, eligible: Bool) -> Int? {
        guard eligible, delta.isFinite, time.isFinite else { reset(); return nil }
        guard !momentum, delta != 0 else { return nil }
        if time - lastEvent > 0.35 || accumulated * delta < 0 { accumulated = 0 }
        lastEvent = time
        guard time - lastTurn >= 0.3 else { accumulated = 0; return nil }
        accumulated += delta
        guard abs(accumulated) >= (precise ? 40 : 1) else { return nil }
        let direction = accumulated < 0 ? 1 : -1
        accumulated = 0
        lastTurn = time
        return direction
    }
}

final class ReaderCloseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ReadingPanel: NSPanel {
    var onHide: (() -> Void)?
    var onReturnToBooks: (() -> Void)?
    var wheelPagingEnabled = false { didSet { resetWheelPaging() } }
    var isReadingPage: (() -> Bool)?
    weak var wheelContentView: NSView?
    private var wheelState = WheelPagingState()
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleReadingAction(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleReadingAction(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard event.type == .keyDown, modifiers.isEmpty, NSApp.isActive, isKeyWindow,
              attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        let action: (() -> Void)?
        switch event.keyCode {
        case 126: action = onHide
        case 125: action = onReturnToBooks
        default: return false
        }
        guard let action else { return false }
        if !event.isARepeat { action() }
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        if handleWheel(event) { return }
        // Plain arrows follow the ordinary key-event path, before WebKit consumes them.
        if handleReadingAction(event) { return }
        if event.type == .leftMouseDown, event.modifierFlags.contains(.option), attachedSheet == nil {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }

    func resetWheelPaging() { wheelState.reset() }

    override func resignKey() {
        resetWheelPaging()
        super.resignKey()
    }

    private func handleWheel(_ event: NSEvent) -> Bool {
        guard event.type == .scrollWheel else { return false }
        guard wheelPagingEnabled, isReadingPage?() == true, let view = wheelContentView,
              let hit = contentView?.hitTest(event.locationInWindow), hit === view || hit.isDescendant(of: view) else {
            resetWheelPaging()
            return false
        }
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
            wheelState.clearMotion()
            return false
        }
        let eligible = NSApp.isActive && isKeyWindow && attachedSheet == nil && NSApp.modalWindow == nil
        if let direction = wheelState.consume(delta: Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
            momentum: !event.momentumPhase.isEmpty, time: event.timestamp, eligible: eligible) {
            sendPageKey(next: direction > 0, timestamp: event.timestamp)
        }
        // In wheel mode even unfocused wheel events over the reader must not scroll/turn it.
        return true
    }

    func sendPageKey(next: Bool, timestamp: TimeInterval) {
        guard let view = wheelContentView, makeFirstResponder(view) else { return }
        let characters = next ? "\u{f703}" : "\u{f702}"
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let key = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [.function, .numericPad],
                timestamp: timestamp, windowNumber: windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: next ? 124 : 123) else { continue }
            sendEvent(key)
        }
    }
}

final class TransparentWebView: WKWebView {
    override var isOpaque: Bool { false }
    private(set) var backgroundTransparencyAvailable = false

    override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        configureTransparentBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTransparentBackground()
    }

    private func configureTransparentBackground() {
        underPageBackgroundColor = .clear
        // underPageBackgroundColor only controls the underlay; macOS WebKit also paints
        // a native page background. This SPI has no equivalent public macOS API.
        // https://bugs.webkit.org/show_bug.cgi?id=221663
        if responds(to: NSSelectorFromString("_setDrawsBackground:")) ||
            responds(to: NSSelectorFromString("setDrawsBackground:")) {
            setValue(false, forKey: "drawsBackground")
            backgroundTransparencyAvailable = true
        }
    }
}

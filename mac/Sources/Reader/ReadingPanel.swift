import AppKit
import WebKit

final class ReadingPanel: NSPanel {
    var onReturnToBooks: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, event.keyCode == 53, modifiers == .command,
           isKeyWindow, attachedSheet == nil, let onReturnToBooks {
            if !event.isARepeat { onReturnToBooks() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.modifierFlags.contains(.option), attachedSheet == nil {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
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

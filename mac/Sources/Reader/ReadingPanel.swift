import AppKit
import WebKit

final class ReadingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
